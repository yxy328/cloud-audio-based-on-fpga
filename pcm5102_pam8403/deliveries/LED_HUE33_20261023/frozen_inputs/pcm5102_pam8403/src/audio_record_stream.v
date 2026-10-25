`timescale 1ns/1ps
// One-way observer of the exact I2S frame sample. Never stalls audio and has
// no sample-playback input. Capture, RAM fetch, CRC and UART use separate
// enable slots on clk. CTS can pause bytes, never a byte already in flight.
module audio_record_stream #(
    parameter integer CLK_HZ=50000000, BAUD=2000000,
    parameter integer SAMPLE_DIV=1024, FIFO_DEPTH=1024, BLOCK_SAMPLES=256
)(
    input wire clk,resetn,sample_ce,
    input wire signed [15:0] sample,
    input wire start,stop,abort,
    input wire [15:0] session,
    input wire cts_n,
    output wire tx,busy,ready,
    output reg capturing,overflow
);
    localparam integer PW=$clog2(FIFO_DEPTH);
    localparam [31:0] CLOCK_VALUE=CLK_HZ;
    localparam [15:0] DIV_VALUE=SAMPLE_DIV;
    localparam [8:0] BLOCK_WORDS=BLOCK_SAMPLES;
    localparam integer UW=PW+1<9 ? 9 : PW+1;
    localparam IDLE=0,START_PACKET=1,WAIT_BLOCK=2,PREPARE=3,HEADER=4,META=5,
        FETCH=6,FETCH_WAIT=7,LOW_BYTE=8,HIGH_BYTE=9,CRC_LOW=10,CRC_HIGH=11,
        SEND=12,CRC_BITS=13,PACKET_DONE=14;
    localparam START_TYPE=1,DATA_TYPE=2,END_TYPE=3;
    reg cts_meta,cts_sync;
    always @(posedge clk)begin
        if(!resetn)begin cts_meta<=1;cts_sync<=1;end
        else begin cts_meta<=cts_n;cts_sync<=cts_meta;end
    end
    assign ready=!cts_sync;
    reg [3:0] state,continuation;
    reg [7:0] tx_byte;
    reg crc_enable;
    wire uart_ready;
    uart_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart(
        .clk(clk),.resetn(resetn && !abort),.rx(1'b1),.rx_ready(1'b1),
        .rx_data(),.rx_valid(),.rx_fault(),
        .tx(tx),.tx_data(tx_byte),.tx_valid(state==SEND && ready),.tx_ready(uart_ready));
    assign busy=state!=IDLE || capturing || !uart_ready;
    wire begin_record=start && !busy;
    (* syn_ramstyle="block_ram" *) reg [15:0] fifo[0:FIFO_DEPTH-1];
    reg [15:0] fifo_q,held_sample;
    reg [PW-1:0] wr,rd;
    reg [PW:0] used;
    wire [UW-1:0] used_extended=used;
    wire push=capturing && sample_ce && !stop && used<FIFO_DEPTH;
    wire pop=state==FETCH && used!=0;
    always @(posedge clk)begin
        if(resetn && !abort && push)fifo[wr]<=sample;
        if(pop)fifo_q<=fifo[rd];
    end
    reg [15:0] take_id,sequence;
    reg [31:0] sent_samples;
    reg [7:0] packet_type;
    reg [15:0] payload_length;
    reg [8:0] words_left;
    reg [127:0] header;
    reg [4:0] header_left;
    reg [2:0] meta_index;
    reg [15:0] crc;
    reg [3:0] crc_left;
    reg [7:0] meta_byte;
    always @*begin
        meta_byte=0;
        if(packet_type==START_TYPE)begin
            case(meta_index)
                0:meta_byte=CLOCK_VALUE[7:0];
                1:meta_byte=CLOCK_VALUE[15:8];
                2:meta_byte=CLOCK_VALUE[23:16];
                3:meta_byte=CLOCK_VALUE[31:24];
                4:meta_byte=DIV_VALUE[7:0];
                5:meta_byte=DIV_VALUE[15:8];
                6:meta_byte=16;
                7:meta_byte=1;
            endcase
        end else if(meta_index==0)meta_byte={7'd0,overflow};
    end
    task emit;
        input [7:0] value;
        input [3:0] next_state;
        input checked;
        begin tx_byte<=value;continuation<=next_state;crc_enable<=checked;state<=SEND;end
    endtask
    always @(posedge clk)begin
        if(!resetn || abort)begin
            state<=IDLE;continuation<=IDLE;capturing<=0;overflow<=0;
            wr<=0;rd<=0;used<=0;take_id<=0;sequence<=0;sent_samples<=0;
            packet_type<=0;payload_length<=0;words_left<=0;header<=0;
            header_left<=0;meta_index<=0;crc<=16'hffff;crc_left<=0;
            tx_byte<=0;crc_enable<=0;held_sample<=0;
        end else begin
            if(begin_record)begin
                // First sample is the next frame_ce after command acceptance.
                capturing<=1;overflow<=0;wr<=0;rd<=0;used<=0;
                take_id<=session;sequence<=0;sent_samples<=0;state<=START_PACKET;
            end else begin
                if(stop)capturing<=0;
                if(capturing && sample_ce && !stop && used==FIFO_DEPTH)begin
                    // End the take at the first missing sample. The queued
                    // prefix stays contiguous; END explicitly marks failure.
                    capturing<=0;overflow<=1;
                end
                if(push)wr<=wr+1'b1;
                if(pop)begin rd<=rd+1'b1;sent_samples<=sent_samples+1'b1;end
                case({push,pop})
                    2'b10:used<=used+1'b1;
                    2'b01:used<=used-1'b1;
                    default:begin end
                endcase
                case(state)
                    IDLE:begin end
                    START_PACKET:begin packet_type<=START_TYPE;payload_length<=8;state<=PREPARE;end
                    WAIT_BLOCK:begin
                        if(used>=BLOCK_SAMPLES || (!capturing && used!=0))begin
                            packet_type<=DATA_TYPE;
                            words_left<=used>=BLOCK_SAMPLES ? BLOCK_WORDS : used_extended[8:0];
                            payload_length<=used>=BLOCK_SAMPLES ? BLOCK_SAMPLES*2 : used*2;
                            state<=PREPARE;
                        end else if(!capturing)begin packet_type<=END_TYPE;payload_length<=4;state<=PREPARE;end
                    end
                    PREPARE:begin
                        // Little-endian header: FAR1,type,flags,length,seq,id,index.
                        header<={sent_samples,take_id,sequence,payload_length,
                            7'd0,overflow,packet_type,32'h31524146};
                        header_left<=16;meta_index<=0;crc<=16'hffff;state<=HEADER;
                    end
                    HEADER:begin
                        emit(header[7:0],header_left==1 ?
                            (packet_type==DATA_TYPE ? FETCH : META) : HEADER,1'b1);
                        header<=header>>8;header_left<=header_left-1'b1;
                    end
                    META:begin
                        emit(meta_byte,meta_index==(packet_type==START_TYPE ? 7 : 3) ? CRC_LOW : META,1'b1);
                        meta_index<=meta_index+1'b1;
                    end
                    FETCH:if(used!=0)state<=FETCH_WAIT;
                    FETCH_WAIT:begin held_sample<=fifo_q;state<=LOW_BYTE;end
                    LOW_BYTE:emit(held_sample[7:0],HIGH_BYTE,1'b1);
                    HIGH_BYTE:begin
                        emit(held_sample[15:8],words_left==1 ? CRC_LOW : FETCH,1'b1);
                        words_left<=words_left-1'b1;
                    end
                    CRC_LOW:emit(crc[7:0],CRC_HIGH,1'b0);
                    CRC_HIGH:emit(crc[15:8],PACKET_DONE,1'b0);
                    SEND:if(uart_ready && ready)begin
                        if(crc_enable)begin crc<=crc^{tx_byte,8'd0};crc_left<=8;state<=CRC_BITS;end
                        else state<=continuation;
                    end
                    CRC_BITS:begin
                        crc<=crc[15] ? (crc<<1)^16'h1021 : crc<<1;
                        crc_left<=crc_left-1'b1;
                        if(crc_left==1)state<=continuation;
                    end
                    PACKET_DONE:if(uart_ready)begin
                        sequence<=sequence+1'b1;
                        state<=packet_type==END_TYPE ? IDLE : WAIT_BLOCK;
                    end
                    default:state<=IDLE;
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(FIFO_DEPTH<2 || (FIFO_DEPTH&(FIFO_DEPTH-1))!=0)$fatal(1,"Recording FIFO must be a power of two");
        if(BLOCK_SAMPLES<1 || BLOCK_SAMPLES>256 || BLOCK_SAMPLES>FIFO_DEPTH)$fatal(1,"Invalid recording block");
    end
`endif
endmodule
