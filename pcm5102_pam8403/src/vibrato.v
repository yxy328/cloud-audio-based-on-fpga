`timescale 1ns/1ps
// Pitch vibrato: 6 Hz sine, +/-1/64 of nominal frequency (about 27 cents).
// One sample enable per 1024 system clocks, with phase continuous at all times.
// Enable depth ramps over 256 samples (5.24ms); no note/envelope retrigger.
module vibrato(
    input wire clk, resetn, sample_ce, enabled,
    input wire [31:0] nominal_inc,
    input wire [31:0] vibrato_inc,
    input wire [9:0] vibrato_depth,
    input wire [15:0] vibrato_delay,
    input wire vibrato_update,
    output wire [31:0] phase_inc
);
    wire signed [15:0] lfo_sample;
    gesture_nco_sine u_lfo (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .phase_inc(vibrato_inc), .sample(lfo_sample)
    );
    reg [9:0] depth;
    reg [15:0] vibrato_wait;
    always @(posedge clk)begin
        if(!resetn || vibrato_update || !enabled)vibrato_wait<=vibrato_delay;
        else if(sample_ce && vibrato_wait!=0)vibrato_wait<=vibrato_wait-1'b1;
    end
    always @(posedge clk) begin
        if (!resetn) depth <= 0;
        else if (sample_ce) begin
            if(enabled && vibrato_wait==0 && depth<vibrato_depth)depth<=depth+1'b1;
            else if((!enabled || vibrato_wait!=0 || depth>vibrato_depth) && depth!=0)depth<=depth-1'b1;
        end
    end

    // Separate the two products with registers. They settle between sample
    // enables; neither the I2S timing nor the existing audio pipeline changes.
    reg signed [25:0] depth_product;
    wire signed [17:0] lfo_scaled = $signed(depth_product[25:8]);
    reg signed [48:0] pitch_product;
    reg [31:0] product_nominal;
    always @(posedge clk) begin
        if (!resetn) begin
            depth_product <= 0; pitch_product <= 0; product_nominal <= 0;
        end else begin
            depth_product <= lfo_sample * $signed({1'b0,depth});
            pitch_product <= $signed({1'b0,nominal_inc}) * lfo_scaled;
            product_nominal <= nominal_inc;
        end
    end
    // 32768 * 64 = 2^21. Preserve sign before adding to the unsigned pitch.
    wire signed [48:0] delta = pitch_product >>> 21;
    wire signed [48:0] adjusted = $signed({17'd0,nominal_inc}) + delta;
    // If a new note arrives immediately before sample_ce, use its exact pitch
    // for that first sample rather than a stale offset from the previous note.
    // With depth zero, this is bit-exact to the pre-vibrato firmware.
    assign phase_inc = (product_nominal == nominal_inc) ? adjusted[31:0] : nominal_inc;
endmodule

