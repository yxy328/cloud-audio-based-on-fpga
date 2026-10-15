`timescale 1ns/1ps
// Full-duplex 8N1, one fabric clock, ready/valid byte interfaces.
// RX queue absorbs short command bursts while the previous reply is sent.
// On framing error/overflow, flush pending input and discard through EOL.
module uart_8n1 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600
) (
    input wire clk,
    input wire resetn,
    input wire rx,
    output wire tx,
    output wire [7:0] rx_data,
    output wire rx_valid,
    input wire rx_ready,
    output reg rx_fault,
    input wire [7:0] tx_data,
    input wire tx_valid,
    output wire tx_ready
);
    localparam integer BIT_TICKS = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer HALF_TICKS = BIT_TICKS/2;
    localparam integer COUNT_W = (BIT_TICKS < 2) ? 1 : $clog2(BIT_TICKS);
    localparam [2:0] IDLE=0, START=1, DATA=2, STOP=3, RECOVER=4;
    reg rx_meta, rx_sync;
    reg [2:0] rx_state, rx_index;
    reg [COUNT_W-1:0] rx_count;
    reg [7:0] rx_shift, received_byte;
    reg received_valid, received_error;
    always @(posedge clk) begin
        if (!resetn) begin rx_meta<=1; rx_sync<=1; end
        else begin rx_meta<=rx; rx_sync<=rx_meta; end
    end
    always @(posedge clk) begin
        if (!resetn) begin
            rx_state<=IDLE; rx_index<=0; rx_count<=0; rx_shift<=0;
            received_byte<=0; received_valid<=0; received_error<=0;
        end else begin
            received_valid<=0; received_error<=0;
            case (rx_state)
                IDLE: if (!rx_sync) begin rx_count<=HALF_TICKS-1; rx_state<=START; end
                START: if (rx_count!=0) rx_count<=rx_count-1'b1;
                    else if (rx_sync) rx_state<=IDLE;
                    else begin rx_count<=BIT_TICKS-1; rx_index<=0; rx_state<=DATA; end
                DATA: if (rx_count!=0) rx_count<=rx_count-1'b1;
                    else begin
                        rx_shift[rx_index]<=rx_sync; rx_count<=BIT_TICKS-1;
                        if (rx_index==7) rx_state<=STOP;
                        else rx_index<=rx_index+1'b1;
                    end
                STOP: if (rx_count!=0) rx_count<=rx_count-1'b1;
                    else if (rx_sync) begin
                        received_byte<=rx_shift; received_valid<=1; rx_state<=IDLE;
                    end else begin received_error<=1; rx_state<=RECOVER; end
                RECOVER: if (rx_sync) rx_state<=IDLE;
                default: rx_state<=IDLE;
            endcase
        end
    end

    reg [7:0] fifo [0:127];
    reg [6:0] wr_ptr, rd_ptr;
    reg [7:0] queued;
    reg discard_line;
    reg [7:0] prefetched_byte;
    reg prefetched_valid;
    wire eol = received_byte==8'd13 || received_byte==8'd10;
    wire pop = rx_valid && rx_ready;
    // Explicit synchronous read. Never read an empty queue on its write edge:
    // the native SDPB reads old data on a same-address read/write collision.
    wire fetch = !prefetched_valid && queued!=0;
    wire push = received_valid && (!discard_line || eol);
    wire overrun = push && queued==128;
    assign rx_valid = prefetched_valid;
    assign rx_data = prefetched_byte;
    always @(posedge clk) begin
        if (!resetn) begin
            wr_ptr<=0; rd_ptr<=0; queued<=0; discard_line<=0; rx_fault<=0;
            prefetched_byte<=0; prefetched_valid<=0;
        end else begin
            rx_fault<=0;
            if (received_error || overrun) begin
                wr_ptr<=0; rd_ptr<=0; queued<=0;
                discard_line<=1; rx_fault<=1;
                prefetched_valid<=0;
            end else begin
                if (push) begin
                    fifo[wr_ptr]<=received_byte; wr_ptr<=wr_ptr+1'b1;
                    if (eol) discard_line<=0;
                end
                if (pop) prefetched_valid<=0;
                if (fetch) begin
                    prefetched_byte<=fifo[rd_ptr];
                    prefetched_valid<=1;
                    rd_ptr<=rd_ptr+1'b1;
                end
                case ({push,fetch})
                    2'b10: queued<=queued+1'b1;
                    2'b01: queued<=queued-1'b1;
                    default: queued<=queued;
                endcase
            end
        end
    end

    reg [9:0] tx_shift;
    reg [3:0] tx_bits;
    reg [COUNT_W-1:0] tx_count;
    assign tx_ready = tx_bits==0;
    assign tx = tx_ready ? 1'b1 : tx_shift[0];
    always @(posedge clk) begin
        if (!resetn) begin tx_shift<=10'h3ff; tx_bits<=0; tx_count<=0; end
        else if (tx_ready && tx_valid) begin
            tx_shift<={1'b1,tx_data,1'b0}; tx_bits<=10; tx_count<=BIT_TICKS-1;
        end else if (!tx_ready) begin
            if (tx_count!=0) tx_count<=tx_count-1'b1;
            else begin
                tx_shift<={1'b1,tx_shift[9:1]}; tx_bits<=tx_bits-1'b1;
                tx_count<=BIT_TICKS-1;
            end
        end
    end
endmodule
