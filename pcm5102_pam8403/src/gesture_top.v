`timescale 1ns/1ps
// New gesture subsystem, integrated with the main top's reset and audio clock.
// SCL=H4/J3 pin 23, SDA=G4/J3 pin 24. OLED/UART are outside this variant.
// The original standalone source is retained in integration_backup.
module gesture_top #(
    parameter [16:0] AUDIO_NOTE_FRAMES = 17'd14648,
    parameter [16:0] AUDIO_PIANO_FRAMES = 17'd58594,
    parameter [16:0] AUDIO_FLUTE_FRAMES = 17'd24414,
    parameter [16:0] AUDIO_UKULELE_FRAMES = 17'd34180,
    parameter [16:0] AUDIO_DRUM_FRAMES = 17'd19531,
    parameter AUDIO_VOLUME_SHIFT = 4,
    parameter [19:0] AUDIO_KEY_DEBOUNCE_CYCLES = 20'd1000000,
    parameter [25:0] AUDIO_LONG_PRESS_CYCLES = 26'd40000000,
    parameter EXTERNAL_CONTROL = 0,
    parameter ENABLE_REPLAY = 0,
    parameter SHARED_ARITH = 0
) (
    input wire clk, resetn, frame_ce,
    input wire key_s1, key_s2,
    inout wire sda, scl,
    output wire signed [15:0] audio_sample,
    output wire init_done, gesture_valid, dir_evaluated,
    output wire [2:0] start_dir, end_dir,
    input wire [2:0] control_timbre,
    input wire control_vibrato, control_bank,
    input wire [31:0] vibrato_inc,
    input wire [9:0] vibrato_depth,
    input wire [15:0] vibrato_delay,
    input wire vibrato_update,
    input wire [15:0] tuning_ratio,
    input wire ir_note_valid, test32,
    input wire [129:0] adsr_config,
    input wire [2:0] ir_note_index,
    output wire [31:0] voice_active,
    output wire [5:0] voice_count,
    output wire overrun,
    input wire replay_mode,replay_gesture_valid,audio_clear,
    input wire [2:0] replay_start,replay_end,
    output wire shared_mul_request,shared_sine_request,
    output wire signed [32:0] shared_mul_a,
    output wire signed [17:0] shared_mul_b,
    output wire [31:0] shared_sine_phase,
    input wire signed [50:0] shared_product,
    input wire signed [15:0] shared_sine
);
    wire i2c_start, i2c_rw, i2c_busy, i2c_done, i2c_nack, i2c_rvalid;
    wire [6:0] i2c_addr;
    wire [7:0] i2c_reg, i2c_wdata, i2c_rdlen, i2c_rdata;
    wire use_replay=ENABLE_REPLAY && replay_mode;

    // The gesture sensor owns this bus; the slider uses its own SCL/SDA pins.
    i2c_master #(.CLK_FREQ(50_000_000), .I2C_FREQ(100_000)) u_i2c (
        .clk(clk), .rst_n(resetn),
        .cmd_start(i2c_start), .cmd_addr(i2c_addr), .cmd_reg(i2c_reg),
        .cmd_rw(i2c_rw), .cmd_wdata(i2c_wdata), .cmd_wdata1(8'h00), .cmd_wlen(1'b0),
        .cmd_rdlen(i2c_rdlen),
        .busy(i2c_busy), .done(i2c_done), .nack(i2c_nack),
        .rdata(i2c_rdata), .rvalid(i2c_rvalid), .scl(scl), .sda(sda)
    );
    // Controller retains its own 100ms sensor initialization wait.
    apds9960_ctrl u_ctrl (
        .clk(clk), .rst_n(resetn),
        .i2c_start(i2c_start), .i2c_addr(i2c_addr), .i2c_reg(i2c_reg),
        .i2c_rw(i2c_rw), .i2c_wdata(i2c_wdata), .i2c_rdlen(i2c_rdlen),
        .i2c_busy(i2c_busy), .i2c_done(i2c_done), .i2c_nack(i2c_nack),
        .i2c_rdata(i2c_rdata), .i2c_rvalid(i2c_rvalid),
        .gesture_valid(gesture_valid), .dir_evaluated(dir_evaluated),
        .start_dir(start_dir), .end_dir(end_dir), .init_done(init_done),
        .raw_u(), .raw_d(), .raw_l(), .raw_r(), .dbg_peak(),
        .dbg_gstatus(), .dbg_gflvl(), .dbg_id(), .dbg_enable(),
        .dbg_proximity(), .dbg_error(), .dbg_nack_count(), .dbg_nack_reg(),
        .dbg_gconf2(), .dbg_gpulse()
    );
    sensor_poly_audio #(
        .NOTE_FRAMES(AUDIO_NOTE_FRAMES),
        .PIANO_FRAMES(AUDIO_PIANO_FRAMES), .FLUTE_FRAMES(AUDIO_FLUTE_FRAMES),
        .UKULELE_FRAMES(AUDIO_UKULELE_FRAMES), .DRUM_FRAMES(AUDIO_DRUM_FRAMES),
        .VOLUME_SHIFT(AUDIO_VOLUME_SHIFT),.SHARED_ARITH(SHARED_ARITH)
    ) u_audio (
        .clk(clk), .resetn(resetn && !(ENABLE_REPLAY && audio_clear)), .frame_ce(frame_ce),
        .sensor_ready(use_replay ? 1'b1 : init_done), .gesture_valid(use_replay ? replay_gesture_valid : gesture_valid),
        .dir_evaluated(use_replay ? replay_gesture_valid : dir_evaluated),
        .start_dir(use_replay ? replay_start : start_dir), .end_dir(use_replay ? replay_end : end_dir),
        .ir_note_valid(ir_note_valid),.ir_note_index(ir_note_index),.test32(test32),
        .control_timbre(control_timbre), .control_vibrato(control_vibrato),
        .vibrato_inc(vibrato_inc),.vibrato_depth(vibrato_depth),.vibrato_delay(vibrato_delay),.vibrato_update(vibrato_update),.tuning_ratio(tuning_ratio),
        .control_bank(control_bank),.adsr_config(adsr_config),
        .voice_active(voice_active),.voice_count(voice_count),.overrun(overrun),
        .audio_sample(audio_sample),
        .shared_mul_request(shared_mul_request),.shared_sine_request(shared_sine_request),
        .shared_mul_a(shared_mul_a),.shared_mul_b(shared_mul_b),.shared_sine_phase(shared_sine_phase),
        .shared_product(shared_product),.shared_sine(shared_sine)
    );
endmodule
