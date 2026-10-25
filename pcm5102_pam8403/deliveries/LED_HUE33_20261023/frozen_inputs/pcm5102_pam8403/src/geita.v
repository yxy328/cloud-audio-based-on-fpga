`timescale 1ns/1ps
// Single-string Karplus--Strong. All logic runs on clk, sample_ce once/frame.
// f ~= Fs/(STRING_LENGTH + 0.5); default 48828.125/110.5 = 441.88 Hz.
module geita #(
    parameter STRING_LENGTH = 110, // 2..1024
    parameter DEBOUNCE_CYCLES = 250000, // 5 ms at 50 MHz
    parameter LOSS_SHIFT = 9, // feedback gain 1 - 2^-LOSS_SHIFT (1..15)
    parameter EXTERNAL_TRIGGER = 0 // 1: synchronous one-clock pluck, 0: S1
) (
    input wire clk, resetn, key_s1, sample_ce,
    output reg signed [15:0] sample,
    input wire pluck
);
    (* syn_preserve = 1 *) reg key_meta;
    (* syn_preserve = 1 *) reg key_sync;
    reg key_stable, pending;
    reg [31:0] debounce_count;
    reg [31:0] lfsr;
    reg [9:0] pointer;
    reg [10:0] fill_remaining;
    reg active;
    reg [1:0] state;
    reg signed [15:0] delay_line [0:STRING_LENGTH-1];
    reg signed [15:0] delayed, previous;
    wire signed [16:0] pair_sum =
        {delayed[15], delayed} + {previous[15], previous};
    // Truncate toward zero symmetrically; ceil loss prevents DC limit cycles.
    wire signed [16:0] average = pair_sum / 17'sd2;
    wire [16:0] magnitude = average[16] ? -average : average;
    wire [16:0] loss = (magnitude + ((17'd1 << LOSS_SHIFT)-1)) >> LOSS_SHIFT;
    wire signed [16:0] remaining = magnitude - loss;
    wire signed [16:0] feedback = average[16] ? -remaining : remaining;
    wire signed [15:0] noise = lfsr[0] ? 16'sd16384 : -16'sd16384;
    wire [10:0] pointer_plus_one = {1'b0,pointer} + 11'd1;
    wire [9:0] next_pointer = (pointer == STRING_LENGTH-1) ?
                             10'd0 : pointer_plus_one[9:0];

    always @(posedge clk) begin
        if (!resetn) begin
            key_meta <= 0; key_sync <= 0; key_stable <= 0;
            debounce_count <= 0; pending <= 0;
            lfsr <= 32'h1acebeef;
            pointer <= 0; fill_remaining <= 0; active <= 0;
            state <= 0; delayed <= 0; previous <= 0; sample <= 0;
        end
    else begin
            lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
            if (EXTERNAL_TRIGGER) begin
                // Capture an event between audio frames; the next frame
                // starts excitation. Unconnected pluck is ignored in S1 mode.
                if (pluck) pending <= 1;
            end else begin
                key_meta <= key_s1;
                key_sync <= key_meta;
                if (key_sync == key_stable) debounce_count <= 0;
                else if (debounce_count == DEBOUNCE_CYCLES-1) begin
                    debounce_count <= 0;
                    key_stable <= key_sync;
                    if (key_sync) pending <= 1;
                end else debounce_count <= debounce_count + 1;
            end

            // Read then compute/write on separate clocks, allowing sync RAM.
            if (state == 1) begin
                delay_line[pointer] <= feedback[15:0];
                sample <= delayed;
                previous <= delayed;
                pointer <= next_pointer;
                state <= 0;
            end else if (sample_ce) begin
                if (pending) begin
                    pending <= 0;
                    pointer <= 0;
                    fill_remaining <= STRING_LENGTH;
                    active <= 0;
                    previous <= 0;
                    sample <= 0;
                end else if (fill_remaining != 0) begin
                    delay_line[pointer] <= noise;
                    sample <= noise;
                    pointer <= next_pointer;
                    fill_remaining <= fill_remaining - 1'b1;
                    if (fill_remaining == 1) begin
                        active <= 1;
                        previous <= noise;
                    end
                end else if (active) begin
                    delayed <= delay_line[pointer];
                    state <= 1;
                end else sample <= 0;
            end
        end
    end
endmodule
