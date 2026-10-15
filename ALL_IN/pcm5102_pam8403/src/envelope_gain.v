`timescale 1ns/1ps
// Positive unsigned Q0.16 gain must be zero-extended before signed multiply.
// A registered product adds one audio frame of pipeline delay and keeps the
// ROM/multiplier/serializer path short. Gain=0 produces exact digital zero.
module envelope_gain #(
    parameter VOLUME_SHIFT = 4
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire signed [15:0] sample_in,
    input wire [15:0] gain,
    output wire signed [15:0] sample_out
);
    wire signed [16:0] positive_gain = {1'b0,gain};
    reg signed [32:0] product;
    always @(posedge clk) begin
        if (!resetn)
            product <= 33'sd0;
        else if (sample_ce)
            product <= sample_in * positive_gain;
    end
    wire signed [32:0] scaled_product = product >>> (16 + VOLUME_SHIFT);
    assign sample_out = scaled_product[15:0];
endmodule
