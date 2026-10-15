`timescale 1ns/1ps
module tb_ttp229_gpio_input;
    reg clk = 0, resetn = 0, enable = 1;
    reg [7:0] pads = 8'hff;
    always #500 clk = ~clk;
    wire [7:0] raw, stable, low_raw, low_stable;
    wire valid, ready, low_valid, low_ready;
    wire slow_ready, slow_valid;
    wire [7:0] slow_stable;
    reg fast_done = 0;
    ttp229_gpio_input #(.CLK_FREQ(1_000_000), .STARTUP_US(3000)) dut (
        .clk(clk), .resetn(resetn), .enable(enable), .touch_out(pads),
        .keys_raw(raw), .keys_stable(stable), .sample_valid(valid), .ready(ready)
    );
    ttp229_gpio_input #(.CLK_FREQ(1_000_000), .STARTUP_US(3000), .ACTIVE_LOW(1)) low (
        .clk(clk), .resetn(resetn), .enable(enable), .touch_out(~pads),
        .keys_raw(low_raw), .keys_stable(low_stable), .sample_valid(low_valid), .ready(low_ready)
    );
    // Hold input throughout the actual 600ms cold start, even while disabled.
    ttp229_gpio_input #(.CLK_FREQ(1_000_000)) cold (
        .clk(clk), .resetn(resetn), .enable(1'b1), .touch_out(8'h81),
        .keys_raw(), .keys_stable(slow_stable), .sample_valid(slow_valid), .ready(slow_ready)
    );
    always @(negedge clk) begin
        if (resetn && (raw !== low_raw || stable !== low_stable || valid !== low_valid || ready !== low_ready))
            $fatal(1, "GPIO input polarity normalization mismatch");
        if (!slow_ready && (slow_stable !== 0 || slow_valid))
            $fatal(1, "GPIO cold start accepted held keys before 600ms");
    end
    time previous_valid = 0, pulse_time;
    always @(posedge valid) begin
        if (previous_valid && $time - previous_valid != 1_000_000 && enable)
            $fatal(1, "GPIO frame cadence is not 1ms");
        previous_valid = $time; pulse_time = $time;
    end
    always @(negedge valid) begin
        if (resetn && ready && enable && $time - pulse_time != 20_000)
            $fatal(1, "GPIO valid pulse is not 20us");
    end
    task samples;
        input integer count;
        input [7:0] expected;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                @(posedge valid); #2;
                if (stable !== expected) $fatal(1, "GPIO debounce expected %h observed %h sample %0d",expected,stable,n);
            end
        end
    endtask
    task drive;
        input [7:0] new_pads;
        begin
            @(negedge valid); @(negedge clk); pads = new_pads;
        end
    endtask
    task confirm;
        input [7:0] new_pads;
        input [7:0] old_pads;
        begin
            drive(new_pads); samples(19,old_pads); samples(1,new_pads);
        end
    endtask
    integer key;
    initial begin
        repeat (5) @(negedge clk); resetn = 1;
        wait (ready); #2;
        if (stable !== 0) $fatal(1, "Held GPIO startup keys became confirmed");
        pads = 0;
        // Allow the released input to pass two synchronizer stages before
        // a full matching millisecond sample clears the startup candidate.
        samples(2,0);
        for (key = 0; key < 8; key = key + 1) begin
            confirm(8'h01 << key,0);
            confirm(0,8'h01 << key);
        end
        confirm(8'hff,0); confirm(0,8'hff);
        drive(1); samples(10,0);
        drive(3); samples(9,0); samples(1,1); samples(9,1); samples(1,3);
        confirm(0,3);
        drive(4); samples(19,0); drive(0); samples(1,0);
        confirm(4,0);
        @(negedge clk); enable = 0;
        repeat (2) @(negedge clk);
        if (stable !== 0 || valid) $fatal(1, "Disabling GPIO did not clear old keys/frame");
        #5_000_000;
        previous_valid = 0;
        @(negedge clk); enable = 1;
        samples(19,0); samples(1,4);
        fast_done = 1;
        wait (slow_ready);
        #2;
        if ($time < 600_000_000 || slow_stable !== 0) $fatal(1, "600ms startup duration/keys incorrect");
        wait (slow_stable == 8'h81);
        if (!fast_done) $fatal(1, "Fast GPIO checks incomplete");
        $display("PASS: extracted GPIO reader, all OUT1..8 positions, both polarities, 20ms independent debounce, bounce, disable/rearm, 20us frames and 600ms startup");
        $finish;
    end
    initial begin
        #650_000_000; $fatal(1,"GPIO reader test timed out");
    end
endmodule
