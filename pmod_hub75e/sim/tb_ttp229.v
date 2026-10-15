`timescale 1ns/1ps

// Self-checking simulation; run from the pmod_hub75e directory:
//   iverilog -g2012 -s tb_ttp229 -o sim/tb_ttp229.out src/ttp229_ctrl.v sim/tb_ttp229.v
//   vvp sim/tb_ttp229.out
// Add +dump to vvp only when a waveform is needed (tb_ttp229.vcd).
//
// Four independent checkers cover 8 / 16 keys and both SCL/SDO polarities.
// The serial model sends K1 first: key_state[i] must become touch_keys[i].
// Keep the 50 us SCL half-period and 20 us valid pulse, with a 3 ms idle
// interval so the chip's >2 ms serial timeout can rearm each transaction.
// Reading all keys does not wrap the chip model's bit index automatically.
// These fast serial tests override cold startup to 3 ms. The independent
// tb_ttp229_startup bench checks the real 600 ms startup at a 1 MHz clock.

module tb_ttp229;
    reg clk = 1'b0;
    wire [3:0] done;

    always #10 clk = ~clk; // 50 MHz

    ttp229_checker #(.KEY_NUM(16), .ACTIVE_LOW(1)) check_16_low
        (.clk(clk), .done(done[0]));
    ttp229_checker #(.KEY_NUM(16), .ACTIVE_LOW(0)) check_16_high
        (.clk(clk), .done(done[1]));
    ttp229_checker #(.KEY_NUM(8), .ACTIVE_LOW(1)) check_8_low
        (.clk(clk), .done(done[2]));
    ttp229_checker #(.KEY_NUM(8), .ACTIVE_LOW(0)) check_8_high
        (.clk(clk), .done(done[3]));

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("tb_ttp229.vcd");
            $dumpvars(0, tb_ttp229);
        end
        wait (&done);
        $display("PASS: TTP229 key order, polarity, timing, synchronization and reset recovery");
        $finish;
    end

    initial begin
        #50_000_000;
        $fatal(1, "FAIL: TTP229 simulation timed out");
    end
endmodule

// Independent black-box regression for the old high-polarity defect.
// Compile this top with either revision of ttp229_ctrl; it uses no new
// parameters or DUT internals. A real active-high chip advances on rising
// SCL, so K1 alone must remain bit 0 rather than shifting to bit 1.
module tb_ttp229_high_counterexample;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg sdo = 1'b0;
    wire scl;
    wire touch_valid;
    wire [15:0] touch_keys;
    integer chip_index = 0;
    time chip_last_edge = 0;
    reg chip_level = 1'b0;

    always #500 clk = ~clk; // 1 MHz keeps the full startup test inexpensive.
    ttp229_ctrl #(.CLK_FREQ(1_000_000), .KEY_NUM(16), .TP_ACTIVE_LOW(0)) dut (
        .clk(clk), .resetn(resetn), .sdo(sdo), .scl(scl),
        .touch_valid(touch_valid), .touch_keys(touch_keys),
        .state_o(), .bit_cnt_o()
    );

    // The chip is already powered and ready, and is independent of resetn.
    always @(scl) begin
        if (scl === 1'b0 || scl === 1'b1) begin
            if ($time - chip_last_edge > 2_000_000) begin
                chip_index = 0;
                chip_level = 1'b0;
            end
            chip_last_edge = $time;
            if (scl === 1'b1 && chip_index < 16) begin
                chip_level = (chip_index == 0); // K1 only
                chip_index = chip_index + 1;
            end
            #100;
            sdo = chip_level;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        resetn = 1'b1;
        @(posedge touch_valid);
        #1;
        if (touch_keys !== 16'h0001)
            $fatal(1, "FAIL: physical active-high chip, K1 expected 0001, observed %h", touch_keys);
        $display("PASS: physical active-high chip keeps K1 in bit 0");
        $finish;
    end
    initial begin
        #650_000_000;
        $fatal(1, "FAIL: physical active-high counterexample timed out");
    end
endmodule

module ttp229_checker #(
    parameter KEY_NUM = 16,
    parameter ACTIVE_LOW = 1
) (
    input wire clk,
    output reg done = 1'b0
);
    localparam HALF_TICKS = 2500; // 50 us at 50 MHz
    localparam VALID_TICKS = 1000; // 20 us at 50 MHz
    localparam IDLE_TICKS = 150000; // 3 ms at 50 MHz
    localparam FRAME_TICKS = 2 * KEY_NUM * HALF_TICKS + VALID_TICKS +
                            IDLE_TICKS - HALF_TICKS;
    localparam CHIP_TIMEOUT_NS = 2_000_000;
    localparam SCL_IDLE = ACTIVE_LOW ? 1'b1 : 1'b0;
    localparam SCL_ACTIVE = ~SCL_IDLE;
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_ACTIVE = 3'd1;
    localparam [2:0] S_VALID = 3'd2;

    reg resetn = 1'b0;
    reg sdo = ACTIVE_LOW ? 1'b1 : 1'b0;
    reg [KEY_NUM-1:0] key_state = {KEY_NUM{1'b0}};
    wire scl;
    wire touch_valid;
    wire [KEY_NUM-1:0] touch_keys;
    wire [2:0] state_o;
    wire [3:0] bit_cnt_o;

    ttp229_ctrl #(
        .CLK_FREQ(50_000_000),
        .KEY_NUM(KEY_NUM),
        .TP_ACTIVE_LOW(ACTIVE_LOW),
        .SCL_HALF_US(50),
        .VALID_PULSE_US(20),
        .FRAME_IDLE_US(3000),
        .STARTUP_US(3000)
    ) dut (
        .clk(clk), .resetn(resetn), .sdo(sdo), .scl(scl),
        .touch_valid(touch_valid), .touch_keys(touch_keys),
        .state_o(state_o), .bit_cnt_o(bit_cnt_o)
    );

    task fail;
        input [8*120-1:0] reason;
        begin
            $fatal(1, "FAIL [%0d keys, active_low=%0d, t=%0t]: %0s",
                   KEY_NUM, ACTIVE_LOW, $time, reason);
        end
    endtask

    // The chip receives SCL only; FPGA reset is not wired to the module.
    // An idle gap longer than 2 ms rearms the serial reader. Read completion
    // holds D(KEY_NUM-1), rather than silently wrapping back to K1.
    // Checking the timeout at the next SCL edge models the same frame
    // alignment without resetting this model from the FPGA reset signal.
    integer model_idx = 0;
    integer model_timeout_resets = 0;
    time model_last_edge = 0;
    reg [KEY_NUM-1:0] model_frame = {KEY_NUM{1'b0}};
    reg model_level = ACTIVE_LOW ? 1'b1 : 1'b0;
    wire chip_clock = ACTIVE_LOW ? ~scl : scl;
    always @(scl) begin
        if (scl === 1'b0 || scl === 1'b1) begin
            if (($time - model_last_edge) > CHIP_TIMEOUT_NS) begin
                model_idx = 0;
                model_level = SCL_IDLE;
                model_timeout_resets = model_timeout_resets + 1;
            end
            model_last_edge = $time;
            // Datasheet figure 3-4-1/2: TP1 changes the physical clock
            // edge as well as data polarity. Falling SCL selects a bit
            // for active-low; rising SCL selects it for active-high.
            if (scl === SCL_ACTIVE) begin
                if (model_idx == 0)
                    model_frame = key_state;
                if (model_idx < KEY_NUM) begin
                    model_level = ACTIVE_LOW ? ~model_frame[model_idx] : model_frame[model_idx];
                    model_idx = model_idx + 1;
                end
            end
            // Put chip data transitions between FPGA clock edges.
            #37;
            sdo = model_level;
        end
    end

    integer late_changes = 0;
    // Change raw SDO half a clock before every sample. The two synchronizer
    // stages must keep this late change out of the current sample. This also
    // makes replacing sdo_sync[1] with raw sdo fail the test deterministically.
    always @(negedge clk) begin
        if (!resetn) begin
            late_changes = 0;
        end
        else if (state_o == S_ACTIVE && dut.timer == 0) begin
            sdo = ~model_level;
            late_changes = late_changes + 1;
            // Restore the real chip's held bit after checking this sample.
            #37;
            sdo = model_level;
        end
    end

    integer cycle = 0;
    integer last_rise = 0;
    integer last_fall = 0;
    integer frame_falls = 0;
    integer valid_start = -1;
    integer previous_valid_start = -1;
    integer frames = 0;
    integer pulses = 0;
    reg previous_scl = SCL_IDLE;
    reg previous_valid = 1'b0;
    reg last_rise_completed_frame = 1'b0;
    reg [KEY_NUM-1:0] previous_keys = {KEY_NUM{1'b0}};

    // Check after the DUT's nonblocking assignments have settled.
    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            if (scl !== SCL_IDLE || touch_valid !== 1'b0 ||
                touch_keys !== {KEY_NUM{1'b0}} ||
                state_o !== S_IDLE || bit_cnt_o !== 4'd0)
                fail("synchronous reset did not clear outputs/state");
            cycle = 0;
            last_rise = 0;
            last_fall = 0;
            frame_falls = 0;
            valid_start = -1;
            previous_valid_start = -1;
            previous_scl = SCL_IDLE;
            previous_valid = 1'b0;
            last_rise_completed_frame = 1'b0;
            previous_keys = {KEY_NUM{1'b0}};
        end
        else begin
            cycle = cycle + 1;
            if (scl !== 1'b0 && scl !== 1'b1)
                fail("SCL contains an unknown value");
            if (touch_valid !== 1'b0 && touch_valid !== 1'b1)
                fail("touch_valid contains an unknown value");

            if (previous_scl == SCL_IDLE && scl == SCL_ACTIVE) begin
                if (cycle - last_rise != ((last_rise == 0) ? IDLE_TICKS :
                    (last_rise_completed_frame ? IDLE_TICKS + VALID_TICKS : HALF_TICKS)))
                    fail("SCL idle duration/startup/frame gap is wrong");
                if (state_o !== S_ACTIVE || bit_cnt_o != frame_falls)
                    fail("active SCL edge has wrong state or key index");
                if (touch_valid)
                    fail("SCL became active while touch_valid was asserted");
                last_fall = cycle;
                frame_falls = frame_falls + 1;
            end

            if (previous_scl == SCL_ACTIVE && scl == SCL_IDLE) begin
                if (cycle - last_fall != HALF_TICKS)
                    fail("SCL active duration is wrong");
                if (sdo === model_level || dut.sdo_now !== model_level)
                    fail("late raw SDO change was not isolated by the synchronizer");
                last_rise = cycle;
                last_rise_completed_frame = touch_valid;
            end

            if (touch_valid && !previous_valid) begin
                if (state_o !== S_VALID || scl !== SCL_IDLE || bit_cnt_o !== 4'd0)
                    fail("frame completion has wrong state/SCL/key index");
                if (frame_falls != KEY_NUM || late_changes != KEY_NUM)
                    fail("frame has wrong number of serial clocks/samples");
                if (model_idx != KEY_NUM)
                    fail("chip reader did not hold its last bit after a full transaction");
                if (touch_keys !== model_frame) begin
                    $display("Expected keys=%h, observed keys=%h", model_frame, touch_keys);
                    fail("key order, key polarity or sample data is wrong");
                end
                if (previous_valid_start >= 0 &&
                    cycle - previous_valid_start != FRAME_TICKS)
                    fail("frame-to-frame polling period is wrong");
                previous_valid_start = cycle;
                valid_start = cycle;
                frame_falls = 0;
                late_changes = 0;
                frames = frames + 1;
            end
            else if (touch_keys !== previous_keys)
                fail("touch_keys changed outside frame completion");

            if (!touch_valid && previous_valid) begin
                if (cycle - valid_start != VALID_TICKS)
                    fail("touch_valid pulse width is wrong");
                pulses = pulses + 1;
            end
            if (touch_valid && (state_o !== S_VALID || scl !== SCL_IDLE))
                fail("valid pulse is not held with SCL idle");

            previous_scl = scl;
            previous_valid = touch_valid;
            previous_keys = touch_keys;
        end
    end

    integer model_idx_before_reset;
    integer model_timeouts_before_reset;
    initial begin
        // K1 alone and K(KEY_NUM) alone detect reversed serial bit order.
        key_state = {{(KEY_NUM-1){1'b0}}, 1'b1};
        repeat (5) @(negedge clk);
        resetn = 1'b1;
        wait (frames == 1);
        @(negedge clk);
        key_state = {1'b1, {(KEY_NUM-1){1'b0}}};
        wait (frames == 2);
        @(negedge clk);
        key_state = 16'h96A5; // asymmetric, including multiple keys
        wait (frames == 3);
        @(negedge clk);
        key_state = {KEY_NUM{1'b0}};
        wait (frames == 4);

        // Abort a partially collected frame, then verify a fresh key pattern.
        wait (!touch_valid);
        repeat (4) @(posedge chip_clock);
        repeat (13) @(negedge clk);
        model_idx_before_reset = model_idx;
        model_timeouts_before_reset = model_timeout_resets;
        resetn = 1'b0;
        key_state = 16'h5248;
        repeat (4) @(negedge clk);
        if (model_idx != model_idx_before_reset)
            fail("FPGA reset incorrectly reset the independently powered chip model");
        resetn = 1'b1;
        wait (frames == 5);
        if (model_timeout_resets != model_timeouts_before_reset + 1)
            fail("partial-frame reset recovery did not wait for the chip timeout");

        // Reset during valid must truncate it and restart with cleared keys.
        @(negedge clk);
        resetn = 1'b0;
        key_state = {KEY_NUM{1'b1}};
        repeat (4) @(negedge clk);
        resetn = 1'b1;
        wait (frames == 6);
        wait (!touch_valid);
        #2;
        if (pulses != 5)
            fail("not all uninterrupted valid pulses were verified");
        done = 1'b1;
        $display("PASS [%0d keys, active_low=%0d]: %0d frames, %0d full valid pulses; %0d us frame period; timeout rearm",
                 KEY_NUM, ACTIVE_LOW, frames, pulses, FRAME_TICKS / 50);
    end
endmodule
