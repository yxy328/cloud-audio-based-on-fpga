`timescale 1ns/1ps
// Seven note keys + pressure + score/panel + APDS gestures + remote guitar.
// Each note key has its own DDS/ADSR; FSR402 controls volume OR pitch.
// S1 plays/stops; short S2 restarts outside XY / selects XY preset inside;
// long S2 switches panel mode. XY reference settings are display-only.
// E2=50MHz, H11=S1, H10=S2; K2/K1/L1=PCM5102 BCK/LRCK/DIN.
module top #(
    // Live touch, gesture and remote pluck events generate audio in FPGA.
    // Optional score audition is an explicitly separate demonstration mode.
    parameter ENABLE_DEMO_SCORE = 0,
    parameter VOLUME_SHIFT = 4,
    parameter KEY_CONFIRM_CYCLES = 50_000,
    parameter TOUCH_STARTUP_US = 600000,
    parameter TOUCH_DEBOUNCE_MS = 2, // Note keys 1..7: short press/release confirmation.
    parameter TOUCH_MODE_DEBOUNCE_MS = 20, // Key 8 remains a deliberate mode control.
    parameter TOUCH_ACTIVE_LOW = 0,
    parameter ADSR_ATTACK_SAMPLES = 98,
    parameter ADSR_DECAY_SAMPLES = 3906,
    parameter [15:0] ADSR_SUSTAIN_LEVEL = 16'd39321,
    parameter ADSR_RELEASE_SAMPLES = 4883, // ~100ms, matches melody articulation
    parameter TOUCH_ADSR_RELEASE_SAMPLES = 488, // ~10ms tail for live note keys.
    parameter SONG_BEAT_SAMPLES = 19531,
    parameter SONG_GAP_SAMPLES = 4883,
    parameter SONG_INTRO_SAMPLES = 1953,
    parameter SONG_TAIL_SAMPLES = 17100,
    parameter FSR_ENABLE = 1,
    parameter FSR_SAMPLE_HZ = 1000,
    parameter FSR_ADC_INVERT = 0, // Supplied one-channel module AO rises with force.
    parameter FSR_GAIN_REVERSE = 1, // Light touch loud, heavy touch quiet.
    parameter [9:0] FSR_ADC_ZERO = 10'd32,
    parameter [9:0] FSR_ADC_FULL = 10'd600,
    parameter [15:0] FSR_MIN_GAIN = 16'd16384,
    parameter [15:0] FSR_SLEW_STEP = 16'd64,
    parameter [15:0] FSR_PITCH_MIN_RATIO = 16'd32768, // One octave below base.
    parameter [15:0] FSR_PITCH_SLEW_STEP = 16'd64,
    parameter integer HC05_BAUD = 9600,
    parameter integer GUIDE_LEAD_MS = 1500,
    parameter GUITAR_STRING_LENGTH = 110,
    parameter IR_FILTER_CYCLES = 50000,
    parameter SENSOR_VOLUME_SHIFT = VOLUME_SHIFT+2,
    parameter integer DISPLAY_HOLD_FRAMES = 48828
) (
    input wire clk,
    input wire key_s1,
    input wire key_s2,
    input wire [7:0] touch_out,
    input wire [7:0] ir_beam,
    input wire hc05_rx,
    output wire hc05_tx,
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din,
    output wire touch_scl,
    inout wire scl, sda,
    output wire hub_R1, hub_G1, hub_B1,
    output wire hub_R2, hub_G2, hub_B2,
    output wire hub_A, hub_B, hub_C, hub_D, hub_E,
    output wire hub_CK, hub_ST, hub_OE
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

    wire s1_pressed;
    wire s2_pressed;
    wire s2_level, s2_restart;
    wire [1:0] visual_mode;
    wire xy_write;
    wire [1:0] xy_ratio,xy_phase,reference_ratio,reference_phase;
    // Keep the historical audition-mode press timing; production short S2
    // waits for release so a long display-switch hold never restarts a score.
    wire s2_action = ENABLE_DEMO_SCORE ? s2_pressed : s2_restart;
    wire [3:0] voice_gates;
    wire [127:0] phase_increments;
    wire frame_ce;
    wire bck_rise_ce;
    wire bck_fall_ce;
    wire [5:0] bit_index;
    wire signed [15:0] audio_sample;
    wire signed [15:0] song_sample;
    wire [7:0] touch_keys;
    wire [7:0] touch_keys_raw;
    wire touch_ready;
    wire touch_idle = TOUCH_ACTIVE_LOW ? 1'b1 : 1'b0;
    wire [7:0] note_keys, note_keys_raw, mode_keys, mode_keys_raw;
    wire note_ready, mode_ready;
    assign touch_keys = {mode_keys[7],note_keys[6:0]};
    assign touch_keys_raw = {mode_keys_raw[7],note_keys_raw[6:0]};
    assign touch_ready = note_ready && mode_ready;
    // Downloaded notes drive the same independent DDS/ADSR lanes as the pads
    // only after an explicit AUDITION. No audio samples are stored in a score.
    wire [6:0] audition_keys;
    wire [7:0] touch_note_gates = {1'b0,(touch_keys[6:0] | audition_keys)};
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
    wire song_playing;
    wire [3:0] song_active;
    wire [7:0] touch_active;
    wire [55:0] touch_note_map;
    wire [223:0] touch_base_increments;
    wire builtin_playing, downloaded_valid, downloaded_playing, downloaded_gate;
    wire downloaded_audition;
    wire [3:0] builtin_gates;
    wire [127:0] builtin_increments;
    wire [31:0] downloaded_increment;
    wire [6:0] song_guide_keys;
    wire guide_ms_tick, guide_reset, guide_note_spawn, guide_note_ready;
    wire [6:0] guide_spawn_keys;
    wire [15:0] guide_spawn_delay;
    wire recording_busy, builtin_play, builtin_stop;
    wire guitar_pluck, gesture_vibrato, gesture_bank;
    wire [2:0] gesture_timbre;
    wire [63:0] touch_adsr;
    wire [129:0] sensor_adsr;
    wire bend_write,bend_reset;
    wire [2:0] bend_index;
    wire [15:0] bend_ratio;
    wire ir_note_valid, sensor_test32, sensor_overrun;
    wire [2:0] ir_note_index;
    wire [7:0] ir_blocked, ir_armed;
    wire [31:0] sensor_voice_active;
    wire [5:0] sensor_voice_count;
    wire signed [15:0] guitar_sample, guitar_scaled_sample, gesture_sample;
    wire signed [15:0] extra_sample;
    wire gesture_ready, gesture_valid, dir_evaluated;
    wire [2:0] start_dir, end_dir;
    assign song_playing=builtin_playing || downloaded_playing;
    assign voice_gates=ENABLE_DEMO_SCORE ? (downloaded_valid ? {3'd0,downloaded_gate} : builtin_gates) : 4'd0;
    assign phase_increments=downloaded_valid ? {96'd0,downloaded_increment} : builtin_increments;
    assign audition_keys=(downloaded_audition && downloaded_gate) ? song_guide_keys : 7'd0;
    // Include synchronized raw pads, debounced gates, and release tails.
    hc05_keymap #(.DEFAULT_A(ADSR_ATTACK_SAMPLES),.DEFAULT_D(ADSR_DECAY_SAMPLES),
        .DEFAULT_S(ADSR_SUSTAIN_LEVEL),.DEFAULT_R(TOUCH_ADSR_RELEASE_SAMPLES),.BAUD(HC05_BAUD),.ENABLE_DEMO_SCORE(ENABLE_DEMO_SCORE),
        .ENABLE_LOOKAHEAD(!ENABLE_DEMO_SCORE),.LOOKAHEAD_MS(GUIDE_LEAD_MS)) u_keymap (
        .clk(clk),.resetn(resetn),.rx(hc05_rx),.tx(hc05_tx),
        .keys_ready(touch_ready),
        .song_busy(song_playing || (|song_active) || s1_pressed || s2_action),
        .notes_busy((|touch_keys_raw[6:0]) || (|touch_keys[6:0]) || (|touch_active[6:0])),
        .recording(1'b0),.note_map(touch_note_map),
        .touch_keys(touch_keys[6:0]),.pressure_mode(fsr_pitch_mode),
        .volume_gain(fsr_gain),.pitch_ratio(fsr_pitch_ratio),
        .toggle_play(s1_pressed),.restart(s2_action),.rec_busy(recording_busy),
        .downloaded_valid(downloaded_valid),.downloaded_playing(downloaded_playing),
        .downloaded_audition(downloaded_audition),
        .downloaded_gate(downloaded_gate),.downloaded_increment(downloaded_increment),
        .guide_keys(song_guide_keys),.guide_ms_tick(guide_ms_tick),.guide_reset(guide_reset),
        .note_spawn(guide_note_spawn),.spawn_keys(guide_spawn_keys),
        .spawn_delay_ms(guide_spawn_delay),.note_ready(guide_note_ready),
        .builtin_play(builtin_play),.builtin_stop(builtin_stop),
        .guitar_pluck(guitar_pluck),.gesture_timbre(gesture_timbre),
        .gesture_vibrato(gesture_vibrato),.gesture_bank(gesture_bank),
        .sensor_test32(sensor_test32),.touch_adsr(touch_adsr),.sensor_adsr(sensor_adsr),
        .bend_write(bend_write),.bend_reset(bend_reset),.bend_index(bend_index),.bend_ratio(bend_ratio),
        .xy_write(xy_write),.xy_ratio(xy_ratio),.xy_phase(xy_phase)
    );
    // Sensor, score/panel and all voices share one 50MHz clock and frame CE.
    // S1/S2 retain their score controls; Bluetooth controls the new voices.
    ir_strings #(.FILTER_CYCLES(IR_FILTER_CYCLES)) u_ir (
        .clk(clk),.rst_n(resetn),.beam_in(ir_beam),
        .blocked(ir_blocked),.armed(ir_armed),
        .note_valid(ir_note_valid),.note_index(ir_note_index)
    );
    gesture_top #(.AUDIO_VOLUME_SHIFT(SENSOR_VOLUME_SHIFT),.EXTERNAL_CONTROL(1)) u_gesture (
        .clk(clk),.resetn(resetn),.frame_ce(frame_ce),
        .key_s1(1'b0),.key_s2(1'b0),.scl(scl),.sda(sda),
        .control_timbre(gesture_timbre),.control_vibrato(gesture_vibrato),
        .control_bank(gesture_bank),.audio_sample(gesture_sample),
        .ir_note_valid(ir_note_valid),.ir_note_index(ir_note_index),.test32(sensor_test32),.adsr_config(sensor_adsr),
        .voice_active(sensor_voice_active),.voice_count(sensor_voice_count),.overrun(sensor_overrun),
        .init_done(gesture_ready),.gesture_valid(gesture_valid),
        .dir_evaluated(dir_evaluated),.start_dir(start_dir),.end_dir(end_dir)
    );
    geita #(.STRING_LENGTH(GUITAR_STRING_LENGTH),.EXTERNAL_TRIGGER(1)) u_string (
        .clk(clk),.resetn(resetn),.sample_ce(frame_ce),.key_s1(1'b0),
        .pluck(guitar_pluck),.sample(guitar_sample)
    );
    assign guitar_scaled_sample = guitar_sample >>> VOLUME_SHIFT;
    audio_mixer u_extra_mix (
        .clk(clk),.resetn(resetn),.sample_ce(frame_ce),
        .sample0(gesture_sample),.sample1(guitar_scaled_sample),
        .sample2(16'sd0),.sample3(16'sd0),.sample_out(extra_sample),.clipped()
    );
    // Score timing and panel scan use clock enables on the same 50MHz clock.
    // Dropping playing on guide_reset clears pending pixels without resetting scan.
    hub75e_rhythm_display #(.LEAD_MS(GUIDE_LEAD_MS),.ENABLE_AUDIO_VISUAL(1)) u_guide_display (
        .clk(clk),.resetn(resetn),.touch_keys(touch_keys[6:0]),
        .guide_keys(song_guide_keys),.playing(downloaded_playing && !guide_reset),
        .ms_tick(guide_ms_tick),.note_spawn(guide_note_spawn),
        .spawn_keys(guide_spawn_keys),.spawn_delay_ms(guide_spawn_delay),
        .visual_mode(visual_mode),.reference_ratio(reference_ratio),.reference_phase(reference_phase),
        .sample_ce(frame_ce),.mixed_sample(audio_sample),
        .touch0(touch_mix0),.touch1(touch_mix1),
        .sensor_sample(gesture_sample),.guitar_sample(guitar_scaled_sample),
        .note_ready(guide_note_ready),.overflow(),
        .hub_R1(hub_R1),.hub_G1(hub_G1),.hub_B1(hub_B1),
        .hub_R2(hub_R2),.hub_G2(hub_G2),.hub_B2(hub_B2),
        .hub_A(hub_A),.hub_B(hub_B),.hub_C(hub_C),.hub_D(hub_D),.hub_E(hub_E),
        .hub_CK(hub_CK),.hub_ST(hub_ST),.hub_OE(hub_OE)
    );
    midi_note_lut #(.BLOCK_ROM(1)) u_note_lut (
        .clk(clk),.resetn(resetn),.note_map(touch_note_map),
        .phase_increments(touch_base_increments)
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

    // Reuse the shared reader with separate confirmation times for notes/mode.
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

    button_filter #(.CONFIRM_CYCLES(KEY_CONFIRM_CYCLES)) u_s1 (
        .clk(clk), .resetn(resetn), .button(key_s1),
        .level(), .pressed(s1_pressed)
    );
    button_filter #(.CONFIRM_CYCLES(KEY_CONFIRM_CYCLES)) u_s2 (
        .clk(clk), .resetn(resetn), .button(key_s2),
        .level(s2_level), .pressed(s2_pressed)
    );
    display_mode_control #(.HOLD_FRAMES(DISPLAY_HOLD_FRAMES)) u_display_mode (
        .clk(clk),.resetn(resetn),.frame_ce(frame_ce),.button_level(s2_level),
        .restart(s2_restart),.visual_mode(visual_mode),
        .xy_write(xy_write),.xy_ratio(xy_ratio),.xy_phase(xy_phase),
        .reference_ratio(reference_ratio),.reference_phase(reference_phase)
    );
    twinkle_sequencer #(
        .BEAT_SAMPLES(SONG_BEAT_SAMPLES), .GAP_SAMPLES(SONG_GAP_SAMPLES),
        .INTRO_SAMPLES(SONG_INTRO_SAMPLES), .TAIL_SAMPLES(SONG_TAIL_SAMPLES)
    ) u_control (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .toggle_play(ENABLE_DEMO_SCORE && ((s1_pressed && !downloaded_valid) || (builtin_stop && builtin_playing))),
        .restart(ENABLE_DEMO_SCORE && ((s2_action && !downloaded_valid) || builtin_play)),
        .playing(builtin_playing), .note_index(), .gates(builtin_gates), .phase_increments(builtin_increments)
    );
    clk_div u_clk_div (
        .clk(clk), .resetn(resetn), .bck(i2s_bck), .lrck(i2s_lrck),
        .bck_rise_ce(bck_rise_ce), .bck_fall_ce(bck_fall_ce),
        .frame_ce(frame_ce), .bit_index(bit_index)
    );
    poly_synth #(
        .VOLUME_SHIFT(VOLUME_SHIFT),
        .ATTACK_SAMPLES(ADSR_ATTACK_SAMPLES),
        .DECAY_SAMPLES(ADSR_DECAY_SAMPLES),
        .SUSTAIN_LEVEL(ADSR_SUSTAIN_LEVEL),
        .RELEASE_SAMPLES(ADSR_RELEASE_SAMPLES)
    ) u_synth (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .gates(voice_gates),.adsr_config(64'd0), .phase_increments(phase_increments), .sample(song_sample),
        .voice_samples(), .envelope_gains(), .envelope_states(), .active(song_active), .clipped()
    );
    // OUT1..7 default to C4 D4 E4 F4 G4 A4 B4; HC-05 can remap them.
    // Fs=48828.125Hz. Pressure pitch changes preserve each DDS phase.
    fsr_pitch_scaler #(.PER_VOICE_BEND(1)) u_fsr_pitch_scaler (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce), .pitch_ratio(fsr_pitch_ratio),
        .note_increments(touch_base_increments),
        .bend_write(bend_write),.bend_reset(bend_reset),.bend_index(bend_index),.bend_ratio(bend_ratio),
        .phase_increments(touch_phase_increments)
    );
    genvar touch_group;
    generate
        for (touch_group=0; touch_group<2; touch_group=touch_group+1) begin: touch_voices
            poly_synth #(
                .PIPELINE_OSCILLATOR(1),
                .RUNTIME_ADSR(1),
                .VOLUME_SHIFT(VOLUME_SHIFT),
                .ATTACK_SAMPLES(ADSR_ATTACK_SAMPLES),
                .DECAY_SAMPLES(ADSR_DECAY_SAMPLES),
                .SUSTAIN_LEVEL(ADSR_SUSTAIN_LEVEL),
                .RELEASE_SAMPLES(TOUCH_ADSR_RELEASE_SAMPLES)
            ) u_synth (
                .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
                .gates(touch_note_gates[touch_group*4 +: 4]),.adsr_config(touch_adsr),
                .phase_increments(touch_phase_increments[touch_group*128 +: 128]),
                .sample(touch_samples[touch_group*16 +: 16]),
                .voice_samples(), .envelope_gains(), .envelope_states(),
                .active(touch_active[touch_group*4 +: 4]), .clipped()
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
    // Default gain leaves room for seven keys, gestures and a guitar string.
    // Saturation still protects configurations with a higher compile-time gain.
    audio_mixer u_output_mix (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .sample0(song_sample), .sample1(touch_mix0),
        .sample2(touch_mix1), .sample3(extra_sample),
        .sample_out(audio_sample), .clipped()
    );
    i2s_tx u_i2s_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
endmodule
