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
    parameter [25:0] AUDIO_LONG_PRESS_CYCLES = 26'd40000000
) (
    input wire clk, resetn, frame_ce,
    input wire key_s1, key_s2,
    inout wire sda, scl,
    output wire signed [15:0] audio_sample,
    output wire init_done, gesture_valid, dir_evaluated,
    output wire [2:0] start_dir, end_dir
);
    wire i2c_start, i2c_rw, i2c_busy, i2c_done, i2c_nack, i2c_rvalid;
    wire [6:0] i2c_addr;
    wire [7:0] i2c_reg, i2c_wdata, i2c_rdlen, i2c_rdata;

    // Only the sensor owns this bus in the requested sensor/audio variant.
    i2c_master #(.CLK_FREQ(50_000_000), .I2C_FREQ(100_000)) u_i2c (
        .clk(clk), .rst_n(resetn),
        .cmd_start(i2c_start), .cmd_addr(i2c_addr), .cmd_reg(i2c_reg),
        .cmd_rw(i2c_rw), .cmd_wdata(i2c_wdata), .cmd_rdlen(i2c_rdlen),
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
    gesture_audio #(
        .SHARED_AUDIO_CLOCK(1), .NOTE_FRAMES(AUDIO_NOTE_FRAMES),
        .PIANO_FRAMES(AUDIO_PIANO_FRAMES), .FLUTE_FRAMES(AUDIO_FLUTE_FRAMES),
        .UKULELE_FRAMES(AUDIO_UKULELE_FRAMES), .DRUM_FRAMES(AUDIO_DRUM_FRAMES),
        .VOLUME_SHIFT(AUDIO_VOLUME_SHIFT),
        .KEY_DEBOUNCE_CYCLES(AUDIO_KEY_DEBOUNCE_CYCLES),
        .LONG_PRESS_CYCLES(AUDIO_LONG_PRESS_CYCLES)
    ) u_audio (
        .clk(clk), .resetn(resetn), .shared_frame_ce(frame_ce),
        .sensor_ready(init_done), .gesture_valid(gesture_valid),
        .dir_evaluated(dir_evaluated), .start_dir(start_dir), .end_dir(end_dir),
        .key_s1(key_s1), .key_s2(key_s2),
        .note_bank(), .timbre_selected(), .vibrato_enabled(),
        .i2s_bck(), .i2s_lrck(), .i2s_din(), .audio_sample(audio_sample)
    );
endmodule
