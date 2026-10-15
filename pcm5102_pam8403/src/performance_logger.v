`timescale 1ns/1ps
// Timestamped state snapshots, independent of UART throughput and audio enables.
// FIFO_DEPTH must be a power of two >=2. No RAM reset: pointers invalidate it.
module performance_logger #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer FIFO_DEPTH=64
) (
    input wire clk, resetn, start, stop,
    input wire [55:0] note_map,
    input wire [6:0] touch_keys,
    input wire pressure_mode,
    input wire [15:0] volume_gain, pitch_ratio,
    output wire recording,
    output wire [7:0] tx_data,
    output wire tx_valid, tx_last,
    input wire tx_ready,
    output reg [31:0] dropped
);
    localparam integer PTR_W=$clog2(FIFO_DEPTH);
    localparam integer MS_TICKS=(CLK_HZ/1000 < 1) ? 1 : CLK_HZ/1000;
    localparam IDLE=0, FETCH_WAIT=1, EVENT=2, CONVERT=3, DIGITS=4, SEND=5,
        APPEND_FIELDS=6, ALIGN=7;
    reg [2:0] state;
    reg capturing, map_pending, ending, final_pending;
    reg [55:0] map_snapshot;
    reg [31:0] ms_div, elapsed_ms, reported_dropped;
    reg [4:0] pressure_ms;
    reg [6:0] last_keys;
    reg last_mode;
    reg [15:0] last_gain, last_ratio;
    reg [71:0] fifo [0:FIFO_DEPTH-1];
    reg [71:0] fifo_q;
    reg [71:0] held;
    reg [71:0] final_event;
    reg fetch_final;
    reg [PTR_W-1:0] wr_ptr, rd_ptr;
    reg [PTR_W:0] count;
    wire ms_tick=ms_div==MS_TICKS-1;
    wire keys_changed=touch_keys!=last_keys;
    wire expression_changed=pressure_mode!=last_mode || volume_gain!=last_gain || pitch_ratio!=last_ratio;
    wire accept_start=start && !recording;
    wire capture=accept_start || (capturing && !stop && (keys_changed ||
        (ms_tick && pressure_ms==19 && expression_changed)));
    wire fetch=resetn && state==IDLE && !map_pending && dropped==reported_dropped && count!=0;
    // Avoid implementation-specific RAM read-during-write behavior at full.
    wire push=resetn && capture && count<FIFO_DEPTH;
    wire [31:0] event_time=elapsed_ms+((capturing && ms_tick) ? 32'd1 : 32'd0);
    reg [511:0] message;
    reg [6:0] length, send_index;
    reg [5:0] align_remaining;
    reg [31:0] binary_value;
    reg [39:0] bcd, adjusted_bcd;
    reg [5:0] convert_count;
    reg [3:0] digit_index;
    reg leading;
    reg [2:0] field;
    integer i;
    assign recording=capturing || map_pending || ending || final_pending || count!=0 || state!=IDLE;
    assign tx_valid=state==SEND;
    assign tx_data=message[511:504];
    assign tx_last=state==SEND && send_index==length-1;
    // Keep the synchronous RAM output free of reset and final-event bypasses,
    // so inference can retain a single block-RAM read port.
    always @(posedge clk) begin
        if(push)
            fifo[wr_ptr]<={accept_start ? 32'd0 : event_time,touch_keys,pressure_mode,volume_gain,pitch_ratio};
        if(fetch)
            fifo_q<=fifo[rd_ptr];
    end
    function [7:0] hexchar;
        input [3:0] value;
        begin hexchar=(value<10) ? 8'd48+value : 8'd65+value-10; end
    endfunction
    function [7:0] tens;
        input [7:0] note;
        begin tens=(note<70) ? "6" : "7"; end
    endfunction
    function [7:0] ones;
        input [7:0] note;
        begin ones=8'd48+((note<70) ? note-8'd60 : note-8'd70); end
    endfunction
    // Shared iterative binary-to-decimal converter; no combinational divider.
    always @* begin
        adjusted_bcd=bcd;
        for(i=0;i<10;i=i+1)
            if(bcd[i*4 +: 4]>=5) adjusted_bcd[i*4 +: 4]=bcd[i*4 +: 4]+4'd3;
    end
    task number;
        input [31:0] value;
        begin binary_value<=value; bcd<=0; convert_count<=0; state<=CONVERT; end
    endtask
    task append;
        input [7:0] ch;
        begin message<={message[503:0],ch}; length<=length+1'b1; end
    endtask
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; capturing<=0; map_pending<=0; ending<=0; final_pending<=0; map_snapshot<=0;
            ms_div<=0; elapsed_ms<=0; pressure_ms<=0; last_keys<=0; last_mode<=0;
            last_gain<=0; last_ratio<=0; wr_ptr<=0; rd_ptr<=0; count<=0; held<=0; final_event<=0;
            dropped<=0; reported_dropped<=0; message<=0; length<=0; send_index<=0;
            fetch_final<=0; align_remaining<=0;
            binary_value<=0; bcd<=0; convert_count<=0; digit_index<=0; leading<=1; field<=0;
        end else begin
            if(accept_start) begin
                capturing<=1; map_pending<=1; map_snapshot<=note_map;
                ms_div<=0; elapsed_ms<=0; pressure_ms<=0;
                dropped<=0; reported_dropped<=0;
            end else if(capturing) begin
                if(ms_tick) begin
                    ms_div<=0; elapsed_ms<=elapsed_ms+1'b1;
                    pressure_ms<=(pressure_ms==19) ? 0 : pressure_ms+1'b1;
                end else ms_div<=ms_div+1'b1;
                if(stop) begin
                    capturing<=0; ending<=1; final_pending<=1;
                    final_event<={event_time,touch_keys,pressure_mode,volume_gain,pitch_ratio};
                end
            end
            if(capture) begin
                last_keys<=touch_keys; last_mode<=pressure_mode;
                last_gain<=volume_gain; last_ratio<=pitch_ratio;
                if(push) begin
                    wr_ptr<=wr_ptr+1'b1;
                end else if(dropped!=32'hffffffff) dropped<=dropped+1'b1;
            end
            if(fetch) rd_ptr<=rd_ptr+1'b1;
            case({push,fetch})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: begin end
            endcase
            case(state)
                IDLE: begin
                    send_index<=0;
                    if(map_pending) begin
                        message<={"MAP,",tens(map_snapshot[7:0]),ones(map_snapshot[7:0]),",",
                            tens(map_snapshot[15:8]),ones(map_snapshot[15:8]),",",
                            tens(map_snapshot[23:16]),ones(map_snapshot[23:16]),",",
                            tens(map_snapshot[31:24]),ones(map_snapshot[31:24]),",",
                            tens(map_snapshot[39:32]),ones(map_snapshot[39:32]),",",
                            tens(map_snapshot[47:40]),ones(map_snapshot[47:40]),",",
                            tens(map_snapshot[55:48]),ones(map_snapshot[55:48]),8'd13,8'd10} << (38*8);
                        length<=26; map_pending<=0; state<=SEND;
                    end else if(dropped!=reported_dropped) begin
                        message<="ERR,REC_OVERFLOW,"; length<=17; field<=3;
                        reported_dropped<=dropped; number(dropped);
                    end else if(fetch) begin fetch_final<=0; state<=FETCH_WAIT; end
                    else if(final_pending) begin
                        fetch_final<=1; final_pending<=0; state<=FETCH_WAIT;
                    end
                    else if(ending && !capturing) begin
                        message<="REC_END,"; length<=8; field<=3;
                        ending<=0; number(dropped);
                    end
                end
                FETCH_WAIT: begin
                    held<=fetch_final ? final_event : fifo_q;
                    fetch_final<=0; state<=EVENT;
                end
                EVENT: begin message<="EVT,"; length<=4; field<=0; number(held[71:40]); end
                CONVERT: begin
                    bcd<={adjusted_bcd[38:0],binary_value[31]};
                    binary_value<={binary_value[30:0],1'b0};
                    if(convert_count==31) begin digit_index<=9; leading<=1; state<=DIGITS; end
                    else convert_count<=convert_count+1'b1;
                end
                DIGITS: begin
                    if(!leading || bcd[digit_index*4 +: 4]!=0 || digit_index==0) begin
                        append(8'd48+{4'd0,bcd[digit_index*4 +: 4]}); leading<=0;
                    end
                    if(digit_index!=0) digit_index<=digit_index-1'b1;
                    else begin
                        // The final digit is appended on this edge; delimiters
                        // are built next cycle to avoid competing assignments.
                        state<=APPEND_FIELDS;
                    end
                end
                APPEND_FIELDS: begin
                    if(field==0) begin
                        message<={message[463:0],8'd44,hexchar({1'b0,held[39:37]}),hexchar(held[36:33]),
                            8'd44,8'd48+{7'd0,held[32]},8'd44}; length<=length+6;
                        field<=1; number({16'd0,held[31:16]});
                    end else if(field==1) begin
                        append(","); field<=2; number({16'd0,held[15:0]});
                    end else begin
                        message<={message[495:0],8'd13,8'd10};
                        length<=length+2; align_remaining<=62-length; state<=ALIGN;
                    end
                end
                // UART takes thousands of fabric clocks per byte. Align one
                // byte per clock instead of building a 512-bit barrel shifter.
                ALIGN: begin
                    if(align_remaining==0) begin send_index<=0; state<=SEND; end
                    else begin
                        message<={message[503:0],8'd0};
                        align_remaining<=align_remaining-1'b1;
                    end
                end
                SEND: if(tx_ready) begin
                    message<={message[503:0],8'd0}; send_index<=send_index+1'b1;
                    if(tx_last) state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
