`timescale 1ns/1ps
// S1 selects C4/D4/E4/F4 or G4/A4/B4/C5; completed gestures play a note.
// Reuse the standalone project's clock divider, sine table and I2S transmitter.
module gesture_audio #(
    parameter [16:0] NOTE_FRAMES = 17'd14648, // 299.991ms at 48828.125Hz
    parameter [16:0] PIANO_FRAMES = 17'd58594, // 1.200s, including a decaying tail
    parameter [16:0] FLUTE_FRAMES = 17'd24414, // 0.500s breath
    parameter [16:0] UKULELE_FRAMES = 17'd34180, // 0.700s pluck
    parameter [16:0] DRUM_FRAMES = 17'd19531, // 0.400s drum tail
    parameter VOLUME_SHIFT = 4,             // initial amplitude 1/16
    parameter [19:0] KEY_DEBOUNCE_CYCLES = 20'd1000000, // 20ms at 50MHz
    parameter [25:0] LONG_PRESS_CYCLES = 26'd40000000 // 0.8s after debounce
)(
    input wire clk, resetn, sensor_ready,
    input wire gesture_valid, dir_evaluated,
    input wire [2:0] start_dir, end_dir,
    input wire key_s1, key_s2,
    output wire note_bank, vibrato_enabled,
    output wire [2:0] timbre_selected,
    output wire i2s_bck, i2s_lrck, i2s_din
);
    (* syn_preserve = 1 *) reg key_meta;
    (* syn_preserve = 1 *) reg key_sync;
    always @(posedge clk) begin
        if (!resetn) begin key_meta <= 0; key_sync <= 0; end
        else begin key_meta <= key_s1; key_sync <= key_meta; end
    end

    // S2: short release selects the next timbre; a long hold toggles vibrato
    // once. A long release cannot also change timbre. Both edges are debounced.
    (* syn_preserve = 1 *) reg tone_meta;
    (* syn_preserve = 1 *) reg tone_sync;
    reg tone_stable, vibrato_selection, tone_long_fired;
    reg [2:0] tone_selection;
    reg [19:0] tone_count;
    reg [25:0] tone_hold_count;
    wire tone_change = (tone_sync != tone_stable) &&
                       (tone_count == KEY_DEBOUNCE_CYCLES - 1'b1);
    wire tone_press = tone_change && tone_sync;
    wire tone_release = tone_change && !tone_sync;
    wire tone_long = tone_stable && !tone_release && !tone_long_fired &&
                     (tone_hold_count == LONG_PRESS_CYCLES - 1'b1);
    wire tone_short = tone_release && !tone_long_fired;
    // Like S1, expose the pending change for same-clock OLED/note agreement.
    wire [2:0] next_timbre = (tone_selection == 3'd4) ? 3'd0 : tone_selection + 1'b1;
    assign timbre_selected = tone_short ? next_timbre : tone_selection;
    assign vibrato_enabled = vibrato_selection ^ tone_long;
    always @(posedge clk) begin
        if (!resetn) begin
            tone_meta <= 0; tone_sync <= 0; tone_stable <= 0;
            tone_selection <= 0; tone_count <= 0;
            tone_hold_count <= 0; tone_long_fired <= 0; vibrato_selection <= 0;
        end else begin
            tone_meta <= key_s2; tone_sync <= tone_meta;
            if (tone_sync == tone_stable) tone_count <= 0;
            else if (tone_change) begin
                tone_stable <= tone_sync; tone_count <= 0;
            end else tone_count <= tone_count + 1'b1;
            if (tone_short) tone_selection <= next_timbre;
            if (!tone_stable || tone_press || tone_release) begin
                tone_hold_count <= 0; tone_long_fired <= 0;
            end else if (!tone_long_fired) begin
                if (tone_long) begin
                    tone_long_fired <= 1;
                    vibrato_selection <= ~vibrato_selection;
                end else tone_hold_count <= tone_hold_count + 1'b1;
            end
        end
    end

    // Require 20ms of stable high AND stable low. Hold S1 for bank 2;
    // release for bank 1. Contact bounce cannot repeatedly switch the group.
    reg key_stable;
    reg [19:0] debounce_count;
    wire bank_change = (key_sync != key_stable) &&
                       (debounce_count == KEY_DEBOUNCE_CYCLES - 1'b1);
    // Expose the pending switch to both audio and OLED on the same clock, even
    // if a completed gesture coincides with an accepted press or release.
    assign note_bank = bank_change ? key_sync : key_stable;
    always @(posedge clk) begin
        if (!resetn) begin
            key_stable <= 0; debounce_count <= 0;
        end else begin
            if (key_sync == key_stable) debounce_count <= 0;
            else if (debounce_count == KEY_DEBOUNCE_CYCLES - 1'b1) begin
                key_stable <= key_sync; debounce_count <= 0;
            end else debounce_count <= debounce_count + 1'b1;
        end
    end

    wire frame_ce, bck_fall_ce;
    wire [5:0] bit_index;
    clk_div u_clock (
        .clk(clk), .resetn(resetn), .bck(i2s_bck), .lrck(i2s_lrck),
        .bck_rise_ce(), .bck_fall_ce(bck_fall_ce), .frame_ce(frame_ce),
        .bit_index(bit_index)
    );

    reg [31:0] event_inc;
    always @(*) begin
        case ({start_dir, end_dir})
            {3'd1,3'd2}: event_inc = note_bank ? 32'd34480283 : 32'd23012828; // SOL / DO
            {3'd3,3'd4}: event_inc = note_bank ? 32'd38702809 : 32'd25831026; // LA / RE
            {3'd2,3'd1}: event_inc = note_bank ? 32'd43442435 : 32'd28994347; // SI / MI
            {3'd4,3'd3}: event_inc = note_bank ? 32'd46025656 : 32'd30718440; // high DO / FA
            default: event_inc = 0;
        endcase
    end
    wire trigger_note = sensor_ready && gesture_valid && dir_evaluated && (event_inc != 0);
    reg [16:0] remaining;
    reg [31:0] note_inc;
    reg [2:0] note_timbre;
    reg [16:0] event_frames;
    always @(*) begin
        case (timbre_selected)
            3'd1: event_frames = PIANO_FRAMES;
            3'd2: event_frames = FLUTE_FRAMES;
            3'd3: event_frames = UKULELE_FRAMES;
            3'd4: event_frames = DRUM_FRAMES;
            default: event_frames = NOTE_FRAMES;
        endcase
    end
    always @(posedge clk) begin
        if (!resetn) begin remaining <= 0; note_inc <= 32'd23012828; note_timbre <= 0; end
        else if (trigger_note) begin
            // Retain single-cycle events even between audio frames. Newest
            // gesture changes pitch and restarts the duration, without a queue.
            remaining <= event_frames;
            note_inc <= event_inc; note_timbre <= timbre_selected;
        end else if (frame_ce && remaining != 0) remaining <= remaining - 1'b1;
    end

    // Pitch is latched per gesture: switching group must not retune a note
    // already sounding or extend its duration.
    wire [31:0] phase_inc;
    vibrato u_vibrato (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .enabled(vibrato_enabled), .nominal_inc(note_inc), .phase_inc(phase_inc)
    );
    wire signed [15:0] sine_sample;
    nco_sine u_sine (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .phase_inc(phase_inc), .sample(sine_sample)
    );

    wire signed [15:0] piano_sample, partial2, partial3, partial4;
    piano_voice u_piano (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .trigger_note(trigger_note), .phase_inc(phase_inc),
        .fundamental(sine_sample), .sample(piano_sample),
        .partial2(partial2), .partial3(partial3), .partial4(partial4)
    );
    wire signed [15:0] flute_sample, ukulele_sample, drum_sample;
    extra_voices u_extra (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce), .trigger_note(trigger_note),
        .phase_inc(phase_inc), .event_inc(event_inc), .fundamental(sine_sample),
        .partial2(partial2), .partial3(partial3), .partial4(partial4),
        .flute_sample(flute_sample), .ukulele_sample(ukulele_sample), .drum_sample(drum_sample)
    );
    // A note retains its timbre when S2 changes the next-note selection.
    reg signed [15:0] sine_frame, piano_frame;
    reg [2:0] timbre_frame;
    reg [8:0] gain_input_frame;
    // Match the new instruments' waveform/envelope stage for every timbre.
    always @(posedge clk) begin
        if (!resetn) begin sine_frame <= 0; piano_frame <= 0; timbre_frame <= 0; gain_input_frame <= 0; end
        else if (frame_ce) begin
            sine_frame <= sine_sample; piano_frame <= piano_sample;
            timbre_frame <= note_timbre; gain_input_frame <= gain;
        end
    end
    reg signed [15:0] voice_sample;
    always @(*) begin
        case (timbre_frame)
            3'd1: voice_sample = piano_frame;
            3'd2: voice_sample = flute_sample;
            3'd3: voice_sample = ukulele_sample;
            3'd4: voice_sample = drum_sample;
            default: voice_sample = sine_frame;
        endcase
    end

    // 256-frame (~5.24ms) attack/release avoids abruptly gating full amplitude.
    // A new pitch keeps phase and gain continuous; silence still sends I2S zero.
    reg [8:0] gain;
    wire sounding = (remaining != 0);
    always @(posedge clk) begin
        if (!resetn) gain <= 0;
        else if (frame_ce) begin
            if (sounding && gain < 9'd256) gain <= gain + 1'b1;
            else if (!sounding && gain != 0) gain <= gain - 1'b1;
        end
    end
    // Separate the oscillator/partial-envelope calculation from final gain.
    // Capture both operands together once per sample to preserve the exact
    // waveform. Together with the stage above, latency is two frames (40.96us).
    // This avoids a long path through two cascaded multipliers at 50MHz.
    reg signed [15:0] voice_frame;
    reg [8:0] gain_frame;
    always @(posedge clk) begin
        if (!resetn) begin voice_frame <= 0; gain_frame <= 0; end
        else if (frame_ce) begin voice_frame <= voice_sample; gain_frame <= gain_input_frame; end
    end
    wire signed [25:0] product = voice_frame * $signed({1'b0,gain_frame});
    wire signed [25:0] scaled = product >>> (8 + VOLUME_SHIFT);
    wire signed [15:0] audio_sample = scaled[15:0];
    i2s_tx u_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
endmodule
