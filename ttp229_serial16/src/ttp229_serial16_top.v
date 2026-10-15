`timescale 1ns/1ps
// Tang Primer 25K: fixed 16-key mode, no S2 mode selection needed.
// User module: TP1 + TP2 yellow jumpers fitted -> active-high, 16 keys.
module ttp229_serial16_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer STARTUP_US = 1_000_000,
    parameter integer GAP_US = 10_000,
    parameter integer REPORT_MS = 100,
    parameter integer ACTIVE_LOW = 0
) (
    input wire CLK_IN,
    input wire touch_sdo,
    output wire touch_scl,
    output wire led_key,
    output wire led_run,
    output wire uart_tx
);
    // Gowin synthesizes this initial value into the FPGA power-up FF state.
    // Keep the reset independent of board button polarity and module SDO.
    reg [7:0] por_count = 8'd0;
    wire resetn = &por_count;
    always @(posedge CLK_IN) begin
        if (!resetn)
            por_count <= por_count + 1'b1;
    end

    wire ready;
    wire frame_valid;
    wire [15:0] raw_keys, keys, key_press, key_release;
    ttp229_serial16 #(
        .CLK_HZ(CLK_HZ), .ACTIVE_LOW(ACTIVE_LOW),
        .STARTUP_US(STARTUP_US), .GAP_US(GAP_US)
    ) u_touch (
        .clk(CLK_IN), .resetn(resetn), .sdo(touch_sdo), .scl(touch_scl),
        .ready(ready), .frame_valid(frame_valid), .raw_keys(raw_keys),
        .keys(keys), .key_press(key_press), .key_release(key_release)
    );

    // Dock LED3 READY (E8), LED4 DONE (D7): both light at HIGH level.
    // LED3 indicates any confirmed key; LED4 blinks to prove the fabric runs.
    reg [31:0] blink_count;
    reg blink;
    always @(posedge CLK_IN) begin
        if (!resetn) begin
            blink_count <= 0;
            blink <= 0;
        end else if (blink_count == CLK_HZ/4 - 1) begin
            blink_count <= 0;
            blink <= ~blink;
        end else
            blink_count <= blink_count + 1'b1;
    end
    assign led_key = ready && (|keys);
    assign led_run = blink;

    ttp229_uart_report #(.CLK_HZ(CLK_HZ), .REPORT_MS(REPORT_MS)) u_report (
        .clk(CLK_IN), .resetn(resetn), .ready(ready),
        .raw_keys(raw_keys), .keys(keys), .tx(uart_tx)
    );
endmodule
