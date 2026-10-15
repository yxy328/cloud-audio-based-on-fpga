`timescale 1ns/1ps

// The sensor stays powered when the FPGA is reset. Its serial pointer resets
// only after >2 ms between active SCL edges. Touches are frozen at D0.
// This is deliberately an external pin model, not a copy of the FPGA FSM.
module ttp229_sensor_model #(
    parameter integer ACTIVE_LOW = 1,
    parameter integer DATA_DELAY_NS = 350
) (
    input wire scl,
    input wire [15:0] touches,
    output reg sdo,
    output reg [15:0] locked_touches,
    output integer edges_in_frame
);
    localparam IDLE_LEVEL = ACTIVE_LOW ? 1'b1 : 1'b0;
    time last_edge;
    reg next_data;
    initial begin
        sdo = IDLE_LEVEL;
        locked_touches = 0;
        edges_in_frame = 0;
        last_edge = 0;
    end
    always @(scl) begin
        if (scl === ~IDLE_LEVEL) begin
            if (last_edge == 0 || $time - last_edge > 2_000_000) begin
                edges_in_frame = 0;
                locked_touches = touches;
            end
            if (edges_in_frame >= 16)
                $fatal(1, "Sensor received a 17th edge without >2 ms re-alignment");
            next_data = ACTIVE_LOW ? ~locked_touches[edges_in_frame]
                                   : locked_touches[edges_in_frame];
            edges_in_frame = edges_in_frame + 1;
            last_edge = $time;
            // A real SDO pin is asynchronous to clk and has propagation delay.
            #(DATA_DELAY_NS) sdo = next_data;
        end
    end
endmodule

module core_tester #(
    parameter integer ACTIVE_LOW = 1
) (output reg done);
    localparam integer STARTUP_US = 3000;
    localparam integer HALF_US = 10;
    localparam IDLE_LEVEL = ACTIVE_LOW ? 1'b1 : 1'b0;
    reg clk = 0;
    always #500 clk = ~clk; // 1 MHz, the DUT's supported integer MHz clock.
    reg resetn = 0;
    reg [15:0] touches = 0;
    wire scl, sdo, ready, frame_valid;
    wire [15:0] raw_keys, keys, key_press, key_release;
    wire [15:0] locked_touches;
    wire [31:0] edges_in_frame;
    ttp229_serial16 #(
        .CLK_HZ(1_000_000), .ACTIVE_LOW(ACTIVE_LOW),
        .HALF_US(HALF_US), .GAP_US(3000),
        .STARTUP_US(STARTUP_US), .FILTER_FRAMES(3)
    ) dut (.*);
    ttp229_sensor_model #(.ACTIVE_LOW(ACTIVE_LOW)) sensor (
        .scl(scl), .touches(touches), .sdo(sdo),
        .locked_touches(locked_touches), .edges_in_frame(edges_in_frame)
    );

    integer frames_seen = 0;
    integer press_events = 0;
    integer release_events = 0;
    integer disagrees [0:15];
    integer k;
    reg [15:0] expected_keys = 0;
    reg [15:0] expected_press, expected_release;
    reg pending_frame = 0;
    reg previous_frame_valid = 0;
    reg [15:0] pending_raw = 0;
    time reset_released = 0;
    time active_edge_at = 0;
    time returned_at = 0;
    reg saw_edge_after_reset = 0;

    // A separate frame-level oracle: count consecutive disagreements per key.
    // Compare every cycle, including cycles where no event is allowed.
    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            expected_keys = 0;
            pending_frame = 0;
            previous_frame_valid = 0;
            saw_edge_after_reset = 0;
            active_edge_at = 0;
            returned_at = 0;
            for (k = 0; k < 16; k = k + 1) disagrees[k] = 0;
            if ({scl, ready, frame_valid, raw_keys, keys, key_press, key_release}
                !== {IDLE_LEVEL, 1'b0, 1'b0, 64'b0})
                $fatal(1, "mode %0d: reset outputs are incorrect", ACTIVE_LOW);
        end else begin
            expected_press = 0;
            expected_release = 0;
            if (pending_frame) begin
                for (k = 0; k < 16; k = k + 1) begin
                    if (pending_raw[k] == expected_keys[k]) disagrees[k] = 0;
                    else begin
                        disagrees[k] = disagrees[k] + 1;
                        if (disagrees[k] == 3) begin
                            expected_keys[k] = pending_raw[k];
                            if (pending_raw[k]) begin
                                expected_press[k] = 1;
                                press_events = press_events + 1;
                            end else begin
                                expected_release[k] = 1;
                                release_events = release_events + 1;
                            end
                            disagrees[k] = 0;
                        end
                    end
                end
            end
            if (keys !== expected_keys || key_press !== expected_press ||
                key_release !== expected_release)
                $fatal(1, "mode %0d: filter/event mismatch keys=%h expected=%h press=%h/%h release=%h/%h",
                    ACTIVE_LOW, keys, expected_keys, key_press, expected_press,
                    key_release, expected_release);
            if (!ready && (scl !== IDLE_LEVEL || frame_valid))
                $fatal(1, "mode %0d: serial activity before startup wait", ACTIVE_LOW);
            if (frame_valid) begin
                if (previous_frame_valid)
                    $fatal(1, "mode %0d: frame_valid is longer than one clock", ACTIVE_LOW);
                if (edges_in_frame != 16 || raw_keys !== locked_touches)
                    $fatal(1, "mode %0d: frame/bit-order mismatch: %0d edges, raw=%h expected=%h",
                        ACTIVE_LOW, edges_in_frame, raw_keys, locked_touches);
                frames_seen = frames_seen + 1;
                pending_raw = raw_keys;
            end
            pending_frame = frame_valid;
            previous_frame_valid = frame_valid;
        end
    end

    // Check both SCL polarities, pulse widths, and the startup time at pins.
    always @(scl) begin
        #2;
        if (resetn && scl === ~IDLE_LEVEL) begin
            if (!ready)
                $fatal(1, "mode %0d: active edge before ready", ACTIVE_LOW);
            if (!saw_edge_after_reset) begin
                // Reset is released between clock edges: allow one clock of
                // phase uncertainty while enforcing the programmed wait.
                if ($time - reset_released < STARTUP_US * 1000 - 1000)
                    $fatal(1, "mode %0d: startup wait is too short", ACTIVE_LOW);
                saw_edge_after_reset = 1;
            end else if (edges_in_frame == 1) begin
                if ($time - returned_at <= 2_000_000)
                    $fatal(1, "mode %0d: inter-frame idle is <=2 ms", ACTIVE_LOW);
            end else if ($time - returned_at != HALF_US * 1000)
                $fatal(1, "mode %0d: wrong inactive half-period", ACTIVE_LOW);
            active_edge_at = $time;
        end else if (resetn && scl === IDLE_LEVEL && active_edge_at != 0) begin
            if ($time - active_edge_at != HALF_US * 1000)
                $fatal(1, "mode %0d: wrong active half-period", ACTIVE_LOW);
            returned_at = $time;
        end
    end

    task drive_frames(input [15:0] bitmap, input integer count);
        integer target;
        begin
            touches = bitmap;
            target = frames_seen + count;
            wait (frames_seen >= target);
            @(negedge clk); // Let the filter consume frame_valid next cycle.
            @(negedge clk);
        end
    endtask
    task expect_keys(input [15:0] bitmap);
        begin
            if (keys !== bitmap)
                $fatal(1, "mode %0d: scenario expected keys=%h, got %h", ACTIVE_LOW, bitmap, keys);
        end
    endtask
    integer bit_number;
    integer target_frame;
    integer held_presses;
    initial begin
        done = 0;
        repeat (6) @(negedge clk);
        resetn = 1;
        reset_released = $time;
        drive_frames(16'h0000, 1);
        expect_keys(0);
        // All 16 one-hot positions; catches reversed order and a missing K16.
        for (bit_number = 0; bit_number < 16; bit_number = bit_number + 1)
            drive_frames(16'h0001 << bit_number, 1);
        drive_frames(16'h8000, 2);
        expect_keys(16'h8000);
        drive_frames(0, 3);
        expect_keys(0);
        // Two frames are insufficient, and returning to 0 cancels the count.
        drive_frames(16'h8000, 2);
        expect_keys(0);
        drive_frames(0, 1);
        // K2 chatter must not postpone the independent K1 confirmation.
        drive_frames(16'h0003, 1);
        drive_frames(16'h0001, 1);
        drive_frames(16'h0003, 1);
        expect_keys(16'h0001);
        drive_frames(16'h0003, 2);
        expect_keys(16'h0003);
        // Interrupted release, then a full release while K2 remains held.
        drive_frames(16'h0002, 2);
        expect_keys(16'h0003);
        drive_frames(16'h0003, 1);
        drive_frames(16'h0002, 2);
        expect_keys(16'h0003);
        drive_frames(16'h0002, 1);
        expect_keys(16'h0002);
        drive_frames(0, 2);
        expect_keys(16'h0002);
        drive_frames(16'h0002, 1);
        drive_frames(0, 3);
        expect_keys(0);
        // Multiple non-adjacent keys and all keys can be represented together.
        drive_frames(16'h8421, 3);
        expect_keys(16'h8421);
        held_presses = press_events;
        drive_frames(16'h8421, 8);
        if (press_events != held_presses)
            $fatal(1, "mode %0d: long hold generated repeated presses", ACTIVE_LOW);
        drive_frames(16'hffff, 3);
        expect_keys(16'hffff);
        drive_frames(0, 3);
        expect_keys(0);
        // A touch change half way through a read must wait for the next frame.
        touches = 16'h0010;
        target_frame = frames_seen + 1;
        wait (edges_in_frame == 1);
        wait (edges_in_frame == 8);
        touches = 16'hf0f0;
        wait (frames_seen >= target_frame);
        if (raw_keys !== 16'h0010)
            $fatal(1, "mode %0d: sensor did not lock a complete frame", ACTIVE_LOW);
        @(negedge clk);
        @(negedge clk);
        drive_frames(16'hf0f0, 3);
        expect_keys(16'hf0f0);
        // Reset during a partly read frame; module pointer is NOT reset here.
        wait (edges_in_frame == 1);
        wait (edges_in_frame == 7);
        @(negedge clk);
        resetn = 0;
        touches = 16'h8001;
        repeat (4) @(negedge clk);
        resetn = 1;
        reset_released = $time;
        drive_frames(16'h8001, 3);
        expect_keys(16'h8001);
        drive_frames(0, 3);
        expect_keys(0);
        $display("PASS core ACTIVE_LOW=%0d: %0d complete frames; 16 keys, filtering, lock and reset", ACTIVE_LOW, frames_seen);
        done = 1;
    end
endmodule

// Receiver decodes only the external UART pin at the nominal bit centers.
// Resynchronize on 'R' so a caller can inspect complete periodic reports.
module uart_line_monitor #(
    parameter integer CLK_HZ = 1_000_000,
    parameter integer BAUD = 115200
) (
    input wire tx,
    input wire enable,
    output reg [119:0] line,
    output integer lines_seen
);
    localparam integer BIT_TICKS = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer BIT_NS = 1_000_000_000 / CLK_HZ * BIT_TICKS;
    reg [7:0] byte_data;
    reg [119:0] buffer;
    integer bit_number;
    integer char_number;
    initial begin
        line = 0;
        lines_seen = 0;
        buffer = 0;
        char_number = 0;
        forever begin
            @(negedge tx);
            if (enable) begin
                #(BIT_NS / 2);
                if (tx !== 0) $fatal(1, "UART start bit is too short");
                for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                    #(BIT_NS);
                    if (tx !== 0 && tx !== 1) $fatal(1, "UART data is unknown");
                    byte_data[bit_number] = tx;
                end
                #(BIT_NS);
                if (tx !== 1) $fatal(1, "UART stop bit/framing error");
                if (char_number == 0) begin
                    if (byte_data == "R") begin
                        buffer[119:112] = byte_data;
                        char_number = 1;
                    end
                end else begin
                    buffer[119-char_number*8 -: 8] = byte_data;
                    if (char_number == 14) begin
                        line = buffer;
                        lines_seen = lines_seen + 1;
                        char_number = 0;
                    end else char_number = char_number + 1;
                end
                #(BIT_NS / 2);
            end
        end
    end
endmodule

module uart_tester(output reg done);
    reg clk = 0;
    always #500 clk = ~clk;
    reg resetn = 0;
    reg ready = 0;
    reg [15:0] raw_keys = 16'h1a2f;
    reg [15:0] keys = 16'h903c;
    wire tx;
    wire [119:0] line;
    wire [31:0] lines_seen;
    ttp229_uart_report #(.CLK_HZ(1_000_000), .BAUD(100000), .REPORT_MS(3)) dut (.*);
    uart_line_monitor #(.BAUD(100000)) receiver (.*,.enable(resetn && ready));
    time ready_at;
    initial begin
        done = 0;
        repeat (4) @(negedge clk);
        resetn = 1;
        repeat (4000) begin
            @(negedge clk);
            if (tx !== 1) $fatal(1, "UART transmitted while ready was low");
        end
        ready = 1;
        ready_at = $time;
        @(negedge tx);
        if ($time - ready_at < 3_000_000)
            $fatal(1, "UART did not wait for the report interval");
        // Changes during a line must not tear the snapshot.
        raw_keys = 16'hbeef;
        keys = 16'h0c05;
        wait (lines_seen == 1);
        if (line !== {"R=1A2F K=903C", 8'h0d, 8'h0a})
            $fatal(1, "UART first snapshot mismatch: %s", line);
        wait (lines_seen == 2);
        if (line !== {"R=BEEF K=0C05", 8'h0d, 8'h0a})
            $fatal(1, "UART next snapshot mismatch: %s", line);
        @(negedge clk);
        ready = 0;
        repeat (4000) begin
            @(negedge clk);
            if (tx !== 1) $fatal(1, "UART did not become idle when ready went low");
        end
        $display("PASS UART: 8N1 pin timing, uppercase hex, CR/LF, stable snapshots and ready gating");
        done = 1;
    end
endmodule

module top_tester(output reg done);
    reg CLK_IN = 0;
    always #500 CLK_IN = ~CLK_IN;
    reg [15:0] touches = 16'h8001;
    wire touch_scl, touch_sdo, led_key, led_run, uart_tx;
    wire [15:0] locked_touches;
    wire [31:0] edges_in_frame;
    wire [119:0] line;
    wire [31:0] lines_seen;
    ttp229_serial16_top #(
        .CLK_HZ(1_000_000), .STARTUP_US(3000), .GAP_US(3000), .REPORT_MS(5)
    ) dut (.*);
    ttp229_sensor_model #(.ACTIVE_LOW(0)) sensor (
        .scl(touch_scl), .sdo(touch_sdo), .touches(touches),
        .locked_touches(locked_touches), .edges_in_frame(edges_in_frame)
    );
    uart_line_monitor receiver (
        .tx(uart_tx), .enable(dut.resetn && dut.ready), .line(line), .lines_seen(lines_seen)
    );
    integer target_line;
    time reset_at;
    initial begin
        done = 0;
        // No external reset exists: check that FPGA power-up state resets it.
        repeat (250) begin
            @(negedge CLK_IN);
            if (touch_scl !== 0 || led_key !== 0 || led_run !== 0 || uart_tx !== 1)
                $fatal(1, "Top automatic power-on reset failed");
        end
        wait (dut.resetn === 1);
        reset_at = $time;
        wait (led_key === 1);
        if (dut.keys !== 16'h8001) $fatal(1, "Top LED did not reflect confirmed K1+K16");
        target_line = lines_seen + 1;
        wait (lines_seen >= target_line);
        if (line !== {"R=8001 K=8001", 8'h0d, 8'h0a})
            $fatal(1, "Top UART pressed report mismatch: %s", line);
        touches = 0;
        wait (led_key === 0);
        // One already transmitting line may have captured the old key state.
        // The following complete report must capture the confirmed release.
        target_line = lines_seen + 2;
        wait (lines_seen >= target_line);
        if (line !== {"R=0000 K=0000", 8'h0d, 8'h0a})
            $fatal(1, "Top UART released report mismatch: %s", line);
        wait (led_run === 1);
        if ($time - reset_at != 250_000_000)
            $fatal(1, "Top run LED first transition has incorrect timing");
        wait (led_run === 0);
        if ($time - reset_at != 500_000_000)
            $fatal(1, "Top run LED second transition has incorrect timing");
        $display("PASS top active-high default: automatic reset, key LED, 250 ms run-LED transitions and UART reports");
        done = 1;
    end
endmodule

module production_clock_tester(output reg done);
    reg clk = 0;
    always begin // Stop this fast test clock once its checks finish.
        if (done === 1) wait (done !== 1);
        #10 clk = ~clk; // Actual 50 MHz board clock.
    end
    reg resetn = 0;
    reg [15:0] touches = 16'h8000;
    wire scl, sdo, ready, frame_valid;
    wire [15:0] raw_keys, keys, key_press, key_release, locked_touches;
    wire [31:0] edges_in_frame;
    // Only the startup delay is shortened; HALF_US=10 and GAP_US=10000
    // retain the production defaults and their 50 MHz counter conversion.
    ttp229_serial16 #(.STARTUP_US(3000)) dut (.*);
    ttp229_sensor_model #(.ACTIVE_LOW(0), .DATA_DELAY_NS(77)) sensor (
        .scl(scl), .sdo(sdo), .touches(touches),
        .locked_touches(locked_touches), .edges_in_frame(edges_in_frame)
    );
    time reset_at, first_edge_at, active_at, returned_at, frame_at;
    integer n;
    initial begin
        done = 0;
        repeat (6) @(negedge clk);
        resetn = 1;
        reset_at = $time;
        @(posedge scl);
        first_edge_at = $time;
        if (first_edge_at - reset_at != 3_000_000 - 10)
            $fatal(1, "50 MHz startup counter conversion is incorrect");
        for (n = 0; n < 16; n = n + 1) begin
            if (n != 0) @(posedge scl);
            active_at = $time;
            if (n != 0 && active_at - returned_at != 10_000)
                $fatal(1, "50 MHz inactive SCL half-period is incorrect");
            @(negedge scl);
            returned_at = $time;
            if (returned_at - active_at != 10_000)
                $fatal(1, "50 MHz active SCL half-period is incorrect");
        end
        @(posedge frame_valid);
        #1;
        frame_at = $time - 1;
        if (raw_keys !== 16'h8000 || edges_in_frame != 16)
            $fatal(1, "50 MHz complete K16 frame is incorrect");
        @(posedge scl);
        #1; // Allow the independent sensor model to process the same edge.
        if ($time - 1 - frame_at != 10_000_000 || edges_in_frame != 1)
            $fatal(1, "50 MHz production 10 ms gap conversion is incorrect");
        $display("PASS 50 MHz active-high default: startup, 10 us half-periods, all 16 clocks and default 10 ms gap");
        done = 1;
    end
endmodule

module tb_ttp229_serial16;
    wire low_done, high_done, uart_done, top_done, production_done;
    core_tester #(.ACTIVE_LOW(1)) low_mode (.done(low_done));
    core_tester #(.ACTIVE_LOW(0)) high_mode (.done(high_done));
    uart_tester uart_test (.done(uart_done));
    top_tester top_test (.done(top_done));
    production_clock_tester production_clock (.done(production_done));
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("ttp229_serial16.vcd");
            $dumpvars(0, tb_ttp229_serial16);
        end
        wait (low_done && high_done && uart_done && top_done && production_done);
        $display("ALL TESTS PASSED");
        $finish;
    end
    initial begin
        #600_000_000;
        $fatal(1, "Simulation timeout");
    end
endmodule
