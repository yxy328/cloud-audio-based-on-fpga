`timescale 1ns/1ps

// End-to-end: real serial input, official Gowin pROM model, actual HUB75
// RGB samples on CK. No force of UI, scan counters, or ROM outputs.
module tb_top;
    // Official Gowin primitives reference this exact global instance name.
    GSR GSR (.GSRI(1'b1));
    reg clk = 0;
    reg user_key = 0; // Dock S1 is active-high; released is low.
    reg s2 = 0;
    reg [7:0] gpio_pads = 0;
    always #10 clk = ~clk;
    wire scl;
    reg sdo = 1;
    wire r1, g1, b1, r2, g2, b2, ck, st, oe;
    wire [4:0] rows;
    wire dbg0, dbg1, dbg2;
    // The full 600 ms startup is tested separately at a 1 MHz master.
    TOP #(.TTP_STARTUP_US(3000), .S2_DEBOUNCE_MS(0), .S2_TOGGLE_MODE(0)) dut (
        .CLK_IN(clk), .USER_KEY(user_key), .S2(s2), .touch_out(gpio_pads),
        .touch_scl(scl), .touch_sdo(sdo),
        .hub_R1(r1), .hub_G1(g1), .hub_B1(b1),
        .hub_R2(r2), .hub_G2(g2), .hub_B2(b2),
        .hub_A(rows[0]), .hub_B(rows[1]), .hub_C(rows[2]),
        .hub_D(rows[3]), .hub_E(rows[4]),
        .hub_CK(ck), .hub_ST(st), .hub_OE(oe),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2)
    );

    // The independently powered chip holds its final data bit after 16
    // reads. Only >2 ms with no SCL edge rearms the next frame; S1/FPGA
    // reset does not reset its serial index. Check the idle timeout when
    // the next falling edge arrives, then snapshot the physical keys.
    reg [15:0] physical_keys = 0;
    reg [15:0] serial_keys = 0;
    integer serial_index = 0;
    time serial_last_edge = 0;
    always @(posedge scl) begin
        serial_last_edge = $time;
    end
    always @(negedge scl) begin
        if (($time - serial_last_edge) > 2_000_000)
            serial_index = 0;
        serial_last_edge = $time;
        if (serial_index == 0)
            serial_keys = physical_keys;
        if (serial_index < 16) begin
            sdo <= #37 ~serial_keys[serial_index];
            serial_index = serial_index + 1;
        end
    end

    reg [31:0] image_t [0:2047];
    reg [31:0] image_s [0:2047];
    integer fd, rc, i;
    reg [1023:0] header;
    initial begin
        fd = $fopen("src/logoT.hex", "r");
        if (!fd) $fatal(1, "Cannot open logoT.hex");
        repeat (3) rc = $fgets(header, fd);
        for (i = 0; i < 2048; i = i + 1) begin
            rc = $fscanf(fd, "%h\n", image_t[i]);
            if (rc != 1) $fatal(1, "Invalid logoT word %0d", i);
        end
        $fclose(fd);
        fd = $fopen("src/logoS.hex", "r");
        if (!fd) $fatal(1, "Cannot open logoS.hex");
        repeat (3) rc = $fgets(header, fd);
        for (i = 0; i < 2048; i = i + 1) begin
            rc = $fscanf(fd, "%h\n", image_s[i]);
            if (rc != 1) $fatal(1, "Invalid logoS word %0d", i);
        end
        $fclose(fd);
    end

    // Scoreboard uses external CK/LAT counts and the source hex assets,
    // rather than the DUT address or DUT scale_color function.
    integer column = 0;
    integer scan_row = 0;
    integer pwm_phase = 0;
    integer pixel_checks = 0;
    integer latch_checks = 0;
    integer address;
    reg [31:0] expected_word;
    reg [5:0] expected_rgb;
    reg row_image;
    reg [3:0] row_brightness;
    always @(negedge dut.resetn) begin
        column = 0;
        scan_row = 0;
        pwm_phase = 0;
    end
    always @(posedge ck) begin
        if (dut.resetn) begin
            if (column == 0) begin
                row_image = dut.image_active;
                row_brightness = dut.brightness_active;
            end
            if (column >= 64 || st !== 0 || dut.threshold !== pwm_phase[4:0])
                $fatal(1, "Invalid shift/phase: row=%0d col=%0d phase=%0d/%0d",
                       scan_row, column, dut.threshold, pwm_phase);
            if (dut.image_active !== row_image || dut.brightness_active !== row_brightness)
                $fatal(1, "Display controls changed during row shifting");
            address = scan_row * 64 + column;
            expected_word = row_image ? image_s[address] : image_t[address];
            expected_rgb[5] = ((expected_word[30:26] * row_brightness) / 8) > pwm_phase;
            expected_rgb[4] = ((expected_word[20:16] * row_brightness) / 8) > pwm_phase;
            expected_rgb[3] = ((expected_word[25:21] * row_brightness) / 8) > pwm_phase;
            expected_rgb[2] = ((expected_word[14:10] * row_brightness) / 8) > pwm_phase;
            expected_rgb[1] = ((expected_word[ 4: 0] * row_brightness) / 8) > pwm_phase;
            expected_rgb[0] = ((expected_word[ 9: 5] * row_brightness) / 8) > pwm_phase;
            if ({r1,g1,b1,r2,g2,b2} !== expected_rgb)
                $fatal(1, "RGB mismatch: row=%0d col=%0d image=%b level=%0d phase=%0d got=%b expected=%b",
                       scan_row, column, row_image, row_brightness, pwm_phase,
                       {r1,g1,b1,r2,g2,b2}, expected_rgb);
            column = column + 1;
            pixel_checks = pixel_checks + 1;
        end
    end
    always @(posedge st) begin
        if (dut.resetn) begin
            if (column != 64 || rows !== scan_row[4:0] || oe !== 1)
                $fatal(1, "Bad row latch: col=%0d row=%0d/%0d OE=%b", column, rows, scan_row, oe);
            column = 0;
            latch_checks = latch_checks + 1;
            if (scan_row == 31) begin
                scan_row = 0;
                pwm_phase = (pwm_phase + 1) % 32;
            end
            else
                scan_row = scan_row + 1;
        end
    end

    reg old_image, was_boundary;
    reg was_reset;
    reg [3:0] old_brightness;
    always @(posedge clk) begin
        old_image = dut.image_active;
        old_brightness = dut.brightness_active;
        was_boundary = dut.pwm_cycle_end;
        was_reset = !dut.resetn;
        #1;
        if (was_reset && dut.presetn && user_key === 1'b1) begin
            if (dut.resetn !== 0 || ck !== 0 || st !== 0 || oe !== 1 ||
                scl !== 1 || dut.touch_valid !== 0 || dut.touch_keys !== 0 ||
                dut.keys_stable !== 0 || dut.image_requested !== 0 ||
                dut.brightness_requested !== 8 || dut.image_active !== 0 ||
                dut.brightness_active !== 8)
                $fatal(1, "Business logic did not remain reset with the GAO clock running");
        end
        if (dut.resetn && ((old_image !== dut.image_active) ||
                          (old_brightness !== dut.brightness_active))) begin
            if (!was_boundary || dut.frame_count !== 0)
                $fatal(1, "Display controls changed away from a complete PWM-cycle boundary");
        end
        if (dut.resetn && {dbg0,dbg1,dbg2} !==
                          {dut.touch_keys[0],dut.touch_keys[1],dut.touch_valid})
            $fatal(1, "Debug mapping mismatch");
    end

    integer gao_reset_edges = 0;
    integer gao_reset_edges_before;
    always @(dut.clock) begin
        if (dut.resetn === 1'b0 && dut.presetn === 1'b1 && user_key === 1'b1)
            gao_reset_edges = gao_reset_edges + 1;
    end

    initial begin
        #10_000;
        if (!dut.resetn || dut.image_active !== 0 || dut.brightness_active !== 8)
            $fatal(1, "Startup/reset/defaults failed");

        gpio_pads = 8'h41; // Direct OUT1/OUT7: image S and brightness down.
        wait (dut.keys_stable == 16'h0041);
        #100;
        if (dut.image_requested !== 1 || dut.brightness_requested !== 7)
            $fatal(1, "OUT1/OUT7 direct GPIO keys did not reach UI/display actions");
        wait (dut.image_active == 1 && dut.brightness_active == 7);
        repeat (2) @(negedge dut.touch_valid);
        if (dut.brightness_requested !== 7)
            $fatal(1, "Held brightness key repeated");

        gpio_pads = 0;
        wait (dut.keys_stable == 0);
        s2 = 1; // Level selection here; retained button toggle is in tb_top_modes.
        physical_keys = 16'h8002; // K2=T and K16=brightness up together.
        wait (dut.keys_stable == 16'h8002);
        #100;
        if (dut.image_requested !== 0 || dut.brightness_requested !== 8)
            $fatal(1, "Second serial press failed");
        wait (dut.image_active == 0 && dut.brightness_active == 8);

        // Press active-high S1 while scan is low, then restart from row 0.
        @(negedge dut.scan_clock);
        gao_reset_edges_before = gao_reset_edges;
        user_key = 1;
        physical_keys = 0;
        #3_000;
        if (dut.resetn !== 0 || ck !== 0 || st !== 0 || oe !== 1 ||
            dut.keys_stable !== 0 || dut.image_active !== 0 || dut.brightness_active !== 8)
            $fatal(1, "S1 business reset failed");
        if (gao_reset_edges - gao_reset_edges_before < 16)
            $fatal(1, "GAO sample clock stopped during S1 reset");
        user_key = 0;
        physical_keys = 16'h0001;
        wait (dut.keys_stable == 16'h0001);
        wait (dut.image_active == 1);
        repeat (2) @(posedge st);
        #100;
        if (pixel_checks < 65536 || latch_checks < 1024)
            $fatal(1, "Insufficient scan/PWM coverage");
        $display("PASS tb_top: OUT1/OUT7 GPIO and 16-key serial -> debounce -> UI -> actual RGB and PWM-cycle commit; %0d RGB pixels, %0d row latches; S1 reset/restart",
                 pixel_checks, latch_checks);
        $finish;
    end
    initial begin
        #100_000_000;
        $fatal(1, "tb_top timeout");
    end
endmodule
