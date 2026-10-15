`timescale 1ns/1ps
// Relative expression, not a calibrated measurement in newtons or kilograms.
// ADC polarity follows the connected voltage converter, independently of gain.
// Calibrate ZERO/FULL after inversion. A single sensor controls all touch notes.
// GAIN_REVERSE=1: more force lowers the gain/ratio; ADC polarity is independent.
module fsr_dynamics #(
    parameter ADC_INVERT = 1,
    parameter GAIN_REVERSE = 1,
    parameter [9:0] ADC_ZERO = 10'd32,
    parameter [9:0] ADC_FULL = 10'd900,
    parameter [15:0] MIN_GAIN = 16'd16384,
    parameter [15:0] SLEW_STEP = 16'd64
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire expression_enable,
    input wire adc_valid,
    input wire [9:0] adc_sample,
    output reg [9:0] pressure_code,
    output reg [15:0] target_gain,
    output reg [15:0] gain
);
    // Constant reciprocal replaces a run-time divider; intermediate mapping
    // differs by at most one gain LSB. Both calibrated endpoints are exact.
    localparam integer ADC_SPAN = (ADC_FULL > ADC_ZERO) ? ADC_FULL-ADC_ZERO : 1;
    localparam integer GAIN_SPAN = 65535-MIN_GAIN;
    localparam [15:0] IDLE_GAIN = GAIN_REVERSE ? 16'hffff : MIN_GAIN;
    localparam [27:0] SCALE_Q12 = (GAIN_SPAN*4096 + ADC_SPAN/2)/ADC_SPAN;
    wire [9:0] directed_code = ADC_INVERT ? 10'd1023-adc_sample : adc_sample;
    reg [9:0] offset_code;
    reg [1:0] limit1, limit2;
    reg valid1, valid2;
    reg [37:0] mapped_product;
    wire [38:0] gain_delta = {1'b0, mapped_product} >> 12;
    wire [38:0] mapped_gain = GAIN_REVERSE ? 39'd65535-gain_delta :
                                                {23'd0, MIN_GAIN}+gain_delta;
    // Inactive expression smoothly returns to unity, using the latest target
    // again when enabled. ADC calibration remains live in both modes.
    wire [15:0] slew_target_gain = expression_enable ? target_gain : 16'hffff;

    always @(posedge clk) begin
        if (!resetn) begin
            pressure_code <= 0;
            target_gain <= IDLE_GAIN;
            gain <= IDLE_GAIN;
            offset_code <= 0;
            limit1 <= 0;
            limit2 <= 0;
            valid1 <= 0;
            valid2 <= 0;
            mapped_product <= 0;
        end else begin
            valid1 <= adc_valid;
            valid2 <= valid1;
            if (adc_valid) begin
                pressure_code <= directed_code;
                if (directed_code <= ADC_ZERO) begin
                    offset_code <= 0;
                    limit1 <= 0;
                end else if (directed_code >= ADC_FULL) begin
                    offset_code <= ADC_SPAN;
                    limit1 <= 2;
                end else begin
                    offset_code <= directed_code-ADC_ZERO;
                    limit1 <= 1;
                end
            end
            if (valid1) begin
                mapped_product <= offset_code * SCALE_Q12;
                limit2 <= limit1;
            end
            if (valid2) begin
                if (limit2 == 0)
                    target_gain <= IDLE_GAIN;
                else if (limit2 == 2)
                    target_gain <= GAIN_REVERSE ? MIN_GAIN : 16'hffff;
                else if (mapped_gain >= 65535)
                    target_gain <= 16'hffff;
                else if (mapped_gain <= MIN_GAIN)
                    target_gain <= MIN_GAIN;
                else
                    target_gain <= mapped_gain[15:0];
            end
            // Linear slew on audio frames prevents abrupt volume jumps.
            if (sample_ce) begin
                if (gain < slew_target_gain) begin
                    if (slew_target_gain-gain > SLEW_STEP)
                        gain <= gain+SLEW_STEP;
                    else
                        gain <= slew_target_gain;
                end else if (gain > slew_target_gain) begin
                    if (gain-slew_target_gain > SLEW_STEP)
                        gain <= gain-SLEW_STEP;
                    else
                        gain <= slew_target_gain;
                end
            end
        end
    end
endmodule
