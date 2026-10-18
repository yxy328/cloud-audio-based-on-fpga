`timescale 1ns/1ps
// TTP229-BSF, TP1 open: active-low serial interface (not I2C).
// D0..D15 follow successive falling SCL edges. Idle high for >2ms
// resets the chip's serial counter; wait for DV to finish before a read.
module ttp229_keys #(
    parameter integer STARTUP_CYCLES = 30000000, // 600ms at 50MHz
    parameter integer HALF_PERIOD_CYCLES = 500, // 50kHz SCL; 10us per level
    parameter integer GAP_CYCLES = 125000,      // 2.5ms; >2ms serial reset
    parameter integer QUIET_CYCLES = 1000,     // 20us high after DV
    parameter integer CONFIRM_CYCLES = 0,       // two matching frames, no extra dwell
    parameter integer TIMEOUT_CYCLES = 5000000  // 100ms without a clean frame
)(
    input wire clk, rst_n, sdo,
    output reg scl,
    output reg [15:0] keys_down,
    output reg [15:0] raw_keys,
    output reg scan_valid, scan_error,
    output reg ready,
    output wire note_valid,
    output reg [3:0] note_index,
    input wire note_ready
);
    (* syn_preserve = 1 *) reg sdo_meta, sdo_sync;
    always @(posedge clk) begin
        if (!rst_n) begin sdo_meta <= 1; sdo_sync <= 1; end
        else begin sdo_meta <= sdo; sdo_sync <= sdo_meta; end
    end

    localparam [2:0] BOOT=0, GAP=1, QUIET=2, LOW=3, HIGH=4, COMMIT=5;
    reg [2:0] state;
    localparam MAX_BOOT_GAP=STARTUP_CYCLES>GAP_CYCLES ? STARTUP_CYCLES : GAP_CYCLES;
    localparam MAX_QUIET_HALF=QUIET_CYCLES>HALF_PERIOD_CYCLES ? QUIET_CYCLES : HALF_PERIOD_CYCLES;
    localparam MAX_COUNT=MAX_BOOT_GAP>MAX_QUIET_HALF ? MAX_BOOT_GAP : MAX_QUIET_HALF;
    localparam COUNT_BITS=MAX_COUNT<2 ? 1 : $clog2(MAX_COUNT);
    localparam CONFIRM_BITS=CONFIRM_CYCLES<1 ? 1 : $clog2(CONFIRM_CYCLES+1);
    localparam TIMEOUT_BITS=TIMEOUT_CYCLES<1 ? 1 : $clog2(TIMEOUT_CYCLES+1);
    reg [COUNT_BITS-1:0] count;
    reg [3:0] bit_index;
    reg [15:0] scan, previous_scan, armed, pressed;
    reg low_sample, frame_error, previous_valid;
    // Vote over the latter half of EACH SCL level, after settling. A short
    // pulse is corrected rather than causing fix25's whole-frame rejection.
    // Both windows must be >=75% consistent and agree. Frame confirmation,
    // serial timing and true 16-key chords remain unchanged.
    localparam integer SAMPLE_SETTLE_CYCLES = HALF_PERIOD_CYCLES/2;
    localparam integer WINDOW_CYCLES = HALF_PERIOD_CYCLES-SAMPLE_SETTLE_CYCLES;
    localparam integer VOTE_THRESHOLD = (WINDOW_CYCLES*3+3)/4;
    localparam integer VOTE_WIDTH = (HALF_PERIOD_CYCLES<2) ? 1 : $clog2(HALF_PERIOD_CYCLES+1);
    reg [VOTE_WIDTH-1:0] sample_ones;
    wire [VOTE_WIDTH:0] votes_now={1'b0,sample_ones}+sdo_sync;
    wire vote_high=votes_now>=VOTE_THRESHOLD;
    wire vote_low=votes_now<=WINDOW_CYCLES-VOTE_THRESHOLD;
    reg [CONFIRM_BITS-1:0] stable_cycles;
    reg [TIMEOUT_BITS-1:0] stale_cycles;
    // Two clean, identical WHOLE frames avoid mixing bits from different
    // serial reads. No added 40ms dwell: default transport acceptance is
    // <6.1ms after a stable sensor report. This cannot reject a persistent
    // false report or shorten the TTP229's own touch detection latency.
    wire accept_frame = !frame_error && previous_valid && (scan == previous_scan) &&
                        stable_cycles >= CONFIRM_CYCLES;
    wire read_timeout = state!=BOOT && stale_cycles>=TIMEOUT_CYCLES-1;
    always @(posedge clk) begin
        if(!rst_n || state==BOOT || read_timeout) begin stable_cycles<=0; stale_cycles<=0; end
        else begin
            if(state==COMMIT && !frame_error) stale_cycles<=0;
            else if(stale_cycles<TIMEOUT_CYCLES) stale_cycles<=stale_cycles+1'b1;
            if(state==COMMIT && (frame_error || !previous_valid || scan!=previous_scan)) stable_cycles<=0;
            else if(previous_valid && stable_cycles<CONFIRM_CYCLES) stable_cycles<=stable_cycles+1'b1;
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= BOOT; count <= 0; scl <= 1; bit_index <= 0;
            scan <= 0; previous_scan <= 0; keys_down <= 0;
            raw_keys <= 0; scan_valid <= 0; scan_error <= 0; ready<=0;
            low_sample <= 1; frame_error <= 0; previous_valid <= 0;
            sample_ones <= 0;
            armed <= 0; pressed <= 0;
        end else begin
            pressed <= 0;
            scan_valid <= 0;
            if(read_timeout) begin
                // No delayed keypress after a disconnected/stuck input.
                // Recovery first requires a new accepted release per key.
                state<=GAP; count<=0; scl<=1;
                keys_down<=0; armed<=0; previous_valid<=0; ready<=0;
                scan_valid<=1; scan_error<=1;
            end else case (state)
                BOOT: if (count >= STARTUP_CYCLES-1) begin
                    count <= 0; state <= GAP;
                end else count <= count+1'b1;
                GAP: if (count >= GAP_CYCLES-1) begin
                    count <= 0; state <= QUIET;
                end else count <= count+1'b1;
                QUIET: if (!sdo_sync) count <= 0;
                else if (count >= QUIET_CYCLES-1) begin
                    count <= 0; bit_index <= 0; frame_error <= 0;
                    sample_ones <= 0;
                    scl <= 0; state <= LOW;
                end else count <= count+1'b1;
                LOW: begin
                    if(count>=SAMPLE_SETTLE_CYCLES) sample_ones<=votes_now[VOTE_WIDTH-1:0];
                    if (count >= HALF_PERIOD_CYCLES-1) begin
                        low_sample<=vote_high;sample_ones<=0;
                        if(!vote_high && !vote_low) frame_error<=1;
                        scl <= 1; count <= 0; state <= HIGH;
                    end else count <= count+1'b1;
                end
                HIGH: begin
                    if(count>=SAMPLE_SETTLE_CYCLES) sample_ones<=votes_now[VOTE_WIDTH-1:0];
                    if (count >= HALF_PERIOD_CYCLES-1) begin
                        count <= 0;sample_ones<=0;
                        if((!vote_high && !vote_low) || vote_high!=low_sample) frame_error<=1;
                        // RAW is the decoded window vote, before frame qualification.
                        scan[bit_index] <= ~vote_high;
                        if (bit_index == 15) state <= COMMIT;
                        else begin bit_index <= bit_index+1'b1; scl <= 0; state <= LOW; end
                    end else count <= count+1'b1;
                end
                COMMIT: begin
                    raw_keys <= scan; scan_valid <= 1; scan_error <= frame_error;
                    if(accept_frame) begin
                        ready<=1;
                        keys_down <= scan;
                        pressed <= scan & ~keys_down & armed;
                        // A key must have an accepted release before it fires.
                        armed <= ~scan;
                    end
                    previous_scan <= scan;
                    previous_valid <= !frame_error;
                    count <= 0; state <= GAP;
                end
                default: begin scl <= 1; count <= 0; state <= BOOT; end
            endcase
        end
    end

    // Backpressure lets IR/gestures/demo commands keep their normal timing.
    // One pending bit per key; at normal human input rates all sixteen drain
    // within 16 clocks. Holding a key never generates repeated notes.
    reg [15:0] pending_notes;
    wire [15:0] available = (pending_notes | pressed) & keys_down;
    wire [15:0] consumed = (note_valid && note_ready) ? (16'h1 << note_index) : 16'd0;
    integer i;
    assign note_valid = |available;
    always @(*) begin
        note_index = 0;
        for (i=15; i>=0; i=i-1) if (available[i]) note_index = i[3:0];
    end
    always @(posedge clk) begin
        if (!rst_n || read_timeout) pending_notes <= 0;
        else pending_notes <= available & ~consumed;
    end
endmodule
