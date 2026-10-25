`timescale 1ns/1ps
// Procedural approximations: breathy flute, short plucked ukulele, pitched tom.
// Shares the existing harmonic oscillators. No stored audio or sample playback.
module extra_voices (
    input wire clk, resetn, sample_ce, trigger_note,
    input wire [31:0] phase_inc, event_inc,
    input wire signed [15:0] fundamental, partial2, partial3, partial4,
    output wire signed [15:0] flute_sample, ukulele_sample, drum_sample
);
    reg [16:0] noise_state;
    wire signed [15:0] noise = noise_state[15:0];
    reg signed [17:0] air_low;
    wire signed [17:0] noise_wide = {{2{noise[15]}},noise};
    wire signed [17:0] air_high = noise_wide - air_low;
    always @(posedge clk) begin
        if (!resetn) begin noise_state <= 17'h1ACE1; air_low <= 0; end
        else if (sample_ce) begin
            noise_state <= {noise_state[15:0],noise_state[16]^noise_state[13]};
            air_low <= air_low + (air_high >>> 3);
        end
    end
    reg [15:0] flute_env;
    reg [23:0] string_body, string_bright, drum_body, drum_hit;
    reg [31:0] drum_glide;
    always @(posedge clk) begin
        if (!resetn) begin
            flute_env <= 0; string_body <= 0; string_bright <= 0;
            drum_body <= 0; drum_hit <= 0; drum_glide <= 0;
        end else if (trigger_note) begin
            flute_env <= 0; string_body <= 24'hFFFFFF; string_bright <= 24'hFFFFFF;
            drum_body <= 24'hFFFFFF; drum_hit <= 24'hFFFFFF;
            drum_glide <= event_inc << 1;
        end else if (sample_ce) begin
            // Flute's breath attack is about 21ms; final release is in gesture_audio.
            if (flute_env < 16'd65471) flute_env <= flute_env + 16'd64;
            else flute_env <= 16'hFFFF;
            // The plucked string loses brightness much faster than body energy.
            if (string_body != 0) string_body <= string_body - (string_body >> 13) - 1'b1;
            if (string_bright != 0) string_bright <= string_bright - (string_bright >> 10) - 1'b1;
            if (drum_body != 0) drum_body <= drum_body - (drum_body >> 11) - 1'b1;
            if (drum_hit != 0) drum_hit <= drum_hit - (drum_hit >> 8) - 1'b1;
            if (drum_glide != 0) drum_glide <= drum_glide - (drum_glide >> 8) - 1'b1;
        end
    end
    wire signed [17:0] base = {{2{fundamental[15]}},fundamental};
    wire signed [17:0] h2 = {{2{partial2[15]}},partial2};
    wire signed [17:0] h3 = {{2{partial3[15]}},partial3};
    wire signed [17:0] h4 = {{2{partial4[15]}},partial4};
    wire signed [17:0] flute_wave = (base >>> 1) + (base >>> 2) +
                                    (h2 >>> 3) + (h3 >>> 4) + (air_high >>> 7);
    wire signed [17:0] string_low, string_high, drum_tone, drum_noise;
    reg signed [17:0] flute_frame, string_low_frame, string_high_frame, drum_tone_frame, drum_noise_frame;
    reg [15:0] flute_env_frame, string_body_frame, string_bright_frame, drum_body_frame, drum_hit_frame;
    // Split harmonic lookup/mixing from envelope multiplication at a sample
    // boundary. Every waveform and its envelope travel through the same stage.
    always @(posedge clk) begin
        if (!resetn) begin
            flute_frame <= 0; string_low_frame <= 0; string_high_frame <= 0;
            drum_tone_frame <= 0; drum_noise_frame <= 0;
            flute_env_frame <= 0; string_body_frame <= 0; string_bright_frame <= 0;
            drum_body_frame <= 0; drum_hit_frame <= 0;
        end else if (sample_ce) begin
            flute_frame <= flute_wave; flute_env_frame <= flute_env;
            string_low_frame <= string_low; string_high_frame <= string_high;
            string_body_frame <= string_body[23:8]; string_bright_frame <= string_bright[23:8];
            drum_tone_frame <= drum_tone; drum_noise_frame <= drum_noise;
            drum_body_frame <= drum_body[23:8]; drum_hit_frame <= drum_hit[23:8];
        end
    end
    wire signed [34:0] flute_product = flute_frame * $signed({1'b0,flute_env_frame});
    assign flute_sample = flute_product[31:16];

    assign string_low = (base >>> 1) + (h2 >>> 2);
    assign string_high = (h3 >>> 3) + (h4 >>> 4) + (noise_wide >>> 5);
    wire signed [34:0] string_low_product = string_low_frame * $signed({1'b0,string_body_frame});
    wire signed [34:0] string_high_product = string_high_frame * $signed({1'b0,string_bright_frame});
    wire signed [35:0] string_mix = $signed({string_low_product[34],string_low_product}) +
                                   $signed({string_high_product[34],string_high_product});
    assign ukulele_sample = string_mix[31:16];

    // A brief pitch drop and noise transient create a tom-like pitched drum.
    // End frequency follows the chosen note, so both four-note banks remain useful.
    wire signed [15:0] drum_wave;
    gesture_nco_sine u_drum (.clk(clk), .resetn(resetn), .sample_ce(sample_ce),
                     .phase_inc(phase_inc + drum_glide), .sample(drum_wave));
    wire signed [17:0] drum_wide = {{2{drum_wave[15]}},drum_wave};
    assign drum_tone = (drum_wide >>> 1) + (drum_wide >>> 2) + (drum_wide >>> 3);
    assign drum_noise = noise_wide >>> 4;
    wire signed [34:0] drum_tone_product = drum_tone_frame * $signed({1'b0,drum_body_frame});
    wire signed [34:0] drum_noise_product = drum_noise_frame * $signed({1'b0,drum_hit_frame});
    wire signed [35:0] drum_mix = $signed({drum_tone_product[34],drum_tone_product}) +
                                 $signed({drum_noise_product[34],drum_noise_product});
    assign drum_sample = drum_mix[31:16];
endmodule

