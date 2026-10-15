`timescale 1ns/1ps
// All state uses the 50 MHz clock. BCK/LRCK are output signals, not clocks.
module clk_div (
    input wire clk,
    input wire resetn,
    output reg bck,
    output reg lrck,
    output wire bck_rise_ce,
    output wire bck_fall_ce,
    output wire frame_ce,
    output reg [5:0] bit_index
);
    reg [3:0] divider;

    // Enables describe the output edge that occurs on this clk rising edge.
    // bit_index is the bit to launch on the NEXT BCK falling edge (0..63).
    assign bck_rise_ce = resetn && (divider == 4'd7);
    assign bck_fall_ce = resetn && (divider == 4'd15);
    assign frame_ce = bck_fall_ce && (bit_index == 6'd0);

    always @(posedge clk) begin
        if (!resetn) begin
            divider <= 4'd0;
            bck <= 1'b0;
            lrck <= 1'b1;
            bit_index <= 6'd0;
        end else begin
            divider <= divider + 4'd1;
            if (bck_rise_ce)
                bck <= 1'b1;
            if (bck_fall_ce) begin
                bck <= 1'b0;
                lrck <= bit_index[5];
                bit_index <= bit_index + 6'd1;
            end
        end
    end
endmodule
