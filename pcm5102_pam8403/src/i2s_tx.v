`timescale 1ns/1ps
// Philips I2S: low LRCK = left, 32 BCK per slot, 16 payload bits.
// Slot bit 0 is the one-BCK delay, bits 1..16 are MSB..LSB, 17..31 zero.
module i2s_tx (
    input wire clk,
    input wire resetn,
    input wire bck_fall_ce,
    input wire [5:0] bit_index,
    input wire signed [15:0] sample,
    output reg din
);
    reg [15:0] frame_sample;
    reg [15:0] shift_word;

    always @(posedge clk) begin
        if (!resetn) begin
            frame_sample <= 16'd0;
            shift_word <= 16'd0;
            din <= 1'b0;
        end else if (bck_fall_ce) begin
            if (bit_index == 6'd0) begin
                // Latch once per stereo frame so a key change cannot make
                // left and right channels carry different samples.
                frame_sample <= sample;
                shift_word <= sample;
                din <= 1'b0;
            end else if (bit_index == 6'd32) begin
                shift_word <= frame_sample;
                din <= 1'b0;
            end else if ((bit_index[4:0] >= 5'd1) &&
                         (bit_index[4:0] <= 5'd16)) begin
                din <= shift_word[15];
                shift_word <= {shift_word[14:0], 1'b0};
            end else begin
                din <= 1'b0;
            end
        end
    end
endmodule
