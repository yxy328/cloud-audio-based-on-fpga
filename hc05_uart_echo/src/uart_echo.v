`timescale 1ns/1ps
// 8N1 UART echo, LSB first, no hardware flow control.
// CLK_HZ / BAUD must be at least 4. Intended for short terminal messages.
module uart_echo #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600
) (
    input wire clk,
    input wire resetn,
    input wire rx,
    output wire tx,
    output reg rx_valid,
    output reg [7:0] rx_data,
    output reg framing_error,
    output reg overflow
);
    localparam integer BIT_TICKS = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer HALF_TICKS = BIT_TICKS / 2;
    localparam [2:0] IDLE=0, START=1, DATA=2, STOP=3, RECOVER=4;
    reg rx_meta, rx_sync;
    reg [2:0] rx_state;
    reg [31:0] rx_count;
    reg [2:0] rx_index;
    reg [7:0] rx_shift;
    always @(posedge clk) begin
        if (!resetn) begin
            rx_meta <= 1;
            rx_sync <= 1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end
    always @(posedge clk) begin
        if (!resetn) begin
            rx_state <= IDLE;
            rx_count <= 0;
            rx_index <= 0;
            rx_shift <= 0;
            rx_data <= 0;
            rx_valid <= 0;
            framing_error <= 0;
        end else begin
            rx_valid <= 0;
            case (rx_state)
                IDLE: if (!rx_sync) begin
                    rx_count <= HALF_TICKS-1;
                    rx_state <= START;
                end
                START: if (rx_count != 0) rx_count <= rx_count-1'b1;
                else if (rx_sync) rx_state <= IDLE; // Reject a short glitch.
                else begin
                    rx_count <= BIT_TICKS-1;
                    rx_index <= 0;
                    rx_state <= DATA;
                end
                DATA: if (rx_count != 0) rx_count <= rx_count-1'b1;
                else begin
                    rx_shift[rx_index] <= rx_sync;
                    rx_count <= BIT_TICKS-1;
                    if (rx_index == 7) rx_state <= STOP;
                    else rx_index <= rx_index+1'b1;
                end
                STOP: if (rx_count != 0) rx_count <= rx_count-1'b1;
                else if (rx_sync) begin
                    rx_data <= rx_shift;
                    rx_valid <= 1;
                    rx_state <= IDLE;
                end else begin
                    framing_error <= 1;
                    rx_state <= RECOVER;
                end
                RECOVER: if (rx_sync) rx_state <= IDLE;
                default: rx_state <= IDLE;
            endcase
        end
    end

    // Small queue decouples receive and transmit timing; errors latch until reset.
    reg [7:0] fifo [0:31];
    reg [4:0] wr_ptr, rd_ptr;
    reg [5:0] count;
    reg [9:0] tx_shift;
    reg [3:0] bits_left;
    reg [31:0] tx_count;
    wire pop = (bits_left == 0) && (count != 0);
    wire push = rx_valid && ((count < 32) || pop);
    assign tx = (bits_left == 0) ? 1'b1 : tx_shift[0];
    always @(posedge clk) begin
        if (!resetn) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            tx_shift <= 10'h3ff;
            bits_left <= 0;
            tx_count <= 0;
            overflow <= 0;
        end else begin
            if (rx_valid && !push) overflow <= 1;
            if (push) begin
                fifo[wr_ptr] <= rx_data;
                wr_ptr <= wr_ptr+1'b1;
            end
            case ({push,pop})
                2'b10: count <= count+1'b1;
                2'b01: count <= count-1'b1;
                default: count <= count;
            endcase
            if (pop) begin
                tx_shift <= {1'b1, fifo[rd_ptr], 1'b0};
                rd_ptr <= rd_ptr+1'b1;
                bits_left <= 10;
                tx_count <= BIT_TICKS-1;
            end else if (bits_left != 0) begin
                if (tx_count != 0) tx_count <= tx_count-1'b1;
                else begin
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    bits_left <= bits_left-1'b1;
                    tx_count <= BIT_TICKS-1;
                end
            end
        end
    end
endmodule
