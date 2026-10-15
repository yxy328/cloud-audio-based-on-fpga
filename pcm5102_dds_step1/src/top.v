`timescale 1ns/1ps
// Step 1: hold S1 to sound; each S2 press selects the next live pitch.
// E2=50MHz, H11=S1, H10=S2; K2/K1/L1=PCM5102 BCK/LRCK/DIN.
module top #(
    parameter VOLUME_SHIFT = 4,
    parameter KEY_CONFIRM_CYCLES = 50_000
) (
    input wire clk,
    input wire key_s1,
    input wire key_s2,
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din
);
    reg [5:0] power_count = 6'd0;
    wire resetn = &power_count;
    always @(posedge clk) begin
        if (!resetn)
            power_count <= power_count + 6'd1;
    end

    wire gate_level;
    wire s2_pressed;
    wire [1:0] note_index;
    wire [31:0] phase_inc;
    wire frame_ce;
    wire bck_rise_ce;
    wire bck_fall_ce;
    wire [5:0] bit_index;
    wire signed [15:0] voice_sample;
    wire signed [15:0] scaled_sample = voice_sample >>> VOLUME_SHIFT;
    wire signed [15:0] audio_sample = gate_level ? scaled_sample : 16'sd0;

    button_filter #(.CONFIRM_CYCLES(KEY_CONFIRM_CYCLES)) u_s1 (
        .clk(clk), .resetn(resetn), .button(key_s1),
        .level(gate_level), .pressed()
    );
    button_filter #(.CONFIRM_CYCLES(KEY_CONFIRM_CYCLES)) u_s2 (
        .clk(clk), .resetn(resetn), .button(key_s2),
        .level(), .pressed(s2_pressed)
    );
    pitch_control u_pitch (
        .clk(clk), .resetn(resetn), .next_pitch(s2_pressed),
        .note_index(note_index), .phase_inc(phase_inc)
    );
    clk_div u_clk_div (
        .clk(clk), .resetn(resetn), .bck(i2s_bck), .lrck(i2s_lrck),
        .bck_rise_ce(bck_rise_ce), .bck_fall_ce(bck_fall_ce),
        .frame_ce(frame_ce), .bit_index(bit_index)
    );
    dds_voice u_voice (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce),
        .phase_inc(phase_inc), .sample(voice_sample)
    );
    i2s_tx u_i2s_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
endmodule
