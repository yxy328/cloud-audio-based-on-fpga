`timescale 1ns/1ps
// TTP229 note keys + FSR402 expression + APDS-9960 gestures + S1 guitar.
// Each note key has its own DDS/ADSR; FSR402 controls volume OR pitch.
// S1 plucks the guitar; S2 short release selects gesture timbre, long hold vibrato.
// E2=50MHz, H11=S1, H10=S2; K2/K1/L1=PCM5102 BCK/LRCK/DIN.
// APDS-9960: SCL=H4/J3 pin 23, SDA=G4/J3 pin 24 (2x20 header).
module top #(
    parameter VOLUME_SHIFT = 4,
    parameter STRING_LENGTH = 110,
    parameter KEY_DEBOUNCE_CYCLES = 250000,
    parameter TOUCH_STARTUP_US = 600000,
    parameter TOUCH_DEBOUNCE_MS = 2, // Note keys 1..7: short press/release confirmation.
    parameter TOUCH_MODE_DEBOUNCE_MS = 20, // Key 8 remains a deliberate mode control.
    parameter TOUCH_ACTIVE_LOW = 0,
    parameter ADSR_ATTACK_SAMPLES = 98,
    parameter ADSR_DECAY_SAMPLES = 3906,
    parameter [15:0] ADSR_SUSTAIN_LEVEL = 16'd39321,
    parameter ADSR_RELEASE_SAMPLES = 4883, // ~100ms, matches melody articulation
    parameter TOUCH_ADSR_RELEASE_SAMPLES = 488, // ~10ms tail for live note keys.
    parameter FSR_ENABLE = 1,
    parameter FSR_SAMPLE_HZ = 1000,
    parameter FSR_ADC_INVERT = 0, // Supplied one-channel module AO rises with force.
    parameter FSR_GAIN_REVERSE = 1, // Light touch loud, heavy touch quiet.
    parameter [9:0] FSR_ADC_ZERO = 10'd32,
    parameter [9:0] FSR_ADC_FULL = 10'd600,
    parameter [15:0] FSR_MIN_GAIN = 16'd16384,
    parameter [15:0] FSR_SLEW_STEP = 16'd64,
    parameter [15:0] FSR_PITCH_MIN_RATIO = 16'd32768, // One octave below base.
    parameter [15:0] FSR_PITCH_SLEW_STEP = 16'd64
) (
    input wire clk,
    input wire key_s1,
    input wire key_s2,
    input wire [7:0] touch_out,
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din,
    inout wire scl, sda,
    output wire touch_scl
);
    // Direct-output mode still requires SCL to stay at a defined level.
    // Match HUB75E GPIO mode: default active-low serial interface idles HIGH.
    // SDO is unused. TTP229 datasheet p14 explicitly forbids floating SCL.
    assign touch_scl = 1'b1;
    reg [5:0] power_count = 6'd0;
    wire resetn = &power_count;
    always @(posedge clk) begin
        if (!resetn)
            power_count <= power_count + 6'd1;
    end

    wire frame_ce;
    wire bck_rise_ce;
    wire bck_fall_ce;
    wire [5:0] bit_index;
    wire signed [15:0] audio_sample;
    wire signed [15:0] guitar_scaled_sample;
    wire [7:0] touch_keys;
    wire [7:0] touch_keys_raw;
    wire touch_ready;
    wire touch_idle = TOUCH_ACTIVE_LOW ? 1'b1 : 1'b0;
    wire [7:0] note_keys, note_keys_raw, mode_keys, mode_keys_raw;
    wire note_ready, mode_ready;
    assign touch_keys = {mode_keys[7],note_keys[6:0]};
    assign touch_keys_raw = {mode_keys_raw[7],note_keys_raw[6:0]};
    assign touch_ready = note_ready && mode_ready;
    wire [7:0] touch_note_gates = {1'b0,touch_keys[6:0]};
    wire fsr_pitch_mode;
    wire [15:0] fsr_target_pitch_ratio, fsr_pitch_ratio;
    wire [255:0] touch_phase_increments;
    wire [31:0] touch_samples;
    wire [9:0] fsr_adc_sample;
    wire fsr_adc_valid;
    wire [13:0] fsr_adc_raw;
    wire fsr_adc_timeout;
    wire [9:0] fsr_pressure_code;
    wire [15:0] fsr_target_gain;
    wire [15:0] fsr_gain;
    wire signed [15:0] touch_mix0, touch_mix1;

    // New gesture_top + gesture_audio replace the former discrete chain.
    // PCM uses this top's frame enable and joins the common output mixer.
    wire gesture_valid, dir_evaluated, gesture_ready;
    wire [2:0] start_dir, end_dir;
    wire signed [15:0] gesture_sample;
    gesture_top #(.AUDIO_VOLUME_SHIFT(VOLUME_SHIFT)) u_gesture (
        .clk(clk), .resetn(resetn), .frame_ce(frame_ce),
        .key_s1(1'b0), .key_s2(key_s2), .scl(scl), .sda(sda),
        .audio_sample(gesture_sample), .init_done(gesture_ready),
        .gesture_valid(gesture_valid), .dir_evaluated(dir_evaluated),
        .start_dir(start_dir), .end_dir(end_dir)
    );

    // Module AO must be attenuated to <=1V before the on-chip ADC PAD.
    gowin_fsr_adc #(
        .SAMPLE_HZ(FSR_SAMPLE_HZ)
    ) u_fsr_adc (
        .clk(clk), .resetn(resetn), .raw_value(fsr_adc_raw),
        .adc_sample(fsr_adc_sample), .sample_valid(fsr_adc_valid),
        .busy(), .timeout(fsr_adc_timeout)
    );
    fsr_dynamics #(
        .ADC_INVERT(FSR_ADC_INVERT), .GAIN_REVERSE(FSR_GAIN_REVERSE), .ADC_ZERO(FSR_ADC_ZERO),
        .ADC_FULL(FSR_ADC_FULL), .MIN_GAIN(FSR_MIN_GAIN),
        .SLEW_STEP(FSR_SLEW_STEP)
    ) u_fsr_dynamics (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .expression_enable(FSR_ENABLE && !fsr_pitch_mode),
        .adc_valid(fsr_adc_valid), .adc_sample(fsr_adc_sample),
        .pressure_code(fsr_pressure_code), .target_gain(fsr_target_gain), .gain(fsr_gain)
    );
    fsr_dynamics #(
        .ADC_INVERT(FSR_ADC_INVERT), .GAIN_REVERSE(1),
        .ADC_ZERO(FSR_ADC_ZERO), .ADC_FULL(FSR_ADC_FULL),
        .MIN_GAIN(FSR_PITCH_MIN_RATIO), .SLEW_STEP(FSR_PITCH_SLEW_STEP)
    ) u_fsr_pitch_dynamics (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .expression_enable(FSR_ENABLE && fsr_pitch_mode),
        .adc_valid(fsr_adc_valid), .adc_sample(fsr_adc_sample),
        .pressure_code(), .target_gain(fsr_target_pitch_ratio), .gain(fsr_pitch_ratio)
    );

    // Use separate confirmation times for notes/mode.
    // Mask unused inputs at their physical idle polarity in each reader.
    ttp229_gpio_input #(
        .CLK_FREQ(50_000_000), .STARTUP_US(TOUCH_STARTUP_US),
        .DEBOUNCE_MS(TOUCH_DEBOUNCE_MS), .ACTIVE_LOW(TOUCH_ACTIVE_LOW)
    ) u_touch_input (
        .clk(clk), .resetn(resetn), .enable(1'b1), .touch_out({touch_idle,touch_out[6:0]}),
        .keys_raw(note_keys_raw), .keys_stable(note_keys), .sample_valid(), .ready(note_ready)
    );
    ttp229_gpio_input #(
        .CLK_FREQ(50_000_000), .STARTUP_US(TOUCH_STARTUP_US),
        .DEBOUNCE_MS(TOUCH_MODE_DEBOUNCE_MS), .ACTIVE_LOW(TOUCH_ACTIVE_LOW)
    ) u_touch_mode_input (
        .clk(clk), .resetn(resetn), .enable(1'b1), .touch_out({touch_out[7],{7{touch_idle}}}),
        .keys_raw(mode_keys_raw), .keys_stable(mode_keys), .sample_valid(), .ready(mode_ready)
    );
    fsr_mode_select u_fsr_mode (
        .clk(clk), .resetn(resetn), .keys_ready(touch_ready),
        .key8_raw(touch_keys_raw[7]), .key8_stable(touch_keys[7]),
        .pitch_mode(fsr_pitch_mode)
    );

    clk_div u_clk_div (
        .clk(clk), .resetn(resetn), .bck(i2s_bck), .lrck(i2s_lrck),
        .bck_rise_ce(bck_rise_ce), .bck_fall_ce(bck_fall_ce),
        .frame_ce(frame_ce), .bit_index(bit_index)
    );
    wire signed [15:0] guitar_sample;
    geita #(.STRING_LENGTH(STRING_LENGTH), .DEBOUNCE_CYCLES(KEY_DEBOUNCE_CYCLES)) u_string (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .key_s1(key_s1), .sample(guitar_sample)
    );
    assign guitar_scaled_sample = guitar_sample >>> VOLUME_SHIFT;
    // OUT1..7 = C4 D4 E4 F4 G4 A4 B4; OUT8 only switches expression mode.
    // Fs=48828.125Hz. Pressure pitch changes preserve each DDS phase.
    localparam [255:0] TOUCH_INCREMENTS = {
        32'd0, 32'd43442435, 32'd38702809, 32'd34480283,
        32'd30718440, 32'd28994347, 32'd25831026, 32'd23012828
    };
    fsr_pitch_scaler #(.NOTE_INCREMENTS(TOUCH_INCREMENTS[223:0])) u_fsr_pitch_scaler (
        .clk(clk), .resetn(resetn), .pitch_ratio(fsr_pitch_ratio),
        .phase_increments(touch_phase_increments)
    );
    genvar touch_group;
    generate
        for (touch_group=0; touch_group<2; touch_group=touch_group+1) begin: touch_voices
            poly_synth #(
                .VOICE_COUNT(touch_group == 0 ? 4 : 3),
                .VOLUME_SHIFT(VOLUME_SHIFT),
                .ATTACK_SAMPLES(ADSR_ATTACK_SAMPLES),
                .DECAY_SAMPLES(ADSR_DECAY_SAMPLES),
                .SUSTAIN_LEVEL(ADSR_SUSTAIN_LEVEL),
                .RELEASE_SAMPLES(TOUCH_ADSR_RELEASE_SAMPLES)
            ) u_synth (
                .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
                .gates(touch_note_gates[touch_group*4 +: 4]),
                .phase_increments(touch_phase_increments[touch_group*128 +: 128]),
                .sample(touch_samples[touch_group*16 +: 16]),
                .voice_samples(), .envelope_gains(), .envelope_states(), .active(), .clipped()
            );
        end
    endgenerate
    generate
        if (FSR_ENABLE) begin: pressure_enabled
            wire signed [15:0] mixed_touch;
            audio_mixer u_touch_mix (
                .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
                .sample0(touch_samples[15:0]), .sample1(touch_samples[31:16]),
                .sample2(16'sd0), .sample3(16'sd0),
                .sample_out(mixed_touch), .clipped()
            );
            envelope_gain #(.VOLUME_SHIFT(0)) u_expression (
                .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
                .sample_in(mixed_touch), .gain(fsr_gain), .sample_out(touch_mix0)
            );
            assign touch_mix1 = 16'sd0;
        end else begin: pressure_bypass
            // Exact original audio path for setups without an ADC.
            assign touch_mix0 = touch_samples[15:0];
            assign touch_mix1 = touch_samples[31:16];
        end
    endgenerate
    // At the default 1/16 gain touch, guitar and gesture voices fit in PCM.
    // Saturation still protects configurations with a higher compile-time gain.
    audio_mixer u_output_mix (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .sample0(guitar_scaled_sample), .sample1(touch_mix0),
        .sample2(touch_mix1), .sample3(gesture_sample),
        .sample_out(audio_sample), .clipped()
    );
    i2s_tx u_i2s_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
// Diagnostic observations: one master-clock delay, no audio control changes.
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_key_s1;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_key_s2;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_resetn;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_touch_ready;
    (* syn_preserve = 1, syn_keep = 1 *) reg [7:0] probe_touch_out;
    (* syn_preserve = 1, syn_keep = 1 *) reg [7:0] probe_touch_keys;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_fsr_pitch_mode;
    (* syn_preserve = 1, syn_keep = 1 *) reg [15:0] probe_fsr_gain;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_frame_ce;
    (* syn_preserve = 1, syn_keep = 1 *) reg [15:0] probe_guitar_scaled_sample;
    (* syn_preserve = 1, syn_keep = 1 *) reg [15:0] probe_touch_mix0;
    (* syn_preserve = 1, syn_keep = 1 *) reg [15:0] probe_gesture_sample;
    (* syn_preserve = 1, syn_keep = 1 *) reg [15:0] probe_audio_sample;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_gesture_ready;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_i2s_bck;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_i2s_lrck;
    (* syn_preserve = 1, syn_keep = 1 *) reg [0:0] probe_i2s_din;
    always @(posedge clk) begin
        if (!resetn) begin
            probe_key_s1 <= 0;
            probe_key_s2 <= 0;
            probe_resetn <= 0;
            probe_touch_ready <= 0;
            probe_touch_out <= 0;
            probe_touch_keys <= 0;
            probe_fsr_pitch_mode <= 0;
            probe_fsr_gain <= 0;
            probe_frame_ce <= 0;
            probe_guitar_scaled_sample <= 0;
            probe_touch_mix0 <= 0;
            probe_gesture_sample <= 0;
            probe_audio_sample <= 0;
            probe_gesture_ready <= 0;
            probe_i2s_bck <= 0;
            probe_i2s_lrck <= 0;
            probe_i2s_din <= 0;
        end else begin
            probe_key_s1 <= key_s1;
            probe_key_s2 <= key_s2;
            probe_resetn <= resetn;
            probe_touch_ready <= touch_ready;
            probe_touch_out <= touch_out;
            probe_touch_keys <= touch_keys;
            probe_fsr_pitch_mode <= fsr_pitch_mode;
            probe_fsr_gain <= fsr_gain;
            probe_frame_ce <= frame_ce;
            probe_guitar_scaled_sample <= guitar_scaled_sample;
            probe_touch_mix0 <= touch_mix0;
            probe_gesture_sample <= gesture_sample;
            probe_audio_sample <= audio_sample;
            probe_gesture_ready <= gesture_ready;
            probe_i2s_bck <= i2s_bck;
            probe_i2s_lrck <= i2s_lrck;
            probe_i2s_din <= i2s_din;
        end
    end
endmodule

