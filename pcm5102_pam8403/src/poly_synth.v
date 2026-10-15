`timescale 1ns/1ps
// Four independent voice controls. Voice 0 occupies the LOW packed slice.
// All voices advance on the same sample_ce. Only one mixed PCM stream leaves.
module poly_synth #(
    parameter VOLUME_SHIFT = 4,
    parameter MIX_SHIFT = 0,
    parameter ATTACK_SAMPLES = 98,
    parameter DECAY_SAMPLES = 3906,
    parameter [15:0] SUSTAIN_LEVEL = 16'd39321,
    parameter RELEASE_SAMPLES = 24414
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire [3:0] gates,
    input wire [127:0] phase_increments,
    output wire signed [15:0] sample,
    output wire [63:0] voice_samples,
    output wire [63:0] envelope_gains,
    output wire [11:0] envelope_states,
    output wire [3:0] active,
    output wire clipped
);
    genvar voice_index;
    generate
        for (voice_index=0; voice_index<4; voice_index=voice_index+1) begin: voices
            synth_voice #(
                .VOLUME_SHIFT(VOLUME_SHIFT), .ATTACK_SAMPLES(ATTACK_SAMPLES),
                .DECAY_SAMPLES(DECAY_SAMPLES), .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
                .RELEASE_SAMPLES(RELEASE_SAMPLES)
            ) u_voice (
                .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
                .gate(gates[voice_index]),
                .phase_inc(phase_increments[voice_index*32 +: 32]),
                .sample(voice_samples[voice_index*16 +: 16]),
                .envelope_gain(envelope_gains[voice_index*16 +: 16]),
                .envelope_state(envelope_states[voice_index*3 +: 3]),
                .active(active[voice_index])
            );
        end
    endgenerate
    audio_mixer #(.MIX_SHIFT(MIX_SHIFT)) u_mixer (
        .clk(clk), .resetn(resetn), .sample_ce(sample_ce),
        .sample0(voice_samples[15:0]), .sample1(voice_samples[31:16]),
        .sample2(voice_samples[47:32]), .sample3(voice_samples[63:48]),
        .sample_out(sample), .clipped(clipped)
    );
endmodule
