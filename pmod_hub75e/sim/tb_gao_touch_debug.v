`timescale 1ns/1ps

// Self-checking bridge test. +dump writes a compact slow-clock waveform.
module tb_gao_touch_debug;
    reg clk = 1'b0;
    always #10 clk = ~clk; // 50 MHz
    reg resetn = 1'b0;
    reg [5:0] clkn = 6'd0;
    always @(posedge clk) begin
        if (!resetn)
            clkn <= 6'd0;
        else
            clkn <= clkn + 1'b1;
    end
    wire gao_clock = clkn[3]; // 3.125 MHz, as in TOP

    reg [15:0] touch_keys = 16'h0000;
    reg [15:0] keys_stable = 16'h0000;
    reg image_requested = 1'b0;
    reg [3:0] brightness_requested = 4'd8;
    reg image_active = 1'b0;
    reg [3:0] brightness_active = 4'd8;
    reg touch_valid = 1'b0;
    reg raw_key_press = 1'b0; // Deliberately narrow original UI pulse.
    wire [43:0] gao_probe;

    gao_touch_debug dut (
        .clk(clk), .resetn(resetn), .touch_keys(touch_keys),
        .keys_stable(keys_stable), .image_requested(image_requested),
        .brightness_requested(brightness_requested),
        .image_active(image_active), .brightness_active(brightness_active),
        .touch_valid(touch_valid), .gao_probe(gao_probe)
    );

    integer failures = 0;
    integer event_rises = 0;
    integer sampled_events = 0;
    integer sampled_raw_press = 0;
    integer previous_event_rises;
    integer previous_sampled_events;
    integer previous_sampled_raw_press;
    reg event_started = 1'b0;
    time event_start_time;
    time last_snapshot_time = 0;
    reg [43:0] previous_probe;

    // Timing is checked at actual slow-clock edges, not from the counter.
    always @(gao_probe) begin
        last_snapshot_time = $time;
        if (resetn && ($time != 0) && clk !== 1'b0) begin
            $display("FAIL: snapshot changed outside a master falling edge");
            failures = failures + 1;
        end
    end

    always @(posedge gao_clock) begin
        if (resetn) begin
            if (($time - last_snapshot_time) < 10) begin
                $display("FAIL: snapshot lacks half-cycle setup before GAO sample");
                failures = failures + 1;
            end
            if (gao_probe[43])
                sampled_events = sampled_events + 1;
            if (raw_key_press)
                sampled_raw_press = sampled_raw_press + 1;
        end
    end

    always @(posedge gao_probe[43]) begin
        if (resetn) begin
            event_rises = event_rises + 1;
            event_start_time = $time;
            event_started = 1'b1;
        end
    end

    always @(negedge gao_probe[43]) begin
        if (resetn && event_started &&
            (($time - event_start_time) != 20000)) begin
            $display("FAIL: event width %0t, expected 20 us",
                     $time - event_start_time);
            failures = failures + 1;
        end
        event_started = 1'b0;
    end

    task check_payload;
        input expected_event;
        input [15:0] expected_raw;
        input [15:0] expected_stable;
        input expected_image_requested;
        input [3:0] expected_brightness_requested;
        input expected_image_active;
        input [3:0] expected_brightness_active;
        input expected_valid;
        reg [43:0] expected;
        begin
            expected = {expected_event, expected_valid,
                        expected_brightness_active, expected_image_active,
                        expected_brightness_requested, expected_image_requested,
                        expected_stable, expected_raw};
            if (gao_probe !== expected) begin
                $display("FAIL: probe=%011h, expected=%011h, t=%0t",
                         gao_probe, expected, $time);
                failures = failures + 1;
            end
        end
    endtask

    task check_captured_event;
        begin
            if (event_rises != previous_event_rises + 1 ||
                sampled_events <= previous_sampled_events) begin
                $display("FAIL: expected one new event captured by slow GAO");
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("sim/gao_touch_debug.vcd");
            // Omit the 50 MHz clock/counter; retain only user-facing signals.
            $dumpvars(0, gao_clock, gao_probe, touch_keys, keys_stable,
                      touch_valid, raw_key_press, image_requested,
                      brightness_requested, image_active, brightness_active);
        end

        #1;
        check_payload(0, 16'h0000, 16'h0000, 0, 8, 0, 8, 0);
        repeat (4) @(negedge clk);
        #1;
        resetn = 1'b1;

        // Every payload field is distinct; raw changes cannot trigger.
        @(posedge clk);
        #1;
        previous_probe = gao_probe;
        touch_keys = 16'h5aa5;
        image_requested = 1;
        brightness_requested = 3;
        image_active = 0;
        brightness_active = 6;
        touch_valid = 1;
        #1;
        if (gao_probe !== previous_probe) begin
            $display("FAIL: probe changed before the falling-edge snapshot");
            failures = failures + 1;
        end
        @(negedge clk);
        #1;
        check_payload(0, 16'h5aa5, 16'h0000, 1, 3, 0, 6, 1);
        #1000;
        if (event_rises != 0 || sampled_events != 0) begin
            $display("FAIL: raw keys/UI changes incorrectly triggered an event");
            failures = failures + 1;
        end

        // Put a 20 ns key_press between slow samples: GAO must miss it,
        // while the stable snapshot and 20 us event must still be captured.
        @(negedge gao_clock);
        @(posedge clk);
        #1;
        previous_event_rises = event_rises;
        previous_sampled_events = sampled_events;
        previous_sampled_raw_press = sampled_raw_press;
        touch_keys = 16'h0001;
        keys_stable = 16'h0001;
        image_requested = 1;
        brightness_requested = 7;
        image_active = 0;
        brightness_active = 8;
        touch_valid = 0;
        raw_key_press = 1;
        @(negedge clk);
        #1;
        check_payload(1, 16'h0001, 16'h0001, 1, 7, 0, 8, 0);
        @(posedge clk);
        #1;
        raw_key_press = 0;
        #1000;
        check_captured_event;
        if (sampled_raw_press != previous_sampled_raw_press) begin
            $display("FAIL: test pulse did not fall between GAO samples");
            failures = failures + 1;
        end

        // Active display settings can change later, without another event.
        @(posedge clk);
        #1;
        image_active = 1;
        brightness_active = 7;
        @(negedge clk);
        #1;
        check_payload(1, 16'h0001, 16'h0001, 1, 7, 1, 7, 0);
        #40000;
        check_payload(0, 16'h0001, 16'h0001, 1, 7, 1, 7, 0);
        if (event_rises != previous_event_rises + 1) begin
            $display("FAIL: long hold retriggered the event");
            failures = failures + 1;
        end

        // Releasing is observable even though requested UI settings stay.
        @(posedge clk);
        #1;
        previous_event_rises = event_rises;
        previous_sampled_events = sampled_events;
        touch_keys = 0;
        keys_stable = 0;
        @(negedge clk);
        #1;
        check_payload(1, 16'h0000, 16'h0000, 1, 7, 1, 7, 0);
        #24000;
        check_captured_event;
        check_payload(0, 16'h0000, 16'h0000, 1, 7, 1, 7, 0);

        // K16 at maximum brightness is still an observable key event.
        @(posedge clk);
        #1;
        previous_event_rises = event_rises;
        previous_sampled_events = sampled_events;
        touch_keys = 16'h8000;
        keys_stable = 16'h8000;
        brightness_requested = 8;
        brightness_active = 8;
        @(negedge clk);
        #1;
        check_payload(1, 16'h8000, 16'h8000, 1, 8, 1, 8, 0);
        #24000;
        check_captured_event;

        // Assert reset between falling edges while an event is active;
        // outputs reset immediately, even as the divided clock stops.
        @(posedge clk);
        #1;
        keys_stable = 16'h4000;
        touch_keys = 16'h4000;
        @(negedge clk);
        #1;
        check_payload(1, 16'h4000, 16'h4000, 1, 8, 1, 8, 0);
        @(posedge clk);
        #3;
        resetn = 0;
        #1;
        check_payload(0, 16'h0000, 16'h0000, 0, 8, 0, 8, 0);
        touch_keys = 0;
        keys_stable = 0;
        image_requested = 0;
        brightness_requested = 8;
        image_active = 0;
        brightness_active = 8;
        repeat (4) @(negedge clk);
        #1;
        check_payload(0, 16'h0000, 16'h0000, 0, 8, 0, 8, 0);
        resetn = 1;
        @(posedge clk);
        #1;
        previous_event_rises = event_rises;
        previous_sampled_events = sampled_events;
        touch_keys = 16'h0002;
        keys_stable = 16'h0002;
        @(negedge clk);
        #1;
        check_payload(1, 16'h0002, 16'h0002, 0, 8, 0, 8, 0);
        #24000;
        check_captured_event;

        if (failures != 0)
            $fatal(1, "tb_gao_touch_debug: %0d failure(s)", failures);
        $display("PASS tb_gao_touch_debug: layout, half-cycle setup, 20 us events,");
        $display("     raw-glitch rejection, press/release/hold, reset, slow sampling");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "tb_gao_touch_debug timeout");
    end
endmodule
