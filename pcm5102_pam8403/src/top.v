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
    parameter ENABLE_EVENT_TAKE = 0,
    parameter ENABLE_FLASH_AUDIO = 0,
    // Unified phone controls leave all sixteen pads available for music.
    parameter EVENT_KEYS_ENABLE = 1,
    // Phone communication uses HC-05. The separate 2Mbps USB PCM uplink
    // is opt-in and consumes no FIFO/UART logic in the default build.
    parameter ENABLE_USB_AUDIO_RECORD = 0,
    parameter VOLUME_SHIFT = 4,
    parameter KEY_CONFIRM_CYCLES = 50_000,
    parameter TOUCH_STARTUP_US = 600000,
    parameter TOUCH_DEBOUNCE_MS = 2, // Note keys 1..7: short press/release confirmation.
    parameter TOUCH_MODE_DEBOUNCE_MS = 20, // Key 8 remains a deliberate mode control.
    parameter TOUCH_ACTIVE_LOW = 0,
    parameter TOUCH_SERIAL_HALF_CYCLES = 500,
    parameter TOUCH_SERIAL_GAP_CYCLES = 125000,
    parameter TOUCH_SERIAL_QUIET_CYCLES = 1000,
    parameter ADSR_ATTACK_SAMPLES = 98,
    parameter ADSR_DECAY_SAMPLES = 3906,
    parameter [15:0] ADSR_SUSTAIN_LEVEL = 16'd39321,
    parameter ADSR_RELEASE_SAMPLES = 4883, // ~100ms, matches melody articulation
    parameter TOUCH_ADSR_RELEASE_SAMPLES = 488, // ~10ms tail for live note keys.
    parameter integer PEDAL_TAIL_MS = 1200,
    parameter integer DAMPER_MS = 10,
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
    input wire touch_sdo,
    input wire [7:0] ir_beam,
    input wire hc05_rx,
    output wire hc05_tx,
    input wire audio_rec_cts_n,
    output wire audio_rec_tx,
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din,
    output wire touch_scl,
    inout wire scl, sda,
    output wire hub_R1, hub_G1, hub_B1,
    output wire hub_R2, hub_G2, hub_B2,
    output wire hub_A, hub_B, hub_C, hub_D, hub_E,
    output wire hub_CK, hub_ST, hub_OE,
    output wire flash_cs_n,flash_sck,flash_mosi,flash_wp_n,flash_hold_n,
    input wire flash_miso
);
    reg [5:0] power_count = 6'd0;
    wire resetn = &power_count;
    wire [527:0] perf_live_state,perf_state;
    wire [15:0] perf_live_pulses,perf_pulses;
    wire perf_recording,perf_playing,perf_replay,perf_kill,perf_available,perf_saved,perf_full;
    wire [3:0] perf_error;
    wire [1:0] perf_confirm;
    wire [23:0] perf_elapsed,perf_duration;
    wire [10:0] perf_count;
    wire [2:0] perf_command;
    wire event_local_flash_request;
    wire nv_busy,nv_boot_done,nv_valid,nv_done,nv_ok,nv_save,nv_delete,nv_we,nv_full;
    wire [3:0] nv_error;
    wire [10:0] nv_count;
    wire [23:0] nv_duration;
    wire [9:0] nv_address;
    wire [47:0] nv_data,nv_q;
    wire [7:0] perf_flags={perf_confirm,nv_busy,perf_full,perf_saved,perf_available,perf_playing,perf_recording};
    assign flash_wp_n=1'b1;
    assign flash_hold_n=1'b1;
    always @(posedge clk) begin
        if (!resetn)
            power_count <= power_count + 6'd1;
    end

    wire s1_pressed;
    wire s2_pressed;
    wire s2_level, s2_restart;
    wire [1:0] visual_mode;
    wire visual_write;
    wire [1:0] remote_visual_mode;
    wire [111:0] visual_snapshot;
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
    wire [15:0] touch_keys;
    wire [15:0] touch_keys_raw;
    wire touch_ready;
    wire touch_idle = TOUCH_ACTIVE_LOW ? 1'b1 : 1'b0;
    wire [7:0] note_keys, note_keys_raw, mode_keys, mode_keys_raw;
    wire note_ready, mode_ready;
    wire touch_mode16,panic,serial_active_high;
    wire [1:0] touch_hold;
    wire [4:0] touch_poly,touch_voice_count;
    reg serial_polarity_previous;
    wire serial_polarity_changed=serial_active_high!=serial_polarity_previous;
    always @(posedge clk)begin
        if(!resetn)serial_polarity_previous<=0;else serial_polarity_previous<=serial_active_high;
    end
    wire [1:0] effect_mode;
    wire [3:0] effect_wet;
    wire [4:0] master_volume;
    wire [2:0] analog_mode;
    wire pressure_write,pressure_value;
    wire [9:0] analog_min,analog_max;
    wire [15:0] serial_keys,serial_raw;
    wire serial_ready,serial_valid,serial_error,serial_scl;
    reg [15:0] serial_armed;
    assign touch_scl=touch_mode16 ? (serial_active_high ? ~serial_scl : serial_scl) : 1'b1;
    assign touch_keys = touch_mode16 ? (serial_keys & serial_armed) : {8'd0,mode_keys[7],note_keys[6:0]};
    assign touch_keys_raw = touch_mode16 ? serial_raw : {8'd0,mode_keys_raw[7],note_keys_raw[6:0]};
    assign touch_ready = touch_mode16 ? serial_ready : (note_ready && mode_ready);
    always @(posedge clk) begin
        if(!resetn || !touch_mode16 || !serial_ready || serial_polarity_changed)serial_armed<=0;
        else serial_armed<=serial_armed | ~serial_keys;
    end
    ttp229_keys #(.STARTUP_CYCLES(TOUCH_STARTUP_US*50),
        .HALF_PERIOD_CYCLES(TOUCH_SERIAL_HALF_CYCLES),.GAP_CYCLES(TOUCH_SERIAL_GAP_CYCLES),
        .QUIET_CYCLES(TOUCH_SERIAL_QUIET_CYCLES)) u_touch_serial (
        .clk(clk),.rst_n(resetn && touch_mode16 && !serial_polarity_changed),.sdo(serial_active_high ? ~touch_sdo : touch_sdo),.scl(serial_scl),
        .keys_down(serial_keys),.raw_keys(serial_raw),.scan_valid(serial_valid),
        .scan_error(serial_error),.ready(serial_ready),.note_valid(),.note_index(),.note_ready(1'b1));
    // Downloaded notes drive the same independent DDS/ADSR lanes as the pads
    // only after an explicit AUDITION. No audio samples are stored in a score.
    wire [6:0] audition_keys;
    wire [15:0] physical_notes=touch_ready ? ((touch_mode16 ? touch_keys : {9'd0,touch_keys[6:0]}) &
        (ENABLE_EVENT_TAKE && EVENT_KEYS_ENABLE ? 16'h0fff : 16'hffff)) : 16'd0;
    reg [15:0] held_notes,blocked_notes;
    reg previous_touch_mode;
    wire [15:0] live_note_gates=(physical_notes & ~blocked_notes) |
        (touch_hold==1 ? held_notes : 16'd0) | {9'd0,audition_keys};
    wire [15:0] touch_note_gates=perf_playing ? perf_state[512 +: 16] : live_note_gates;
    always @(posedge clk)begin
        if(!resetn)begin held_notes<=0;blocked_notes<=0;previous_touch_mode<=0;end
        else begin
            previous_touch_mode<=touch_mode16;
            if(panic || (perf_kill && !perf_recording) || previous_touch_mode!=touch_mode16)begin held_notes<=0;blocked_notes<=physical_notes;end
            else if(frame_ce)begin
                blocked_notes<=blocked_notes & physical_notes;
                held_notes<=touch_hold==1 ? held_notes | (physical_notes & ~blocked_notes) : 16'd0;
            end
        end
    end
    wire fsr_pitch_mode;
    wire [15:0] fsr_target_pitch_ratio, fsr_pitch_ratio;
    wire [255:0] touch_phase_increments;
    wire signed [15:0] touch_sample;
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
    wire [15:0] touch_active;
    wire [8:0] extended_active=touch_active[15:7];
    wire signed [15:0] dry_audio_sample,effect_sample;
    wire effect_valid;
    wire [15:0] effective_pitch_ratio;
    wire [12:0] master_target;
    wire [3:0] effective_wet;
    wire [9:0] analog_position;
    wire analog_available;
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
    wire audio_rec_prepare,audio_rec_start,audio_rec_stop,audio_rec_abort,audio_rec_send,audio_rec_ack;
    wire audio_rec_busy,audio_rec_ready,audio_rec_overflow,audio_rec_valid;
    wire [3:0] audio_rec_status,audio_rec_error;
    wire [20:0] audio_rec_stored_samples;
    wire [15:0] audio_rec_generation;
    wire [15:0] audio_rec_session;
    wire [15:0] audio_rec_ack_sequence;
    wire [7:0] audio_stream_data;
    wire audio_stream_valid,audio_stream_last,audio_stream_ready,audio_stream_busy;
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
        .ENABLE_LOOKAHEAD(!ENABLE_DEMO_SCORE),.LOOKAHEAD_MS(GUIDE_LEAD_MS),
        .ENABLE_DOWNLOADED_INCREMENT(ENABLE_DEMO_SCORE),.ENABLE_EVENT_TAKE(ENABLE_EVENT_TAKE),
        .ENABLE_FLASH_AUDIO(ENABLE_FLASH_AUDIO),.DEFAULT_TOUCH_MODE16(ENABLE_EVENT_TAKE && EVENT_KEYS_ENABLE)) u_keymap (
        .clk(clk),.resetn(resetn),.rx(hc05_rx),.tx(hc05_tx),
        .keys_ready(touch_ready),
        .song_busy(song_playing || (|song_active) || s1_pressed || s2_action),
        .notes_busy((|(touch_mode16 ? touch_keys_raw : {9'd0,touch_keys_raw[6:0]})) || (|physical_notes) || (|touch_active[6:0]) || (|extended_active)),
        .recording(perf_playing),.note_map(touch_note_map),
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
        .xy_write(xy_write),.xy_ratio(xy_ratio),.xy_phase(xy_phase),
        .visual_write(visual_write),.remote_mode(remote_visual_mode),
        .visual_requested(visual_mode),.reference_ratio(reference_ratio),.reference_phase(reference_phase),
        .visual_snapshot(visual_snapshot),
        .touch_mode16(touch_mode16),.touch_hold(touch_hold),.panic(panic),.serial_active_high(serial_active_high),
        .poly_limit(touch_poly),.touch_voice_count(touch_voice_count),
        .pedal_clear(perf_kill || previous_touch_mode!=touch_mode16),.take_recording(perf_recording),
        .effect_mode(effect_mode),.effect_wet(effect_wet),.master_volume(master_volume),
        .analog_mode(analog_mode),.pressure_write(pressure_write),.pressure_value(pressure_value),
        .analog_min(analog_min),.analog_max(analog_max),.adc_sample(fsr_adc_sample),.adc_timeout(fsr_adc_timeout),
        .audio_rec_busy(audio_rec_busy),.audio_rec_ready(audio_rec_ready),.audio_rec_overflow(audio_rec_overflow),.audio_rec_valid(audio_rec_valid),
        .audio_rec_status(audio_rec_status),.audio_rec_error(audio_rec_error),
        .audio_rec_stored_samples(audio_rec_stored_samples),.audio_rec_generation(audio_rec_generation),
        .audio_stream_data(audio_stream_data),.audio_stream_valid(audio_stream_valid),.audio_stream_last(audio_stream_last),
        .audio_stream_busy(audio_stream_busy),.audio_stream_ready(audio_stream_ready),
        .audio_rec_prepare(audio_rec_prepare),.audio_rec_start(audio_rec_start),.audio_rec_stop(audio_rec_stop),.audio_rec_abort(audio_rec_abort),
        .audio_rec_send(audio_rec_send),.audio_rec_ack(audio_rec_ack),.audio_rec_ack_sequence(audio_rec_ack_sequence),
        .audio_rec_session(audio_rec_session),.take_command(perf_command),.take_flags({perf_flags[7:6],nv_busy || event_local_flash_request,perf_flags[4:0]}),
        .take_error(perf_error),.take_elapsed(perf_elapsed),.take_duration(perf_duration),.take_count(perf_count)
    );
    // Sensor, score/panel and all voices share one 50MHz clock and frame CE.
    // S1/S2 retain their score controls; Bluetooth controls the new voices.
    ir_strings #(.FILTER_CYCLES(IR_FILTER_CYCLES)) u_ir (
        .clk(clk),.rst_n(resetn),.beam_in(ir_beam),
        .blocked(ir_blocked),.armed(ir_armed),
        .note_valid(ir_note_valid),.note_index(ir_note_index)
    );
    reg [15:0] replay_pending;
    always @(posedge clk)begin
        if(!resetn || perf_kill)replay_pending<=0;
        else replay_pending<=(replay_pending & (replay_pending-16'd1)) | perf_pulses;
    end
    wire replay_ir_valid=|replay_pending[7:0];
    wire [2:0] replay_ir_index=replay_pending[0] ? 0 : replay_pending[1] ? 1 :
        replay_pending[2] ? 2 : replay_pending[3] ? 3 : replay_pending[4] ? 4 :
        replay_pending[5] ? 5 : replay_pending[6] ? 6 : 7;
    wire replay_gesture_valid=!(|replay_pending[7:0]) && (|replay_pending[11:8]);
    wire [2:0] replay_start=replay_pending[8] ? 1 : replay_pending[9] ? 3 : replay_pending[10] ? 2 : 4;
    wire [2:0] replay_end=replay_pending[8] ? 2 : replay_pending[9] ? 4 : replay_pending[10] ? 1 : 3;
    wire [3:0] live_gesture=(gesture_ready && gesture_valid && dir_evaluated) ?
        ({start_dir,end_dir}=={3'd1,3'd2} ? 4'b0001 :
         {start_dir,end_dir}=={3'd3,3'd4} ? 4'b0010 :
         {start_dir,end_dir}=={3'd2,3'd1} ? 4'b0100 :
         {start_dir,end_dir}=={3'd4,3'd3} ? 4'b1000 : 4'd0) : 4'd0;
    assign perf_live_pulses={panic,1'b0,sensor_test32,guitar_pluck,live_gesture,
        ir_note_valid ? (8'b1<<ir_note_index) : 8'd0};
    assign perf_live_state={live_note_gates,{11'd0,gesture_bank,gesture_vibrato,gesture_timbre},
        {10'd0,effect_mode,effective_wet},{3'd0,master_target},effective_pitch_ratio,fsr_gain,
        {14'd0,sensor_adsr},touch_adsr,touch_phase_increments[223:0]};
    gesture_top #(.AUDIO_VOLUME_SHIFT(SENSOR_VOLUME_SHIFT),.EXTERNAL_CONTROL(1),.ENABLE_REPLAY(ENABLE_EVENT_TAKE)) u_gesture (
        .clk(clk),.resetn(resetn && !(panic && !ENABLE_EVENT_TAKE)),.frame_ce(frame_ce),
        .key_s1(1'b0),.key_s2(1'b0),.scl(scl),.sda(sda),
        .control_timbre(perf_replay ? perf_state[496 +: 3] : gesture_timbre),
        .control_vibrato(perf_replay ? perf_state[499] : gesture_vibrato),
        .control_bank(perf_replay ? perf_state[500] : gesture_bank),.audio_sample(gesture_sample),
        .ir_note_valid(perf_playing ? replay_ir_valid : ir_note_valid),
        .ir_note_index(perf_playing ? replay_ir_index : ir_note_index),
        .test32(perf_playing ? (replay_pending[13] && !(|replay_pending[12:0])) : sensor_test32),
        .adsr_config(perf_replay ? perf_state[288 +: 130] : sensor_adsr),
        .replay_mode(perf_playing),.replay_gesture_valid(replay_gesture_valid),.audio_clear(perf_kill || panic),
        .replay_start(replay_start),.replay_end(replay_end),
        .voice_active(sensor_voice_active),.voice_count(sensor_voice_count),.overrun(sensor_overrun),
        .init_done(gesture_ready),.gesture_valid(gesture_valid),
        .dir_evaluated(dir_evaluated),.start_dir(start_dir),.end_dir(end_dir)
    );
    geita #(.STRING_LENGTH(GUITAR_STRING_LENGTH),.EXTERNAL_TRIGGER(1)) u_string (
        .clk(clk),.resetn(resetn && !panic && !perf_kill),.sample_ce(frame_ce),.key_s1(1'b0),
        .pluck(perf_playing ? (replay_pending[12] && !(|replay_pending[11:0])) : guitar_pluck),.sample(guitar_sample)
    );
    assign guitar_scaled_sample = guitar_sample >>> VOLUME_SHIFT;
    audio_mixer u_extra_mix (
        .clk(clk),.resetn(resetn && !perf_kill),.sample_ce(frame_ce),
        .sample0(gesture_sample),.sample1(guitar_scaled_sample),
        .sample2(16'sd0),.sample3(16'sd0),.sample_out(extra_sample),.clipped()
    );
    // Score timing and panel scan use clock enables on the same 50MHz clock.
    // Dropping playing on guide_reset clears pending pixels without resetting scan.
    hub75e_rhythm_display #(.LEAD_MS(GUIDE_LEAD_MS),.ENABLE_AUDIO_VISUAL(1),.ENABLE_STATUS(1),.ENABLE_TAKE_STATUS(ENABLE_EVENT_TAKE)) u_guide_display (
        .clk(clk),.resetn(resetn),.touch_keys(touch_keys[6:0]),
        .touch_mode16(touch_mode16),.all_touch_keys(touch_note_gates),
        .physical_keys(touch_keys),.ir_keys(ir_blocked),.touch_hold(touch_hold),
        .pressure_pitch(fsr_pitch_mode),.recording(recording_busy || perf_recording),.keys_ready(touch_ready),
        .timbre(gesture_timbre),.analog_mode(analog_mode),.effect_mode(effect_mode),
        .effect_wet(effective_wet),.volume(master_volume),.master_gain(master_target),
        .adc_sample(fsr_adc_sample),.analog_position(analog_position),.analog_valid(analog_available),
        .take_flags({perf_flags[7:6],nv_busy || event_local_flash_request,perf_flags[4:0]}),.take_error(perf_error),.take_elapsed(perf_elapsed),.take_count(perf_count),
        .guide_keys(song_guide_keys),.playing(downloaded_playing && !guide_reset),
        .ms_tick(guide_ms_tick),.note_spawn(guide_note_spawn),
        .spawn_keys(guide_spawn_keys),.spawn_delay_ms(guide_spawn_delay),
        .visual_mode(visual_mode),.reference_ratio(reference_ratio),.reference_phase(reference_phase),
        .visual_snapshot(visual_snapshot),
        .sample_ce(frame_ce),.mixed_sample(audio_sample),
        .touch0(touch_mix0),.touch1(touch_mix1),
        .sensor_sample(gesture_sample),.guitar_sample(guitar_scaled_sample),
        .note_ready(guide_note_ready),.overflow(),
        .hub_R1(hub_R1),.hub_G1(hub_G1),.hub_B1(hub_B1),
        .hub_R2(hub_R2),.hub_G2(hub_G2),.hub_B2(hub_B2),
        .hub_A(hub_A),.hub_B(hub_B),.hub_C(hub_C),.hub_D(hub_D),.hub_E(hub_E),
        .hub_CK(hub_CK),.hub_ST(hub_ST),.hub_OE(hub_OE)
    );
    midi_note_lut #(.BLOCK_ROM(2)) u_note_lut (
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
        .expression_enable(FSR_ENABLE && analog_mode==0 && !fsr_pitch_mode),
        .adc_valid(fsr_adc_valid), .adc_sample(fsr_adc_sample),
        .pressure_code(fsr_pressure_code), .target_gain(fsr_target_gain), .gain(fsr_gain)
    );
    fsr_dynamics #(
        .ADC_INVERT(FSR_ADC_INVERT), .GAIN_REVERSE(1),
        .ADC_ZERO(FSR_ADC_ZERO), .ADC_FULL(FSR_ADC_FULL),
        .MIN_GAIN(FSR_PITCH_MIN_RATIO), .SLEW_STEP(FSR_PITCH_SLEW_STEP)
    ) u_fsr_pitch_dynamics (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .expression_enable(FSR_ENABLE && analog_mode==0 && fsr_pitch_mode),
        .adc_valid(fsr_adc_valid), .adc_sample(fsr_adc_sample),
        .pressure_code(), .target_gain(fsr_target_pitch_ratio), .gain(fsr_pitch_ratio)
    );

    // Reuse the shared reader with separate confirmation times for notes/mode.
    // Mask unused inputs at their physical idle polarity in each reader.
    ttp229_gpio_input #(
        .CLK_FREQ(50_000_000), .STARTUP_US(TOUCH_STARTUP_US),
        .DEBOUNCE_MS(TOUCH_DEBOUNCE_MS), .ACTIVE_LOW(TOUCH_ACTIVE_LOW)
    ) u_touch_input (
        .clk(clk), .resetn(resetn), .enable(!touch_mode16), .touch_out({touch_idle,touch_out[6:0]}),
        .keys_raw(note_keys_raw), .keys_stable(note_keys), .sample_valid(), .ready(note_ready)
    );
    ttp229_gpio_input #(
        .CLK_FREQ(50_000_000), .STARTUP_US(TOUCH_STARTUP_US),
        .DEBOUNCE_MS(TOUCH_MODE_DEBOUNCE_MS), .ACTIVE_LOW(TOUCH_ACTIVE_LOW)
    ) u_touch_mode_input (
        .clk(clk), .resetn(resetn), .enable(!touch_mode16), .touch_out({touch_out[7],{7{touch_idle}}}),
        .keys_raw(mode_keys_raw), .keys_stable(mode_keys), .sample_valid(), .ready(mode_ready)
    );
    fsr_mode_select u_fsr_mode (
        .clk(clk), .resetn(resetn), .keys_ready(touch_ready),
        .key8_raw(!touch_mode16 && touch_keys_raw[7]), .key8_stable(!touch_mode16 && touch_keys[7]),
        .remote_write(pressure_write),.remote_value(pressure_value),
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
        .visual_write(visual_write),.remote_mode(remote_visual_mode),
        .xy_write(xy_write),.xy_ratio(xy_ratio),.xy_phase(xy_phase),
        .reference_ratio(reference_ratio),.reference_phase(reference_phase)
    );
    // Elaborate the optional demo chain only when enabled. Production
    // AUDITION still drives the live touch synthesizer through audition_keys.
    generate
    if(ENABLE_DEMO_SCORE) begin: demo_score
    twinkle_sequencer #(
        .BEAT_SAMPLES(SONG_BEAT_SAMPLES), .GAP_SAMPLES(SONG_GAP_SAMPLES),
        .INTRO_SAMPLES(SONG_INTRO_SAMPLES), .TAIL_SAMPLES(SONG_TAIL_SAMPLES)
    ) u_control (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .toggle_play((s1_pressed && !downloaded_valid) || (builtin_stop && builtin_playing)),
        .restart((s2_action && !downloaded_valid) || builtin_play),
        .playing(builtin_playing), .note_index(), .gates(builtin_gates), .phase_increments(builtin_increments)
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
    end else begin: live_score
        assign builtin_playing=1'b0;
        assign builtin_gates=4'd0;
        assign builtin_increments=128'd0;
        assign song_sample=16'sd0;
        assign song_active=4'd0;
    end
    endgenerate
    clk_div u_clk_div (
        .clk(clk), .resetn(resetn), .bck(i2s_bck), .lrck(i2s_lrck),
        .bck_rise_ce(bck_rise_ce), .bck_fall_ce(bck_fall_ce),
        .frame_ce(frame_ce), .bit_index(bit_index)
    );
    // OUT1..7 default to C4 D4 E4 F4 G4 A4 B4; HC-05 can remap them.
    // Fs=48828.125Hz. Pressure pitch changes preserve each DDS phase.
    fsr_pitch_scaler #(.PER_VOICE_BEND(1)) u_fsr_pitch_scaler (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce), .pitch_ratio(effective_pitch_ratio),
        .note_increments(touch_base_increments),
        .bend_write(bend_write),.bend_reset(bend_reset),.bend_index(bend_index),.bend_ratio(bend_ratio),
        .phase_increments(touch_phase_increments)
    );
    touch_tdm_synth #(.VOLUME_SHIFT(VOLUME_SHIFT),.EXTENDED_CONTROL(1),
        .PEDAL_TAIL_MS(PEDAL_TAIL_MS),.DAMPER_MS(DAMPER_MS)) u_touch_synth (
        .clk(clk),.resetn(resetn && !panic && !perf_kill && previous_touch_mode==touch_mode16),.sample_ce(frame_ce),
        .gates(touch_note_gates),.low_steps(perf_replay ? perf_state[223:0] : touch_phase_increments[223:0]),
        .physical_gates(perf_playing ? touch_note_gates : physical_notes),
        .pedal_mode(perf_playing ? 2'd0 : touch_hold),.poly_limit(perf_playing ? 5'd16 : touch_poly),
        .voice_count(touch_voice_count),
        .adsr_config(perf_replay ? perf_state[224 +: 64] : touch_adsr),
        .pitch_ratio(perf_replay ? perf_state[448 +: 16] : effective_pitch_ratio),
        .sample(touch_sample),.active(touch_active),.clipped(),.overrun());
    generate
        if (FSR_ENABLE) begin: pressure_enabled
            envelope_gain #(.VOLUME_SHIFT(0)) u_expression (
                .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
                .sample_in(touch_sample), .gain(perf_replay ? perf_state[432 +: 16] : fsr_gain), .sample_out(touch_mix0)
            );
            assign touch_mix1 = 16'sd0;
        end else begin: pressure_bypass
            // Exact original audio path for setups without an ADC.
            assign touch_mix0 = touch_sample;
            assign touch_mix1 = 16'sd0;
        end
    endgenerate
    // Default gain leaves room for seven keys, gestures and a guitar string.
    // Saturation still protects configurations with a higher compile-time gain.
    audio_mixer u_output_mix (
        .clk(clk), .resetn(resetn && !perf_kill), .sample_ce(frame_ce),
        .sample0(song_sample), .sample1(touch_mix0),
        .sample2(touch_mix1), .sample3(extra_sample),
        .sample_out(dry_audio_sample), .clipped()
    );
    analog_expression u_analog_expression (
        .clk(clk),.resetn(resetn),.frame_ce(frame_ce),.mode(analog_mode),
        .adc_sample(fsr_adc_sample),.adc_min(analog_min),.adc_max(analog_max),.adc_valid(fsr_adc_valid),.adc_timeout(fsr_adc_timeout),
        .fsr_ratio(fsr_pitch_ratio),.volume(master_volume),.wet(effect_wet),
        .pitch_ratio(effective_pitch_ratio),.master_gain(master_target),.effect_wet(effective_wet),
        .position(analog_position),.available(analog_available));
    // Dry bypass retains the original frame timing. Wet modes add the
    // reference effect pipeline, and the panel observes the final PCM.
    audio_effects #(.ADDRESS_BITS(12)) u_effects (
        .clk(clk),.resetn(resetn && !panic && !perf_kill),.sample_valid(frame_ce),.dry(dry_audio_sample),
        .mode(perf_replay ? perf_state[484 +: 2] : effect_mode),
        .wet(perf_replay ? perf_state[480 +: 4] : effective_wet),.sample(effect_sample),.valid(effect_valid));
    audio_master_volume u_master_volume (
        .clk(clk),.resetn(resetn && !perf_kill),.frame_ce(frame_ce),
        .sample_in((perf_replay ? perf_state[484 +: 2] : effect_mode)==0 ? dry_audio_sample : effect_sample),
        .target_gain(perf_replay ? perf_state[464 +: 13] : master_target),.sample_out(audio_sample),.applied_gain());
    i2s_tx u_i2s_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
    wire pcm_cs_n,pcm_sck,pcm_mosi,event_cs_n,event_sck,event_mosi;
    wire [60:0] pcm_spi_request,event_spi_request;
    wire [52:0] pcm_nor_request,event_nor_request;
    wire [11:0] shared_spi_response;
    wire pcm_resetn,nv_store_busy;
    generate if(ENABLE_FLASH_AUDIO && ENABLE_EVENT_TAKE)begin: shared_flash
        // Event boot owns SPI first. Both stores keep their independent
        // partition checks; runtime flash operations are serialized below.
        reg event_boot_ready;
        always @(posedge clk)
            if(!resetn)event_boot_ready<=0;
            else if(nv_boot_done)event_boot_ready<=1;
        assign pcm_resetn=resetn && event_boot_ready;
        wire [52:0] request=nv_store_busy ? event_nor_request : pcm_nor_request;
        audio_nor_operation #(.DATA_BASE(24'h100000),.DATA_END(24'h800000),.PARTITIONED(1)) u_nor(
            .clk(clk),.resetn(request[52] && (!event_boot_ready || (event_nor_request[52] && pcm_nor_request[52]))),
            .start(request[51]),.kind(request[50:48]),.address(request[47:24]),.length(request[23:9]),
            .write_data(request[8:1]),.write_valid(request[0]),.write_ready(shared_spi_response[8]),
            .read_data(shared_spi_response[7:0]),.read_valid(shared_spi_response[9]),.done(shared_spi_response[10]),
            .error(shared_spi_response[11]),.busy(),.cs_n(flash_cs_n),.sck(flash_sck),.mosi(flash_mosi),
            .miso(flash_miso),.event_partition(nv_store_busy),.spi_request(),.spi_response(12'd0));
    end else begin: separate_flash
        assign pcm_resetn=resetn;
        assign flash_cs_n=ENABLE_FLASH_AUDIO ? pcm_cs_n : ENABLE_EVENT_TAKE ? event_cs_n : 1'b1;
        assign flash_sck=ENABLE_FLASH_AUDIO ? pcm_sck : ENABLE_EVENT_TAKE ? event_sck : 1'b0;
        assign flash_mosi=ENABLE_FLASH_AUDIO ? pcm_mosi : ENABLE_EVENT_TAKE ? event_mosi : 1'b0;
    end endgenerate
    generate if(ENABLE_FLASH_AUDIO)begin: flash_pcm
    wire [3:0] flash_audio_status,flash_audio_error;
    wire flash_audio_prepared,flash_audio_capturing;
    wire [20:0] flash_audio_samples,flash_audio_stored_samples;
    wire [15:0] flash_audio_generation;
    audio_take_store #(.EXTERNAL_NOR(ENABLE_EVENT_TAKE)) u_audio_take(
        .clk(clk),.resetn(pcm_resetn),.sample_ce(frame_ce),.sample(audio_sample),
        .prepare(audio_rec_prepare && !nv_busy),.start(audio_rec_start && !nv_busy),.stop(audio_rec_stop),.abort(audio_rec_abort),.send(audio_rec_send && !nv_busy),
        .session(audio_rec_session),.ack_valid(audio_rec_ack),.ack_sequence(audio_rec_ack_sequence),
        .stream_data(audio_stream_data),.stream_valid(audio_stream_valid),.stream_last(audio_stream_last),.stream_ready(audio_stream_ready),
        .status(flash_audio_status),.error(flash_audio_error),.valid(audio_rec_valid),.prepared(flash_audio_prepared),
        .capturing(flash_audio_capturing),.overflow(audio_rec_overflow),.sample_count(flash_audio_samples),
        .stored_samples(flash_audio_stored_samples),.stored_generation(flash_audio_generation),.busy(audio_rec_busy),
        .cs_n(pcm_cs_n),.sck(pcm_sck),.mosi(pcm_mosi),.miso(flash_miso),.spi_request(pcm_spi_request),
        .spi_response(12'd0),.nor_request(pcm_nor_request),.nor_response(nv_store_busy ? 12'd0 : shared_spi_response));
    assign audio_rec_ready=flash_audio_prepared;
    assign audio_rec_status=flash_audio_status;assign audio_rec_error=flash_audio_error;
    assign audio_rec_stored_samples=flash_audio_stored_samples;assign audio_rec_generation=flash_audio_generation;
    assign audio_stream_busy=flash_audio_status==8;
    assign audio_rec_tx=1'b1;
    end else if(ENABLE_USB_AUDIO_RECORD && !ENABLE_EVENT_TAKE)begin: legacy_pcm
    audio_record_stream u_audio_record (
        .clk(clk),.resetn(resetn),.sample_ce(frame_ce),.sample(audio_sample),
        .start(audio_rec_start),.stop(audio_rec_stop),.abort(audio_rec_abort),.session(audio_rec_session),
        .cts_n(audio_rec_cts_n),.tx(audio_rec_tx),.busy(audio_rec_busy),.ready(audio_rec_ready),
        .capturing(),.overflow(audio_rec_overflow));
        assign audio_rec_valid=1'b0;assign audio_stream_data=0;assign audio_stream_valid=0;assign audio_stream_last=0;assign audio_stream_busy=0;
        assign audio_rec_status=0;assign audio_rec_error=0;assign audio_rec_stored_samples=0;assign audio_rec_generation=0;
    end else begin: event_take_audio
        assign audio_rec_tx=1'b1;assign audio_rec_busy=1'b0;
        assign audio_rec_ready=1'b0;assign audio_rec_overflow=1'b0;assign audio_rec_valid=1'b0;
        assign audio_stream_data=0;assign audio_stream_valid=0;assign audio_stream_last=0;assign audio_stream_busy=0;
        assign audio_rec_status=0;assign audio_rec_error=0;assign audio_rec_stored_samples=0;assign audio_rec_generation=0;
    end endgenerate
    generate if(ENABLE_EVENT_TAKE)begin: take_enabled
        wire [2:0] local_command;
        take_key_control u_keys(.clk(clk),.resetn(resetn),.ready(touch_ready && EVENT_KEYS_ENABLE),.mode16(touch_mode16),
            .keys(touch_keys[15:12]),.confirm(perf_confirm),.command(local_command));
        assign event_local_flash_request=local_command==7 || (local_command==5 && perf_confirm==2);
        wire [2:0] requested_command=local_command!=0 ? local_command : perf_command;
        wire [2:0] allowed_command=((ENABLE_FLASH_AUDIO && audio_rec_busy && requested_command!=2) ||
            ((requested_command==1 || (requested_command==5 && perf_confirm==1)) &&
             (touch_hold==2 || touch_poly!=16))) ? 3'd0 : requested_command;
        // A physical save can race a UART audio request. Queue that pulse
        // until the PCM store releases SPI, rather than dropping the save.
        reg pending_save,pending_delete;
        wire event_launch=!ENABLE_FLASH_AUDIO || (!audio_rec_busy && !audio_rec_prepare && !audio_rec_start && !audio_rec_send);
        wire store_save=event_launch && (nv_save || pending_save);
        wire store_delete=event_launch && (nv_delete || pending_delete);
        always @(posedge clk)begin
            if(!resetn)begin pending_save<=0;pending_delete<=0;end
            else begin
                pending_save<=store_save ? 1'b0 : pending_save || nv_save;
                pending_delete<=store_delete ? 1'b0 : pending_delete || nv_delete;
            end
        end
        assign nv_busy=nv_store_busy || pending_save || pending_delete || nv_save || nv_delete;
        performance_take u_take(
            .clk(clk),.resetn(resetn),.frame_ce(frame_ce),.command(panic ? 3'd2 : allowed_command),
            .live_state(perf_live_state),.live_pulses(perf_live_pulses),
            .play_state(perf_state),.play_valid(perf_replay),.play_pulses(perf_pulses),.recording(perf_recording),.playing(perf_playing),
            .kill(perf_kill),.available(perf_available),.saved(perf_saved),.full(perf_full),.error(perf_error),
            .confirm(perf_confirm),.elapsed_ms(perf_elapsed),.duration_ms(perf_duration),.count(perf_count),
            .nv_busy(nv_busy),.nv_boot_done(nv_boot_done),.nv_valid(nv_valid),.nv_done(nv_done),.nv_ok(nv_ok),
            .nv_error(nv_error),.nv_count(nv_count),.nv_duration(nv_duration),.nv_full(nv_full),.nv_save(nv_save),.nv_delete(nv_delete),
            .nv_we(nv_we),.nv_address(nv_address),.nv_data(nv_data),.nv_q(nv_q));
        take_nor_store #(.EXTERNAL_NOR(ENABLE_FLASH_AUDIO)) u_store(
            .clk(clk),.resetn(resetn),.save(store_save),.delete_take(store_delete),.count(perf_count),.duration(perf_duration),.take_full(perf_full),
            .busy(nv_store_busy),.boot_done(nv_boot_done),.valid(nv_valid),.done(nv_done),.ok(nv_ok),.error(nv_error),
            .loaded_count(nv_count),.loaded_duration(nv_duration),.loaded_full(nv_full),.ram_we(nv_we),.ram_address(nv_address),
            .ram_data(nv_data),.ram_q(nv_q),.cs_n(event_cs_n),.sck(event_sck),.mosi(event_mosi),.miso(flash_miso),
            .spi_request(event_spi_request),.spi_response(12'd0),.nor_request(event_nor_request),.nor_response(nv_store_busy ? shared_spi_response : 12'd0));
    end else begin: no_take
        assign perf_state=0;assign perf_pulses=0;assign perf_recording=0;assign perf_playing=0;assign perf_kill=0;
        assign perf_available=0;assign perf_replay=0;assign perf_saved=0;assign perf_full=0;assign perf_error=0;assign perf_confirm=0;
        assign perf_elapsed=0;assign perf_duration=0;assign perf_count=0;assign nv_busy=0;assign nv_store_busy=0;assign event_local_flash_request=0;
    end endgenerate
endmodule
