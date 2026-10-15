`timescale 1ns/1ps

// Run from ttp229_gpio:
//   iverilog -g2012 -s tb_ttp229_gpio -o sim/build/tb_ttp229_gpio.vvp src/ttp229_gpio_top.v sim/tb_ttp229_gpio.v
//   vvp sim/build/tb_ttp229_gpio.vvp
// Add +dump for sim/build/tb_ttp229_gpio.vcd.
// A 1 MHz clock keeps all millisecond timings real while reducing runtime.
// The main DUT shortens startup to 3 ms; a second DUT keeps every default
// except CLK_FREQ and covers 600 ms startup and a complete 1 Hz heartbeat.
module tb_ttp229_gpio;
    reg clk = 1'b0;
    always #500 clk = ~clk;
    reg [7:0] pads = 8'hff;
    reg fast_done = 1'b0;
    wire slow_done;
    ttp229_gpio_top #(.CLK_FREQ(1_000_000), .STARTUP_MS(3)) dut (
        .CLK_IN(clk), .touch_out(pads), .S2(1'b0), .touch_sdo(1'b1), .touch_scl()
    );
    // The optional polarity parameter must normalize electrically inverted
    // inputs to the same keys, without changing the default active-high mode.
    ttp229_gpio_top #(.CLK_FREQ(1_000_000), .STARTUP_MS(3), .ACTIVE_LOW(1)) dut_low (
        .CLK_IN(clk), .touch_out(~pads), .S2(1'b0), .touch_sdo(1'b1), .touch_scl()
    );
    ttp229_gpio_default_checker check_default (.clk(clk), .done(slow_done));

    task fail;
        input [8*140-1:0] reason;
        begin
            $fatal(1, "FAIL [eight-key GPIO, t=%0t]: %0s", $time, reason);
        end
    endtask

    integer cycle = 0;
    integer first_ms_tick = -1;
    integer last_ms_tick = -1;
    integer last_change_cycle = -2000;
    integer confirmed_changes = 0;
    reg sample_now;
    reg previous_ms_tick = 1'b0;
    reg [7:0] expected_meta = 8'd0;
    reg [7:0] expected_sync = 8'd0;
    reg [7:0] previous_stable = 8'd0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        // ms_tick is registered. The consumer acts on its PRE-edge value.
        sample_now = dut.ms_tick && dut.ready;
        if (!dut.power_resetn) begin
            expected_meta = 8'd0;
            expected_sync = 8'd0;
        end else begin
            expected_sync = expected_meta;
            expected_meta = pads;
        end
        #1;
        if (dut.power_resetn !== (cycle >= 63))
            fail("automatic power reset must release on clock 63");
        if (dut.keys_raw !== expected_sync)
            fail("active-high input synchronization must take exactly two master clocks");
        if (dut.ready !== (cycle >= 3064))
            fail("3 ms startup must finish after three full registered millisecond ticks");
        if (cycle < 3064 && dut.keys_stable !== 8'd0)
            fail("startup input activity must not confirm any key");
        if (dut_low.keys_raw !== dut.keys_raw ||
            dut_low.keys_stable !== dut.keys_stable ||
            dut_low.ready !== dut.ready)
            fail("active-low override did not normalize to the active-high result");
        // Check divider progression during reset too: CLK_IN/256 cannot
        // complete a transition in only 63 reset clocks, but must advance.
        if (dut.gao_div !== cycle[7:0] ||
            dut.gao_clock !== (((cycle - 1) % 256) >= 128) ||
            dut_low.gao_clock !== dut.gao_clock)
            fail("GAO divider must free-run at CLK_IN/256 through reset/startup");
        if (dut.heartbeat !== ((cycle >= 64) ? (((cycle - 64) / 500000) % 2) : 0))
            fail("heartbeat must toggle after every 500 registered ms ticks");
        if (dut.ms_tick && previous_ms_tick)
            fail("1 ms sample enable must be a one-master-clock pulse");
        if (dut.ms_tick) begin
            if (first_ms_tick < 0) begin
                first_ms_tick = cycle;
                if (cycle != 1063)
                    fail("first ms tick must follow 1000 released-reset clocks");
            end else if (cycle - last_ms_tick != 1000)
                fail("millisecond sample cadence must remain exactly 1000 clocks");
            last_ms_tick = cycle;
        end
        if (dut.keys_stable !== previous_stable) begin
            if (!sample_now)
                fail("confirmed keys changed outside a 1 ms sample enable");
            last_change_cycle = cycle;
            confirmed_changes = confirmed_changes + 1;
        end
        if (dut.key_event !== ((cycle - last_change_cycle) < 1000))
            fail("confirmed-key event must remain asserted for exactly 1 ms");
        if (dut_low.key_event !== dut.key_event)
            fail("polarity override changed confirmed-key event behavior");
        previous_ms_tick = dut.ms_tick;
        previous_stable = dut.keys_stable;
    end

    reg [58:0] expected_probe, expected_low_probe;
    always @(negedge clk) begin
        // Delay avoids a race with test stimuli that also change at negedge.
        #1;
        expected_probe = {
            dut.mode_state, dut.serial_bit_cnt, dut.serial_state, dut.serial_valid,
            1'b1, dut.touch_scl, 1'b0, dut.mode_16,
            dut.gao_clock, dut.key_event, dut.heartbeat, dut.ready, dut.power_resetn,
            dut.keys_stable, dut.keys_raw, pads
        };
        expected_low_probe = {
            dut_low.mode_state, dut_low.serial_bit_cnt, dut_low.serial_state, dut_low.serial_valid,
            1'b1, dut_low.touch_scl, 1'b0, dut_low.mode_16,
            dut_low.gao_clock, dut_low.key_event, dut_low.heartbeat, dut_low.ready, dut_low.power_resetn,
            dut_low.keys_stable, dut_low.keys_raw, ~pads
        };
        if (dut.gao_probe !== expected_probe || dut_low.gao_probe !== expected_low_probe)
            fail("GAO snapshot fields or falling-edge capture are incorrect");
    end

    task next_sample;
        begin
            @(posedge clk);
            while (!dut.ms_tick) @(posedge clk);
            #2;
        end
    endtask

    task expect_samples;
        input integer count;
        input [7:0] expected_keys;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                next_sample;
                if (dut.keys_stable !== expected_keys) begin
                    $display("Expected=%h observed=%h sample=%0d/%0d", expected_keys, dut.keys_stable, n + 1, count);
                    fail("key confirmation occurred before/after the required sample boundary");
                end
            end
        end
    endtask

    task drive;
        input [7:0] keys;
        begin
            @(negedge clk);
            #10; // Change after the snapshot edge, between master rising edges.
            pads = keys;
        end
    endtask

    task confirm;
        input [7:0] new_keys;
        input [7:0] old_keys;
        begin
            drive(new_keys);
            expect_samples(19, old_keys);
            expect_samples(1, new_keys);
        end
    endtask

    integer key;
    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("sim/build/tb_ttp229_gpio.vcd");
            $dumpvars(0, tb_ttp229_gpio);
        end
        wait (dut.ready);
        #2;
        if (dut.keys_stable !== 8'd0)
            fail("held-high startup inputs incorrectly became confirmed keys");
        drive(8'd0);
        expect_samples(1, 8'd0);
        for (key = 0; key < 8; key = key + 1) begin
            confirm(8'h01 << key, 8'd0);
            confirm(8'd0, 8'h01 << key);
        end
        confirm(8'hff, 8'd0); // All eight direct inputs remain independent.
        confirm(8'd0, 8'hff);

        // Offset two inputs by ten samples. A shared counter or candidate
        // bitmap would delay K1 when K2 changes, and fails these boundaries.
        drive(8'h01);
        expect_samples(10, 8'h00);
        drive(8'h03);
        expect_samples(9, 8'h00);
        expect_samples(1, 8'h01);
        expect_samples(9, 8'h01);
        expect_samples(1, 8'h03);
        confirm(8'h02, 8'h03); // Releasing K1 must leave K2 pressed.
        confirm(8'h00, 8'h02);

        // Nineteen disagreeing samples are insufficient. One matching
        // sample cancels the entire unfinished press/release count.
        drive(8'h04);
        expect_samples(19, 8'h00);
        drive(8'h00);
        expect_samples(1, 8'h00);
        confirm(8'h04, 8'h00);
        drive(8'h00);
        expect_samples(19, 8'h04);
        drive(8'h04);
        expect_samples(1, 8'h04);
        confirm(8'h00, 8'h04);

        // Electrical pulses entirely between sample instants must appear
        // in synchronized raw keys, but never in the confirmed bitmap.
        drive(8'h81);
        repeat (2) @(posedge clk);
        #2;
        if (dut.keys_raw !== 8'h81 || dut.keys_stable !== 8'h00)
            fail("short electrical pulse did not appear only in raw keys");
        repeat (100) @(posedge clk); // About 100 us, below one sample period.
        drive(8'h00);
        expect_samples(25, 8'h00);
        fast_done = 1'b1;
        $display("PASS [eight-key GPIO]: all eight bit positions, both polarities, 20-sample press/release, simultaneous/independent keys, 19 ms bounce and short pulse; %0d confirmed changes", confirmed_changes);
        wait (slow_done);
        $display("PASS: direct eight-key GPIO reset, startup, synchronization, debounce, GAO clock/snapshot/event and complete 1 Hz heartbeat");
        $finish;
    end
    initial begin
        #1_050_000_000;
        $fatal(1, "FAIL: direct GPIO test timed out");
    end
endmodule

module ttp229_gpio_default_checker (input wire clk, output reg done = 1'b0);
    reg [7:0] pads = 8'h81;
    ttp229_gpio_top #(.CLK_FREQ(1_000_000)) dut (
        .CLK_IN(clk), .touch_out(pads), .S2(1'b0), .touch_sdo(1'b1), .touch_scl()
    );
    integer cycle = 0;
    integer heartbeat_changes = 0;
    reg previous_heartbeat = 1'b0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        #1;
        if (dut.power_resetn !== (cycle >= 63))
            $fatal(1, "FAIL: default DUT automatic reset boundary");
        if (dut.ready !== (cycle >= 600064))
            $fatal(1, "FAIL: default 600 ms startup boundary, cycle=%0d", cycle);
        if (cycle < 600064 && (dut.keys_stable !== 8'd0 || dut.key_event !== 1'b0))
            $fatal(1, "FAIL: held-high inputs were accepted during default startup");
        if (dut.heartbeat !== ((cycle >= 64) ? (((cycle - 64) / 500000) % 2) : 0))
            $fatal(1, "FAIL: default heartbeat boundary, cycle=%0d", cycle);
        if (dut.heartbeat !== previous_heartbeat)
            heartbeat_changes = heartbeat_changes + 1;
        previous_heartbeat = dut.heartbeat;
    end
    task next_sample;
        begin
            @(posedge clk);
            while (!dut.ms_tick) @(posedge clk);
            #2;
        end
    endtask
    integer n;
    initial begin
        wait (dut.ready);
        #2;
        for (n = 1; n <= 20; n = n + 1) begin
            next_sample;
            if (dut.keys_stable !== ((n == 20) ? 8'h81 : 8'h00))
                $fatal(1, "FAIL: default startup did not restart the 20 ms confirmation window");
        end
        @(negedge clk);
        #10;
        pads = 8'd0;
        for (n = 1; n <= 20; n = n + 1) begin
            next_sample;
            if (dut.keys_stable !== ((n == 20) ? 8'h00 : 8'h81))
                $fatal(1, "FAIL: default release debounce");
        end
        wait (cycle >= 1000064);
        #2;
        if (heartbeat_changes != 2 || dut.heartbeat !== 1'b0)
            $fatal(1, "FAIL: heartbeat did not complete its full 1 Hz period");
        done = 1'b1;
        $display("PASS [defaults]: 600 ms startup ignored held inputs, new 20 ms confirmation window, heartbeat edges at 500 ms and 1000 ms");
    end
endmodule
