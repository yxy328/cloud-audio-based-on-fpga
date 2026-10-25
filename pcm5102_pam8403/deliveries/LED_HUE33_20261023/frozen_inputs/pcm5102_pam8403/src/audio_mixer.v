`timescale 1ns/1ps
// Fixed gain, sign-extended addition and saturation. No voice-count averaging.
module audio_mixer #(
    parameter MIX_SHIFT = 0
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire signed [15:0] sample0,
    input wire signed [15:0] sample1,
    input wire signed [15:0] sample2,
    input wire signed [15:0] sample3,
    output reg signed [15:0] sample_out,
    output reg clipped
);
    wire signed [23:0] extended0 = {{8{sample0[15]}},sample0};
    wire signed [23:0] extended1 = {{8{sample1[15]}},sample1};
    wire signed [23:0] extended2 = {{8{sample2[15]}},sample2};
    wire signed [23:0] extended3 = {{8{sample3[15]}},sample3};
    wire signed [23:0] pair01 = extended0 + extended1;
    wire signed [23:0] pair23 = extended2 + extended3;
    wire signed [23:0] mixed = pair01 + pair23;
    wire signed [23:0] scaled = mixed >>> MIX_SHIFT;

    always @(posedge clk) begin
        if (!resetn) begin
            sample_out <= 16'sd0;
            clipped <= 1'b0;
        end else if (sample_ce) begin
            if (scaled > 24'sd32767) begin
                sample_out <= 16'sh7fff;
                clipped <= 1'b1;
            end else if (scaled < -24'sd32768) begin
                sample_out <= 16'sh8000;
                clipped <= 1'b1;
            end else begin
                sample_out <= scaled[15:0];
                clipped <= 1'b0;
            end
        end
    end
endmodule
