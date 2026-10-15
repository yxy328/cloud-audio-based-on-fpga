`timescale 1ns/1ps
// Dock S1 / H11 is active high; external pin uses PULL_MODE=DOWN.
module volume_key #(
    parameter VOLUME_SHIFT = 1
) (
    input wire clk,
    input wire resetn,
    input wire key_s1,
    input wire signed [15:0] nco_sample,
    output wire signed [15:0] sample
);
    (* syn_preserve = 1 *) reg key_meta;
    (* syn_preserve = 1 *) reg key_sync;
    always @(posedge clk) begin
        if (!resetn) begin
            key_meta <= 1'b0;
            key_sync <= 1'b0;
        end else begin
            key_meta <= key_s1;
            key_sync <= key_meta;
        end
    end

    // Arithmetic shift preserves negative PCM values. No derived clocks.
    assign sample = key_sync ? (nco_sample >>> VOLUME_SHIFT) : 16'sd0;
endmodule
