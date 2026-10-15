`timescale 1ns/1ps
// Diagnostic only: continuous tone at 1/16 digital gain; H11 is observed by a register.
// PCM5102 BCK=K2, LRCK=K1, DIN=L1. No FPGA MCLK / PLL is required.
// PAM8403 takes the DAC's analog L/R outputs and has no FPGA control port.
module top #(
    parameter VOLUME_SHIFT = 4
) (
    input wire clk,
    input wire key_s1,
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din
);
    // Keep the H11 input connected while the audio enable is forced on.
    // GAO sees this observation one master-clock edge after the raw pin.
    (* syn_preserve = 1, syn_keep = 1 *) reg key_observed = 1'b0;
    always @(posedge clk)
        key_observed <= key_s1;

    // Gowin configuration initializes this register to zero. Release an
    // internal synchronous reset after 63 clocks; no extra reset pin.
    reg [5:0] power_count = 6'd0;
    wire resetn = &power_count;
    always @(posedge clk) begin
        if (!resetn)
            power_count <= power_count + 6'd1;
    end

    wire bck_rise_ce;
    wire bck_fall_ce;
    wire frame_ce;
    wire [5:0] bit_index;
    wire signed [15:0] nco_sample;
    wire signed [15:0] audio_sample;

    clk_div u_clk_div (
        .clk(clk), .resetn(resetn), .bck(i2s_bck), .lrck(i2s_lrck),
        .bck_rise_ce(bck_rise_ce), .bck_fall_ce(bck_fall_ce),
        .frame_ce(frame_ce), .bit_index(bit_index)
    );
    nco_sine u_nco (
        .clk(clk), .resetn(resetn), .sample_ce(frame_ce), .sample(nco_sample)
    );
    volume_key #(.VOLUME_SHIFT(VOLUME_SHIFT)) u_volume (
        .clk(clk), .resetn(resetn), .key_s1(1'b1),
        .nco_sample(nco_sample), .sample(audio_sample)
    );
    i2s_tx u_i2s_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
endmodule

