`timescale 1ns/1ps
// One independently controlled, continuously running DDS and ADSR voice.
module synth_voice #(
    parameter VOLUME_SHIFT = 4,
    parameter RUNTIME_ADSR = 0,
    parameter PIPELINE_OSCILLATOR = 0,
    parameter ATTACK_SAMPLES = 98,
    parameter DECAY_SAMPLES = 3906,
    parameter [15:0] SUSTAIN_LEVEL = 16'd39321,
    parameter RELEASE_SAMPLES = 24414
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire [63:0] adsr_config,
    input wire gate,
    input wire [31:0] phase_inc,
    output wire signed [15:0] sample,
    output wire [15:0] envelope_gain,
    output wire [2:0] envelope_state,
    output wire active
);
    wire signed [15:0] oscillator_sample;
    wire signed [15:0] gain_input;
    // At least two fabric clocks between sample enables in this mode.
    // Phase holds between frames, so this fabric register preserves the
    // exact sample seen by the frame-enabled envelope multiplier.
    generate if(PIPELINE_OSCILLATOR)begin: pipeline
        reg signed [15:0] held_sample;
        always @(posedge clk)held_sample<=oscillator_sample;
        assign gain_input=held_sample;
    end else begin: direct
        assign gain_input=oscillator_sample;
    end endgenerate
    dds_voice u_dds (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .phase_inc(phase_inc), .sample(oscillator_sample)
    );
    adsr_env #(
        .RUNTIME_ADSR(RUNTIME_ADSR),
        .ATTACK_SAMPLES(ATTACK_SAMPLES), .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .RELEASE_SAMPLES(RELEASE_SAMPLES)
    ) u_adsr (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce), .gate(gate),
        .adsr_config(adsr_config),.gain(envelope_gain), .state(envelope_state), .active(active)
    );
    // Do not gate with gate/active: a note-off must preserve its release tail.
    envelope_gain #(.VOLUME_SHIFT(VOLUME_SHIFT)) u_gain (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .sample_in(gain_input), .gain(envelope_gain), .sample_out(sample)
    );
endmodule
