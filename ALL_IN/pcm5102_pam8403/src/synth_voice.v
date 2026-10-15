`timescale 1ns/1ps
// One independently controlled, continuously running DDS and ADSR voice.
module synth_voice #(
    parameter VOLUME_SHIFT = 4,
    parameter ATTACK_SAMPLES = 98,
    parameter DECAY_SAMPLES = 3906,
    parameter [15:0] SUSTAIN_LEVEL = 16'd39321,
    parameter RELEASE_SAMPLES = 24414
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire gate,
    input wire [31:0] phase_inc,
    output wire signed [15:0] sample,
    output wire [15:0] envelope_gain,
    output wire [2:0] envelope_state,
    output wire active
);
    wire signed [15:0] oscillator_sample;
    dds_voice u_dds (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .phase_inc(phase_inc), .sample(oscillator_sample)
    );
    adsr_env #(
        .ATTACK_SAMPLES(ATTACK_SAMPLES), .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_SAMPLES(RELEASE_SAMPLES)
    ) u_adsr (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce), .gate(gate),
        .gain(envelope_gain), .state(envelope_state), .active(active)
    );
    // Do not gate with gate/active: a note-off must preserve its release tail.
    envelope_gain #(.VOLUME_SHIFT(VOLUME_SHIFT)) u_gain (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .sample_in(oscillator_sample), .gain(envelope_gain), .sample_out(sample)
    );
endmodule
