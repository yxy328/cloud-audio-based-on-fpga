`timescale 1ns/1ps
module tb_top_modes;
    // Mode/UI integration uses a lightweight ROM. tb_top separately checks
    // actual Gowin ROMs and RGB pixels; those primitives are expensive here.
    reg clk = 0, s2 = 0;
    reg [15:0] pads = 0;
    reg [7:0] gpio_pads = 0;
    reg sdo = 1;
    wire scl;
    always #10 clk = ~clk;
    // Button debounce is independently verified at the default 20ms.
    TOP #(.TTP_STARTUP_US(3000), .S2_DEBOUNCE_MS(0)) dut (
        .CLK_IN(clk), .USER_KEY(1'b0), .S2(s2),
        .touch_scl(scl), .touch_sdo(sdo), .touch_out(gpio_pads)
    );
    integer index = 0, count = 0;
    reg [15:0] frame_pads;
    time last_edge = 0;
    always @(scl) begin
        if (scl === 0 || scl === 1) begin
            if ($time - last_edge > 2_000_000) begin
                index = 0; count = 0; frame_pads = pads;
            end
            last_edge = $time;
            if (!scl) begin
                count = count + 1;
                if (index < 16) begin
                    sdo <= #37 ~frame_pads[index];
                    index = index + 1;
                end
            end
        end
    end
    always @(posedge dut.serial_valid) begin
        #1;
        if (!dut.mode_16 || count != 16 || dut.touch_keys !== frame_pads)
            $fatal(1, "TOP selected wrong frame size/order mode=%0d count=%0d", dut.mode_16, count);
    end
    always @(negedge clk) begin
        if (dut.resetn && !dut.mode_16 && !dut.mode_changed && scl !== 1)
            $fatal(1, "GPIO display mode produced a serial clock");
        if (!dut.mode_16 && dut.touch_keys[15:8] !== 0)
            $fatal(1, "GPIO display mode retained upper serial keys");
    end
    task confirm_gpio;
        input [7:0] new_pads;
        begin
            @(negedge clk); gpio_pads = new_pads;
            wait (dut.keys_stable == {8'd0, new_pads});
            #1;
        end
    endtask
    task confirm;
        input [15:0] new_pads;
        begin
            @(negedge clk); pads = new_pads;
            wait (dut.keys_stable == new_pads);
            #1;
        end
    endtask
    task press_s2;
        input expected_mode;
        begin
            @(negedge clk); s2 = 1;
            wait (dut.mode_changed);
            repeat (2) @(negedge clk);
            if (dut.mode_16 !== expected_mode || dut.keys_stable !== 0 || dut.touch_keys !== 0)
                $fatal(1, "TOP mode switch retained old keys/debounce");
            repeat (20) @(negedge clk);
            if (dut.mode_16 !== expected_mode) $fatal(1, "TOP held S2 repeated toggle");
            s2 = 0;
            repeat (5) @(negedge clk);
            if (dut.mode_16 !== expected_mode) $fatal(1, "TOP released S2 changed retained mode");
        end
    endtask
    initial begin
        wait (dut.touch_valid);
        if (dut.mode_16) $fatal(1, "TOP did not boot in 8-key mode");
        // Serial data is deliberately unrelated while GPIO controls display.
        pads = 16'hffff; sdo = 0;
        confirm_gpio(8'h40);
        if (dut.brightness_requested !== 7) $fatal(1, "8-key K7 did not decrease brightness");
        wait (dut.brightness_active == 7);
        confirm_gpio(0);
        confirm_gpio(8'h80);
        if (dut.brightness_requested !== 8) $fatal(1, "8-key K8 did not increase brightness");
        confirm_gpio(0);
        confirm_gpio(1);
        if (!dut.image_requested) $fatal(1, "8-key K1 did not select S");
        wait (dut.image_active == 1);
        if (count != 0) $fatal(1, "Serial clocks appeared in OUT mode");
        @(negedge clk); pads = 0;
        press_s2(1);
        if (!dut.image_requested || dut.brightness_requested !== 8)
            $fatal(1, "Mode switch lost display settings");
        confirm(16'h4000);
        if (dut.brightness_requested !== 7) $fatal(1, "16-key K15 did not decrease brightness");
        confirm(0);
        confirm(16'h8000);
        if (dut.brightness_requested !== 8) $fatal(1, "16-key K16 did not increase brightness");
        gpio_pads = 8'hff;
        #5_000_000;
        if (dut.keys_stable !== 16'h8000)
            $fatal(1, "OUT pins contaminated serial display mode");
        wait (dut.touch_state == 1 && dut.touch_bit_cnt == 5);
        @(negedge clk); pads = 0; gpio_pads = 0;
        press_s2(0);
        confirm_gpio(2);
        if (dut.image_requested) $fatal(1, "8-key K2 did not select T after switch back");
        wait (dut.image_active == 0);
        $display("PASS: TOP OUT1..8/16-key serial selection, idle SCL in GPIO mode, unused-source isolation, mode clearing, retained S2, display image/brightness commit");
        $finish;
    end
    initial begin
        #260_000_000;
        $fatal(1, "TOP mode integration timed out");
    end
endmodule

module display_rom(output wire [31:0] dout, input wire clk, input wire reset,
                   input wire [10:0] ad, input wire image_sel);
    assign dout = 32'd0;
endmodule
