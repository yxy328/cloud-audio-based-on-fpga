`timescale 1ns/1ps
module tb_control12_live_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,enable=0,tx_ready=0;reg [15:0] scan_keys=0;
    wire [7:0] data,ref_data;wire valid,last,ref_valid,ref_last;
    key_live_stream dut(.clk(clk),.resetn(resetn),.enable(enable),.scan_keys(scan_keys),.tx_data(data),.tx_valid(valid),.tx_last(last),.tx_ready(tx_ready));
    key_live_stream_reference ref_dut(.clk(clk),.resetn(resetn),.enable(enable),.scan_keys(scan_keys),.tx_data(ref_data),.tx_valid(ref_valid),.tx_last(ref_last),.tx_ready(tx_ready));
    integer n,seed=193172,random_value,lines=0,stalls=0;reg saw_full=0;
    always @(posedge clk)if(resetn)begin
        if(valid && tx_ready && last)lines=lines+1;
        if(valid && !tx_ready)stalls=stalls+1;
        if(dut.count==32)saw_full=1;
        #1;
        if({data,valid,last}!=={ref_data,ref_valid,ref_last})
            $fatal(1,"Live output differs at cycle %0d",n);
    end
    initial begin
        repeat(5)@(negedge clk);resetn=1;enable=1;scan_keys=16'hffff;
        for(n=0;n<100000;n=n+1)begin
            @(negedge clk);random_value=$random(seed);
            tx_ready=(random_value&15)<3;
            if(n%47==0)scan_keys=random_value;
            if(n%2011==0)enable=!enable;
            if(n%10007==0)resetn=0;else resetn=1;
        end
        if(lines<500 || stalls<5000 || !saw_full)$fatal(1,"Incomplete live stress %0d/%0d/full%0d",lines,stalls,saw_full);
        $display("PASS live packet exact equivalence: 100000 cycles, %0d lines, %0d stalled bytes, full FIFO/wrap, all key numbers, reset/enable/drop interactions",lines,stalls);$finish;
    end
endmodule

`timescale 1ns/1ps
// Edge-triggered 16-key scan uplink for the phone app live link. Every changed
// scan key emits one "K,XX,Y\r\n" line: XX is the 1-based key number and Y is
// 1 for press, 0 for release. A frame already in flight always completes so
// the UART never sees a truncated line when enable drops.
module key_live_stream_reference(
    input wire clk, resetn, enable,
    input wire [15:0] scan_keys,
    output reg [7:0] tx_data,
    output wire tx_valid, tx_last,
    input wire tx_ready
);
    localparam IDLE=2'd0, LOAD=2'd1, SEND=2'd2;
    reg [1:0] state;
    reg enable_q;
    reg [15:0] last_keys, captured, pending;
    reg [4:0] fifo [0:31];
    reg [4:0] fifo_q;
    reg [4:0] wr_ptr, rd_ptr;
    reg [5:0] count;
    reg [63:0] message;
    reg [3:0] send_index;
    wire enable_rise=enable && !enable_q;
    wire capture=enable && !enable_rise && pending==0 && scan_keys!=last_keys;
    wire pushing=pending!=0 && count<6'd32;
    wire dropping=pending!=0 && count==6'd32;
    wire [3:0] low_idx=
        pending[0] ? 4'd0 : pending[1] ? 4'd1 : pending[2] ? 4'd2 : pending[3] ? 4'd3 :
        pending[4] ? 4'd4 : pending[5] ? 4'd5 : pending[6] ? 4'd6 : pending[7] ? 4'd7 :
        pending[8] ? 4'd8 : pending[9] ? 4'd9 : pending[10] ? 4'd10 : pending[11] ? 4'd11 :
        pending[12] ? 4'd12 : pending[13] ? 4'd13 : pending[14] ? 4'd14 : 4'd15;
    wire [4:0] key_number={1'b0,fifo_q[3:0]}+5'd1;
    wire [7:0] tens_byte=key_number>=5'd10 ? 8'd49 : 8'd48;
    wire [7:0] ones_byte=8'd48+(key_number>=5'd10 ? key_number-5'd10 : key_number);
    wire fetch=enable && state==IDLE && count!=0;
    assign tx_valid=state==SEND;
    assign tx_last=state==SEND && send_index==4'd7;
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; enable_q<=0; last_keys<=0; captured<=0; pending<=0;
            fifo_q<=0; wr_ptr<=0; rd_ptr<=0; count<=0; message<=0; send_index<=0; tx_data<=0;
        end else begin
            enable_q<=enable;
            if(!enable) begin
                pending<=0; wr_ptr<=0; rd_ptr<=0; count<=0; last_keys<=0;
            end else if(enable_rise) begin
                pending<=scan_keys; captured<=scan_keys; last_keys<=scan_keys;
            end else if(capture) begin
                pending<=scan_keys^last_keys; captured<=scan_keys; last_keys<=scan_keys;
            end else if(pushing || dropping) begin
                pending<=pending & (pending-1'b1);
            end
            if(pushing) fifo[wr_ptr]<={captured[low_idx],low_idx};
            if(fetch) fifo_q<=fifo[rd_ptr];
            case({pushing,fetch})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: begin end
            endcase
            if(pushing) wr_ptr<=wr_ptr+1'b1;
            if(fetch) rd_ptr<=rd_ptr+1'b1;
            case(state)
                IDLE: if(fetch) begin
                    send_index<=0; state<=LOAD;
                end
                LOAD: begin
                    message<={8'd44,tens_byte,ones_byte,8'd44,
                        fifo_q[4] ? 8'd49 : 8'd48,8'd13,8'd10};
                    tx_data<=8'd75;
                    state<=SEND;
                end
                SEND: if(tx_ready) begin
                    tx_data<=message[55:48];
                    message<={message[55:0],8'd0};
                    send_index<=send_index+1'b1;
                    if(send_index==4'd7) state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
