`timescale 1ns/1ps
// Eight break beams: light received = 0, blocked = 1.
// A channel must first see stable light before it can produce a note. This
// also prevents unused inputs, held high by FPGA pull-ups, from playing notes.
module ir_strings #(
    parameter integer FILTER_CYCLES = 50000 // 1 ms at 50 MHz, on BOTH edges
)(
    input wire clk, rst_n,
    input wire [7:0] beam_in,
    output reg [7:0] blocked,
    output reg [7:0] armed,
    output wire note_valid,
    output reg [2:0] note_index
);
    localparam integer COUNT_WIDTH = (FILTER_CYCLES <= 1) ? 1 : $clog2(FILTER_CYCLES);
    (* syn_preserve = 1 *) reg [7:0] beam_meta;
    (* syn_preserve = 1 *) reg [7:0] beam_sync;
    reg [7:0] trigger_pulse;
    always @(posedge clk) begin
        if (!rst_n) begin beam_meta <= 8'hFF; beam_sync <= 8'hFF; end
        else begin beam_meta <= beam_in; beam_sync <= beam_meta; end
    end

    genvar ch;
    generate for (ch=0; ch<8; ch=ch+1) begin: channels
        reg [COUNT_WIDTH-1:0] count;
        always @(posedge clk) begin
            if (!rst_n) begin
                count <= 0; blocked[ch] <= 1; armed[ch] <= 0; trigger_pulse[ch] <= 0;
            end else begin
                trigger_pulse[ch] <= 0;
                if (beam_sync[ch] == blocked[ch]) count <= 0;
                else if (count == FILTER_CYCLES-1) begin
                    count <= 0;
                    blocked[ch] <= beam_sync[ch];
                    if (!beam_sync[ch]) armed[ch] <= 1;
                    else begin
                        trigger_pulse[ch] <= armed[ch];
                        armed[ch] <= 0;
                    end
                end else count <= count + 1'b1;
            end
        end
    end endgenerate

    // Preserve every qualified channel, then dispatch one note per system
    // clock. The polyphonic allocator reserves each voice on that same clock,
    // so simultaneous beams can fill four voices before the next audio frame.
    // Eight channels drain in at most eight clocks (160 ns at 50 MHz), far
    // faster than a channel can rearm with the default 1 ms edge filter.
    reg [7:0] pending_notes;
    wire [7:0] available_notes = pending_notes | trigger_pulse;
    wire [7:0] dispatched_note = note_valid ? (8'b00000001 << note_index) : 8'd0;
    integer i;
    assign note_valid = |available_notes;
    always @(*) begin
        note_index = 0;
        for (i=7; i>=0; i=i-1)
            if (available_notes[i]) note_index = i;
    end
    always @(posedge clk) begin
        if (!rst_n) pending_notes <= 0;
        else pending_notes <= available_notes & ~dispatched_note;
    end
endmodule
