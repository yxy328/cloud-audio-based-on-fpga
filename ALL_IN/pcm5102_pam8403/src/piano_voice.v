`timescale 1ns/1ps
// A small additive piano approximation, not a recording of an acoustic piano.
// The fundamental decays slowly, while upper partials decay quickly to soften
// the attack. All oscillators retain phase across notes; final gain ramps are
// handled by gesture_audio. 24-bit envelopes avoid a short quantized tail.
module piano_voice (
    input wire clk, resetn, sample_ce, trigger_note,
    input wire [31:0] phase_inc,
    input wire signed [15:0] fundamental,
    output wire signed [15:0] sample,
    output wire signed [15:0] partial2, partial3, partial4
);
    wire signed [15:0] h2, h3, h4;
    assign partial2 = h2;
    assign partial3 = h3;
    assign partial4 = h4;
    nco_sine u_h2 (.clk(clk), .resetn(resetn), .sample_ce(sample_ce),
                   .phase_inc(phase_inc << 1), .sample(h2));
    nco_sine u_h3 (.clk(clk), .resetn(resetn), .sample_ce(sample_ce),
                   .phase_inc(phase_inc + (phase_inc << 1)), .sample(h3));
    nco_sine u_h4 (.clk(clk), .resetn(resetn), .sample_ce(sample_ce),
                   .phase_inc(phase_inc << 2), .sample(h4));

    reg [23:0] body_env, bright_env;
    always @(posedge clk) begin
        if (!resetn) begin body_env <= 0; bright_env <= 0; end
        else if (trigger_note) begin
            body_env <= 24'hFFFFFF; bright_env <= 24'hFFFFFF;
        end else if (sample_ce) begin
            // Time constants at 48828.125 Hz: about 336ms and 42ms.
            if (body_env != 0) body_env <= body_env - (body_env >> 14) - 1'b1;
            if (bright_env != 0) bright_env <= bright_env - (bright_env >> 11) - 1'b1;
        end
    end

    // Absolute weights sum to 1: .75 fundamental, .125 second, .0625 each
    // third/fourth. Signed extensions are explicit to prevent mix overflow.
    wire signed [17:0] base = {{2{fundamental[15]}}, fundamental};
    wire signed [17:0] overtone2 = {{2{h2[15]}}, h2};
    wire signed [17:0] overtone3 = {{2{h3[15]}}, h3};
    wire signed [17:0] overtone4 = {{2{h4[15]}}, h4};
    wire signed [17:0] body = (base >>> 1) + (base >>> 2);
    wire signed [17:0] bright = (overtone2 >>> 3) +
                              (overtone3 >>> 4) + (overtone4 >>> 4);
    wire signed [34:0] body_product = body * $signed({1'b0,body_env[23:8]});
    wire signed [34:0] bright_product = bright * $signed({1'b0,bright_env[23:8]});
    wire signed [35:0] mix = $signed({body_product[34],body_product}) +
                            $signed({bright_product[34],bright_product});
    wire signed [35:0] scaled = mix >>> 16;
    assign sample = scaled[15:0];
endmodule
