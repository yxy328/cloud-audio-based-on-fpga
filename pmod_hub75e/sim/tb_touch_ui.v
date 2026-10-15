`timescale 1ns/1ps

module tb_touch_ui;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg touch_valid = 1'b0;
    reg [15:0] touch_keys = 16'h0000;
    wire [15:0] keys_stable;
    wire [15:0] key_press;
    wire image_sel;
    wire [3:0] brightness;

    // A separate one-frame instance verifies the smallest legal setting.
    wire [15:0] keys_one;
    wire [15:0] press_one;
    wire image_one;
    wire [3:0] brightness_one;

    integer failures = 0;
    integer events = 0;
    integer one_events = 0;
    integer i;
    reg [15:0] last_event = 16'h0000;
    reg [15:0] previous_pulse = 16'h0000;

    touch_ui #(.STABLE_FRAMES(3)) dut (
        .clk(clk), .resetn(resetn), .touch_valid(touch_valid),
        .touch_keys(touch_keys), .keys_stable(keys_stable),
        .key_press(key_press), .image_sel(image_sel),
        .brightness(brightness)
    );

    touch_ui #(.STABLE_FRAMES(1)) dut_one (
        .clk(clk), .resetn(resetn), .touch_valid(touch_valid),
        .touch_keys(touch_keys), .keys_stable(keys_one),
        .key_press(press_one), .image_sel(image_one),
        .brightness(brightness_one)
    );

    // Observe outputs after nonblocking assignments, including pulse width.
    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            previous_pulse = 16'h0000;
        end
        else begin
            if (key_press != 16'h0000) begin
                events = events + 1;
                last_event = key_press;
                if (previous_pulse != 16'h0000) begin
                    $display("FAIL: key_press lasted more than one clock");
                    failures = failures + 1;
                end
            end
            if (press_one != 16'h0000)
                one_events = one_events + 1;
            previous_pulse = key_press;
        end
    end

    task check_state;
        input [15:0] expected_keys;
        input expected_image;
        input [3:0] expected_brightness;
        begin
            if (keys_stable !== expected_keys ||
                image_sel !== expected_image ||
                brightness !== expected_brightness) begin
                $display("FAIL t=%0t keys=%h/%h image=%b/%b brightness=%0d/%0d",
                         $time, keys_stable, expected_keys, image_sel,
                         expected_image, brightness, expected_brightness);
                failures = failures + 1;
            end
        end
    endtask

    task send_frame;
        input [15:0] keys;
        input integer valid_cycles;
        input [15:0] expected_press;
        integer events_before;
        integer high_cycle;
        begin
            events_before = events;
            @(negedge clk);
            touch_keys = keys;
            touch_valid = 1'b1;
            for (high_cycle = 0; high_cycle < valid_cycles; high_cycle = high_cycle + 1) begin
                @(posedge clk);
                #2;
                if (high_cycle == 0 && key_press !== expected_press) begin
                    $display("FAIL: expected press=%h on frame edge, got=%h",
                             expected_press, key_press);
                    failures = failures + 1;
                end
            end
            @(negedge clk);
            touch_valid = 1'b0;
            @(posedge clk);
            #2;
            if ((expected_press == 16'h0000 && events != events_before) ||
                (expected_press != 16'h0000 &&
                 (events != events_before + 1 || last_event !== expected_press))) begin
                $display("FAIL t=%0t event keys=%h expected=%h count=%0d before=%0d last=%h",
                         $time, keys, expected_press, events,
                         events_before, last_event);
                failures = failures + 1;
            end
            if (key_press !== 16'h0000) begin
                $display("FAIL: press pulse did not clear");
                failures = failures + 1;
            end
        end
    endtask

    task release_keys;
        begin
            send_frame(16'h0000, 2, 16'h0000);
            send_frame(16'h0000, 2, 16'h0000);
            send_frame(16'h0000, 2, 16'h0000);
        end
    endtask

    task press_keys;
        input [15:0] keys;
        begin
            send_frame(keys, 2, 16'h0000);
            send_frame(keys, 2, 16'h0000);
            send_frame(keys, 2, keys);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #2;
        check_state(16'h0000, 1'b0, 4'd8);
        @(negedge clk);
        resetn = 1'b1;

        // Isolated frames and alternating bounce must never be committed.
        send_frame(16'h0001, 20, 16'h0000);
        check_state(16'h0000, 1'b0, 4'd8);
        if (keys_one !== 16'h0001 || image_one !== 1'b1 || one_events != 1) begin
            $display("FAIL: STABLE_FRAMES=1 or long valid sampling");
            failures = failures + 1;
        end
        send_frame(16'h0000, 2, 16'h0000);
        send_frame(16'h0001, 2, 16'h0000);
        send_frame(16'h0000, 2, 16'h0000);
        send_frame(16'h0001, 2, 16'h0000);
        check_state(16'h0000, 1'b0, 4'd8);
        send_frame(16'h0001, 20, 16'h0000);
        check_state(16'h0000, 1'b0, 4'd8);
        send_frame(16'h0001, 20, 16'h0001);
        check_state(16'h0001, 1'b1, 4'd8);

        // Long hold emits no repeat events.
        repeat (5) send_frame(16'h0001, 20, 16'h0000);
        check_state(16'h0001, 1'b1, 4'd8);

        // Even changing input keys inside the high valid window must not
        // add another sample. Both debounce settings keep the edge value.
        @(negedge clk);
        touch_keys = 16'h0001;
        touch_valid = 1'b1;
        repeat (3) @(negedge clk);
        touch_keys = 16'h0002;
        repeat (20) @(negedge clk);
        touch_valid = 1'b0;
        @(posedge clk);
        #2;
        check_state(16'h0001, 1'b1, 4'd8);
        if (keys_one !== 16'h0001 || image_one !== 1'b1) begin
            $display("FAIL: resampled keys during a high valid window");
            failures = failures + 1;
        end

        // Whole-frame debounce restarts if any other key changes.
        send_frame(16'h0003, 2, 16'h0000);
        send_frame(16'h0001, 2, 16'h0000);
        send_frame(16'h0003, 2, 16'h0000);
        send_frame(16'h0003, 2, 16'h0000);
        check_state(16'h0001, 1'b1, 4'd8);
        send_frame(16'h0003, 2, 16'h0002);
        check_state(16'h0003, 1'b0, 4'd8);

        // Release also takes three frames. A bounced release must not
        // manufacture another press event for the still-held key.
        send_frame(16'h0000, 2, 16'h0000);
        send_frame(16'h0003, 2, 16'h0000);
        check_state(16'h0003, 1'b0, 4'd8);
        send_frame(16'h0000, 2, 16'h0000);
        send_frame(16'h0000, 2, 16'h0000);
        check_state(16'h0003, 1'b0, 4'd8);
        send_frame(16'h0000, 2, 16'h0000);
        check_state(16'h0000, 1'b0, 4'd8);
        press_keys(16'h0001);
        check_state(16'h0001, 1'b1, 4'd8);
        release_keys;
        press_keys(16'h0003);
        check_state(16'h0003, 1'b0, 4'd8);
        release_keys;

        // Decrease to one, exercise the lower clamp, and verify no repeat.
        for (i = 0; i < 9; i = i + 1) begin
            press_keys(16'h4000);
            if (i < 7)
                check_state(16'h4000, 1'b0, 8 - i - 1);
            else
                check_state(16'h4000, 1'b0, 4'd1);
            repeat (2) send_frame(16'h4000, 20, 16'h0000);
            release_keys;
        end

        // Simultaneous +/- cancel at the lower limit and a middle level.
        press_keys(16'hc000);
        check_state(16'hc000, 1'b0, 4'd1);
        release_keys;
        press_keys(16'h8000);
        check_state(16'h8000, 1'b0, 4'd2);
        release_keys;
        press_keys(16'hc000);
        check_state(16'hc000, 1'b0, 4'd2);
        release_keys;

        for (i = 0; i < 8; i = i + 1) begin
            press_keys(16'h8000);
            if (i < 6)
                check_state(16'h8000, 1'b0, 3 + i);
            else
                check_state(16'h8000, 1'b0, 4'd8);
            release_keys;
        end

        // An unrelated key can be accepted without changing UI controls.
        press_keys(16'h0080);
        check_state(16'h0080, 1'b0, 4'd8);
        release_keys;

        // Reset clears partially accumulated debounce and all UI state.
        press_keys(16'h4001);
        check_state(16'h4001, 1'b1, 4'd7);
        send_frame(16'h0002, 2, 16'h0000);
        send_frame(16'h0002, 2, 16'h0000);
        @(negedge clk);
        resetn = 1'b0;
        touch_valid = 1'b0;
        repeat (2) @(posedge clk);
        #2;
        check_state(16'h0000, 1'b0, 4'd8);
        if (key_press !== 16'h0000 || keys_one !== 16'h0000 ||
            image_one !== 1'b0 || brightness_one !== 4'd8) begin
            $display("FAIL: reset outputs");
            failures = failures + 1;
        end
        @(negedge clk);
        resetn = 1'b1;
        send_frame(16'h0002, 2, 16'h0000);
        send_frame(16'h0002, 2, 16'h0000);
        check_state(16'h0000, 1'b0, 4'd8);
        send_frame(16'h0002, 2, 16'h0002);
        check_state(16'h0002, 1'b0, 4'd8);

        if (failures == 0)
            $display("PASS tb_touch_ui: debounce, valid edge, press/release, UI controls and reset");
        else
            $display("FAIL tb_touch_ui: %0d errors", failures);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL tb_touch_ui: timeout");
        $finish;
    end
endmodule
