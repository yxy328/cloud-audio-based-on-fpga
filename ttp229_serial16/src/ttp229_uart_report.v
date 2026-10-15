`timescale 1ns/1ps
// Optional readout: 115200 baud, 8 data bits, no parity, 1 stop bit.
// Once per 100 ms: "R=0000 K=0000\r\n". R=raw frame; K=filtered bitmap.
// One 50 MHz domain; UART timing uses enables, not another clock.
module ttp229_uart_report #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115200,
    parameter integer REPORT_MS = 100
) (
    input wire clk,
    input wire resetn,
    input wire ready,
    input wire [15:0] raw_keys,
    input wire [15:0] keys,
    output wire tx
);
    localparam integer BIT_TICKS = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer REPORT_TICKS = (CLK_HZ / 1000) * REPORT_MS;
    reg [31:0] report_count;
    reg report_active;
    reg [3:0] char_index;
    reg [15:0] report_raw, report_keys;
    reg [31:0] baud_count;
    reg [3:0] bits_left;
    reg [9:0] tx_shift;
    assign tx = (bits_left == 0) ? 1'b1 : tx_shift[0];

    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            hex_char = (nibble < 10) ? (8'h30 + nibble) : (8'h41 + nibble - 10);
        end
    endfunction
    reg [7:0] char_data;
    always @* begin
        case (char_index)
            0: char_data = "R";
            1: char_data = "=";
            2: char_data = hex_char(report_raw[15:12]);
            3: char_data = hex_char(report_raw[11:8]);
            4: char_data = hex_char(report_raw[7:4]);
            5: char_data = hex_char(report_raw[3:0]);
            6: char_data = " ";
            7: char_data = "K";
            8: char_data = "=";
            9: char_data = hex_char(report_keys[15:12]);
            10: char_data = hex_char(report_keys[11:8]);
            11: char_data = hex_char(report_keys[7:4]);
            12: char_data = hex_char(report_keys[3:0]);
            13: char_data = 8'h0d;
            default: char_data = 8'h0a;
        endcase
    end

    always @(posedge clk) begin
        if (!resetn || !ready) begin
            report_count <= 0;
            report_active <= 0;
            char_index <= 0;
            report_raw <= 0;
            report_keys <= 0;
            baud_count <= 0;
            bits_left <= 0;
            tx_shift <= 10'h3ff;
        end else begin
            if (report_count == REPORT_TICKS - 1) begin
                report_count <= 0;
                if (!report_active && bits_left == 0) begin
                    report_raw <= raw_keys;
                    report_keys <= keys;
                    char_index <= 0;
                    report_active <= 1;
                end
            end else
                report_count <= report_count + 1'b1;

            if (bits_left != 0) begin
                if (baud_count != 0)
                    baud_count <= baud_count - 1'b1;
                else begin
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bits_left <= bits_left - 1'b1;
                    baud_count <= BIT_TICKS - 1;
                end
            end else if (report_active) begin
                tx_shift <= {1'b1, char_data, 1'b0};
                bits_left <= 10;
                baud_count <= BIT_TICKS - 1;
                if (char_index == 14)
                    report_active <= 0;
                else
                    char_index <= char_index + 1'b1;
            end
        end
    end
endmodule
