`timescale 1ns/1ps
// Tang Primer 25K: 50 MHz E2, active-high S1 H11.
// PCM5102 BCK=K2, LRCK=K1, DIN=L1. No FPGA MCLK / PLL is required.
// PAM8403 takes the DAC's analog L/R outputs and has no FPGA control port.
module top #(
    parameter VOLUME_SHIFT = 1,
    parameter STRING_LENGTH = 110,
    parameter KEY_DEBOUNCE_CYCLES = 250000
) (
    input wire clk,
    input wire key_s1,
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din
);
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
    geita #(.STRING_LENGTH(STRING_LENGTH),
            .DEBOUNCE_CYCLES(KEY_DEBOUNCE_CYCLES)) u_string (
        .clk(clk), .resetn(resetn), .key_s1(key_s1),
        .sample_ce(frame_ce), .sample(nco_sample)
    );
    assign audio_sample = nco_sample >>> VOLUME_SHIFT;
    i2s_tx u_i2s_tx (
        .clk(clk), .resetn(resetn), .bck_fall_ce(bck_fall_ce),
        .bit_index(bit_index), .sample(audio_sample), .din(i2s_din)
    );
endmodule
