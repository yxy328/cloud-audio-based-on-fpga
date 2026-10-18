`timescale 1ns/1ps
// Key 8 is a control key, with synchronized raw and debounced levels.
// A key held across calibration must be released before it can toggle.
module fsr_mode_select (
    input wire clk,
    input wire resetn,
    input wire keys_ready,
    input wire key8_raw,
    input wire key8_stable,
    input wire remote_write,remote_value,
    output reg pitch_mode
);
    reg key8_armed;
    always @(posedge clk) begin
        if (!resetn) begin
            pitch_mode <= 1'b0; // Power-up default: pressure controls volume.
            key8_armed <= 1'b0;
        end else if (remote_write===1'b1) begin
            pitch_mode<=remote_value;key8_armed<=0;
        end else if (!keys_ready) begin
            key8_armed <= 1'b0;
        end else if (!key8_raw && !key8_stable) begin
            key8_armed <= 1'b1;
        end else if (key8_stable && key8_armed) begin
            pitch_mode <= ~pitch_mode;
            key8_armed <= 1'b0;
        end
    end
endmodule
