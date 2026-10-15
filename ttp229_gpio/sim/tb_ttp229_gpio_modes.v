`timescale 1ns/1ps
module tb_ttp229_gpio_modes;
    reg clk = 0, s2 = 0;
    reg [7:0] gpio_pads = 8'h81;
    reg [15:0] serial_pads = 16'h8101;
    reg sdo = 1;
    wire scl;
    always #500 clk = ~clk;
    ttp229_gpio_top #(.CLK_FREQ(1_000_000), .STARTUP_MS(3), .S2_DEBOUNCE_MS(0)) dut (
        .CLK_IN(clk), .touch_out(gpio_pads), .S2(s2),
        .touch_sdo(sdo), .touch_scl(scl)
    );
    // Verify the opposite serial polarity through the same top-level path.
    wire high_scl;
    ttp229_gpio_top #(.CLK_FREQ(1_000_000), .STARTUP_MS(3), .S2_DEBOUNCE_MS(0), .SERIAL_ACTIVE_LOW(0)) high (
        .CLK_IN(clk), .touch_out(gpio_pads), .S2(s2),
        .touch_sdo(~sdo), .touch_scl(high_scl)
    );
    integer index = 0, edges = 0, total_edges = 0;
    reg [15:0] frame_pads;
    time last_edge = 0;
    always @(scl) begin
        if (scl === 0 || scl === 1) begin
            if ($time - last_edge > 2_000_000) begin
                index = 0; edges = 0; frame_pads = serial_pads;
            end
            last_edge = $time;
            if (!scl) begin
                total_edges = total_edges + 1;
                edges = edges + 1;
                if (index < 16) begin
                    sdo <= #100 ~frame_pads[index];
                    index = index + 1;
                end
            end
        end
    end
    always @(posedge dut.serial_valid) begin
        #1;
        if (edges != 16 || dut.serial_keys !== frame_pads)
            $fatal(1, "GPIO serial frame has wrong length/order");
    end
    always @(negedge clk) begin
        #1;
        if (dut.power_resetn && (high_scl !== ~scl || high.keys_stable !== dut.keys_stable || high.keys_raw !== dut.keys_raw))
            $fatal(1, "GPIO serial active-high/low normalization differs");
        // The serial FSM consumes mode_changed at the next master edge.
        if (!dut.mode_16 && !dut.mode_changed && (dut.keys_raw[15:8] !== 0 || scl !== 1))
            $fatal(1, "GPIO 8-key mode has upper keys or serial clocks");
    end
    task press_s2;
        input expected_mode;
        begin
            @(negedge clk); s2 = 1;
            wait (dut.mode_changed);
            repeat (2) @(negedge clk);
            if (dut.mode_16 !== expected_mode || dut.keys_stable !== 0)
                $fatal(1, "GPIO mode change retained old confirmed keys");
            repeat (20) @(negedge clk);
            if (dut.mode_16 !== expected_mode) $fatal(1, "GPIO long press repeated toggle");
            s2 = 0;
            repeat (5) @(negedge clk);
            if (dut.mode_16 !== expected_mode) $fatal(1, "GPIO release lost retained mode");
        end
    endtask
    integer old_edges;
    initial begin
        wait (dut.keys_stable == 16'h0081);
        if (total_edges != 0) $fatal(1, "Serial clocks appeared in startup GPIO mode");
        press_s2(1);
        wait (dut.keys_stable == 16'h8101);
        @(negedge clk); gpio_pads = 8'hff;
        #25_000_000;
        if (dut.keys_stable !== 16'h8101) $fatal(1, "OUT pins contaminated 16-key serial mode");
        @(negedge clk); serial_pads = 0;
        wait (dut.keys_stable == 0);
        @(negedge clk); serial_pads = 16'hffff;
        wait (dut.keys_stable == 16'hffff);
        wait (dut.serial_state == 1 && dut.serial_bit_cnt == 5);
        @(negedge clk); gpio_pads = 8'h02;
        press_s2(0);
        old_edges = total_edges;
        wait (dut.keys_stable == 16'h0002);
        #10_000_000;
        if (total_edges != old_edges) $fatal(1, "GPIO mode did not stop serial clock");
        serial_pads = 16'h8001;
        press_s2(1);
        wait (dut.keys_stable == 16'h8001);
        $display("PASS: GPIO top toggles OUT1..8/16-key serial, retains mode on release, clears stale upper keys, ignores unused source and restarts aligned; both polarities");
        $finish;
    end
    initial begin
        #200_000_000;
        $fatal(1, "GPIO mode integration timed out");
    end
endmodule
