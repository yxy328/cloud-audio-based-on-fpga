`timescale 1ns/1ps

// Focused cold-start check at 1 MHz: simulate the actual 600 ms wait
// without advancing a 50 MHz master clock thirty million times.
// The modeled chip disables all serial output for its first 0.5 seconds,
// independently of FPGA reset. Serial framing is checked in tb_ttp229.
module tb_ttp229_startup;
    reg clk = 1'b0;
    wire [1:0] done;
    always #500 clk = ~clk;

    ttp229_startup_checker #(.ACTIVE_LOW(1)) low_checker
        (.clk(clk), .done(done[0]));
    ttp229_startup_checker #(.ACTIVE_LOW(0)) high_checker
        (.clk(clk), .done(done[1]));

    initial begin
        wait (&done);
        $display("PASS: full 600 ms startup, disabled chip until 0.5 s, first K1 frame in both polarities");
        $finish;
    end
    initial begin
        #650_000_000;
        $fatal(1, "FAIL: TTP229 startup simulation timed out");
    end
endmodule

module ttp229_startup_checker #(
    parameter ACTIVE_LOW = 1
) (
    input wire clk,
    output reg done = 1'b0
);
    localparam SCL_IDLE = ACTIVE_LOW ? 1'b1 : 1'b0;
    localparam SCL_ACTIVE = ~SCL_IDLE;
    localparam STARTUP_TICKS = 600000; // 600 ms at 1 MHz
    localparam CHIP_STABLE_NS = 500_000_000;

    reg resetn = 1'b0;
    reg sdo = SCL_IDLE;
    wire scl;
    wire touch_valid;
    wire [15:0] touch_keys;
    ttp229_ctrl #(
        .CLK_FREQ(1_000_000), .KEY_NUM(16), .TP_ACTIVE_LOW(ACTIVE_LOW)
        // Use the default STARTUP_US=600000.
    ) dut (
        .clk(clk), .resetn(resetn), .sdo(sdo), .scl(scl),
        .touch_valid(touch_valid), .touch_keys(touch_keys),
        .state_o(), .bit_cnt_o()
    );

    // A chip powers up at t=0, has no FPGA-reset input, and advances on
    // the physical active edge selected by TP1. Its stable first scan
    // contains only K1. Early host clocks cannot extract that key.
    integer chip_index = 0;
    reg chip_level = SCL_IDLE;
    always @(scl) begin
        if (scl === 1'b0 || scl === 1'b1) begin
            if ($time < CHIP_STABLE_NS)
                chip_level = SCL_IDLE;
            else if (scl === SCL_ACTIVE && chip_index < 16) begin
                chip_level = ACTIVE_LOW ? ~(chip_index == 0) : (chip_index == 0);
                chip_index = chip_index + 1;
            end
            #100;
            sdo = chip_level;
        end
    end

    integer cycle = 0;
    integer active_edges = 0;
    reg previous_scl = SCL_IDLE;
    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            cycle = 0;
            active_edges = 0;
            previous_scl = SCL_IDLE;
            if (scl !== SCL_IDLE || touch_valid !== 1'b0 || touch_keys !== 16'h0000)
                $fatal(1, "FAIL: startup reset outputs, active_low=%0d", ACTIVE_LOW);
        end
        else if (!done) begin
            cycle = cycle + 1;
            if (cycle < STARTUP_TICKS && (scl !== SCL_IDLE || touch_valid !== 1'b0))
                $fatal(1, "FAIL: clock/valid before 600 ms, active_low=%0d, cycle=%0d", ACTIVE_LOW, cycle);
            if (previous_scl == SCL_IDLE && scl == SCL_ACTIVE) begin
                if (active_edges == 0 && cycle != STARTUP_TICKS)
                    $fatal(1, "FAIL: first serial edge at cycle %0d instead of 600000", cycle);
                if ($time < CHIP_STABLE_NS)
                    $fatal(1, "FAIL: serial clock during chip power-on disable period");
                active_edges = active_edges + 1;
            end
            if (touch_valid) begin
                if (active_edges != 16 || chip_index != 16 || scl !== SCL_IDLE)
                    $fatal(1, "FAIL: startup frame incomplete, active_low=%0d", ACTIVE_LOW);
                if (touch_keys !== 16'h0001)
                    $fatal(1, "FAIL: first startup frame expected K1=0001, observed %h", touch_keys);
                done = 1'b1;
                $display("PASS [startup active_low=%0d]: first edge at 600 ms, first K1 frame at %0t", ACTIVE_LOW, $time);
            end
            else if (touch_keys !== 16'h0000)
                $fatal(1, "FAIL: touch keys changed before the first valid frame");
            previous_scl = scl;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        resetn = 1'b1;
    end
endmodule
