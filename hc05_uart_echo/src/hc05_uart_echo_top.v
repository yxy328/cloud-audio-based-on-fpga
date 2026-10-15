`timescale 1ns/1ps
module hc05_uart_echo_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600
) (
    input wire CLK_IN,
    input wire hc05_rx, // HC-05 TXD -> FPGA F2 / J3 pin 16
    output wire hc05_tx, // FPGA F1 / J3 pin 15 -> HC-05 RXD
    output wire led_rx,
    output wire led_run
);
    // Gowin power-up initial FF value, independent of the board buttons.
    reg [7:0] por_count = 0;
    wire resetn = &por_count;
    always @(posedge CLK_IN)
        if (!resetn) por_count <= por_count+1'b1;
    wire rx_valid, framing_error, overflow;
    wire [7:0] rx_data;
    uart_echo #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(CLK_IN), .resetn(resetn), .rx(hc05_rx), .tx(hc05_tx),
        .rx_valid(rx_valid), .rx_data(rx_data),
        .framing_error(framing_error), .overflow(overflow)
    );
    reg [31:0] blink_count, activity_count;
    reg blink;
    always @(posedge CLK_IN) begin
        if (!resetn) begin
            blink_count <= 0;
            activity_count <= 0;
            blink <= 0;
        end else begin
            if (blink_count == CLK_HZ/4-1) begin
                blink_count <= 0;
                blink <= ~blink;
            end else blink_count <= blink_count+1'b1;
            if (rx_valid) activity_count <= CLK_HZ/5;
            else if (activity_count != 0) activity_count <= activity_count-1'b1;
        end
    end
    assign led_rx = (activity_count != 0);
    assign led_run = (framing_error || overflow) ? 1'b1 : blink;
endmodule
