`timescale 1ns/1ps
// Final-mix PCM recorder for the dedicated 0x100000..0x7fbfff NOR partition.
// Two 0x37e000 slots preserve the last committed take. Recording is 16-bit
// mono at the I2S frame CE (50MHz/1024), capped at 30 seconds. A slot must be
// explicitly erased before capture; header commit is written only after a
// full data CRC readback. Download uses acknowledged FAR1 packets.
module audio_take_store #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer SAMPLE_DIVISOR=1024,
    parameter integer MAX_SECONDS=30,
    parameter integer HALF_CYCLES=5,
    parameter integer ACK_TIMEOUT_CYCLES=250_000_000,
    parameter integer EXTERNAL_SPI=0,
    parameter integer EXTERNAL_NOR=0
)(
    input wire clk,resetn,sample_ce,
    input wire signed [15:0] sample,
    input wire prepare,start,stop,abort,send,
    input wire [15:0] session,
    input wire ack_valid,
    input wire [15:0] ack_sequence,
    output reg [7:0] stream_data,
    output reg stream_valid,
    output wire stream_last,
    input wire stream_ready,
    output reg [3:0] status,
    output reg [3:0] error,
    output reg valid,prepared,capturing,overflow,
    output reg [20:0] sample_count,
    output wire [20:0] stored_samples,
    output wire [15:0] stored_generation,
    output wire busy,
    output wire cs_n,sck,mosi,
    input wire miso,
    output wire [60:0] spi_request,
    input wire [11:0] spi_response,
    output wire [52:0] nor_request,
    input wire [11:0] nor_response
);
    localparam [23:0] SLOT0=24'h100000,SLOT1=24'h47e000;
    localparam [23:0] PART_END=24'h7fc000;
    localparam integer MAX_SAMPLES=(CLK_HZ/SAMPLE_DIVISOR)*MAX_SECONDS+
        ((CLK_HZ%SAMPLE_DIVISOR)*MAX_SECONDS)/SAMPLE_DIVISOR;
    localparam integer ERASE_SECTORS=((MAX_SAMPLES*2+4095)/4096)+1;
    localparam BOOT_ID=0,BOOT_ID_WAIT=1,BOOT_H0=2,BOOT_H0_WAIT=3,
        BOOT_H0_EVAL=4,BOOT_H1=5,BOOT_H1_WAIT=6,BOOT_H1_EVAL=7,IDLE=8,
        ERASE_GO=9,ERASE_WAIT=10,RECORD=11,DRAIN=12,PAGE_GO=13,PAGE_WAIT=14,
        VERIFY_GO=15,VERIFY_WAIT=16,VERIFY_EVAL=17,HEADER_GO=18,HEADER_WAIT=19,
        COMMIT_GO=20,COMMIT_WAIT=21,DL_KICK=22,DL_START=23,DL_LOAD=24,
        DL_LOAD_WAIT=25,DL_PACKET=26,DL_ACK=27,DL_END=28,
        GUARD_GO=29,GUARD_WAIT=30,GUARD_EVAL=31,
        HEADER_CHECK=32,HEADER_CHECK_WAIT=33,HEADER_CHECK_EVAL=34,
        COMMIT_CHECK=35,COMMIT_CHECK_WAIT=36,BOOT_VALIDATE0=37,BOOT_VALIDATE1=38,BOOT_SELECT=39,GUARD_INIT=40;
    reg [5:0] state,return_state;
    reg op_start;
    reg [2:0] op_kind;
    reg [23:0] op_address;
    reg [9:0] op_length;
    reg [7:0] op_write_data;
    reg op_write_valid;
    wire op_write_ready;
    wire [7:0] op_read_data;
    wire op_read_valid,op_busy,op_done,op_error;
    assign nor_request={resetn,op_start,op_kind,op_address,5'd0,op_length,op_write_data,op_write_valid};
    generate if(EXTERNAL_NOR)begin: external_nor
        assign {op_error,op_done,op_read_valid,op_write_ready,op_read_data}=nor_response;
        assign op_busy=0;assign spi_request=0;assign cs_n=1;assign sck=0;assign mosi=0;
    end else begin: internal_nor
    audio_nor_operation #(.CLK_HZ(CLK_HZ),.HALF_CYCLES(HALF_CYCLES),
        .DATA_BASE(SLOT0),.DATA_END(PART_END),.EXTERNAL_SPI(EXTERNAL_SPI)) u_nor(
        .clk(clk),.resetn(resetn),.start(op_start),.kind(op_kind),.address(op_address),.length({5'd0,op_length}),
        .write_data(op_write_data),.write_valid(op_write_valid),.write_ready(op_write_ready),
        .read_data(op_read_data),.read_valid(op_read_valid),.busy(op_busy),.done(op_done),.error(op_error),
        .cs_n(cs_n),.sck(sck),.mosi(mosi),.miso(miso),.spi_request(spi_request),.spi_response(spi_response),.event_partition(1'b0));
    end endgenerate
    assign busy=state!=IDLE;
    function [23:0] slot_base;
        input which;
        begin slot_base=which ? SLOT1 : SLOT0;end
    endfunction
    function [31:0] crc32_byte;
        input [31:0] old;
        input [7:0] data;
        integer b;
        reg [31:0] value;
        begin
            value=old^{24'd0,data};
            for(b=0;b<8;b=b+1)value=value[0] ? (value>>1)^32'hedb88320 : value>>1;
            crc32_byte=value;
        end
    endfunction
    function [15:0] crc16_byte;
        input [15:0] old;
        input [7:0] data;
        reg [7:0] folded;
        begin
            folded=old[15:8]^data;
            folded=folded^(folded>>4);
            crc16_byte=(old<<8)^({8'd0,folded}<<12)^({8'd0,folded}<<5)^{8'd0,folded};
        end
    endfunction
    reg target_slot,active_slot,slot0_valid,slot1_valid;
    reg id_ok,abort_pending,guard_dirty,boot_scan;
    reg [23:0] guard_offset;
    reg [15:0] slot0_generation,slot1_generation;
    reg [20:0] slot0_samples,slot1_samples;
    reg [31:0] slot0_crc,slot1_crc,capture_crc,work_crc;
    // Slot descriptors cannot change during an ownership scan. Read them
    // directly instead of retaining a second copy for the guard.
    wire guard_owned=target_slot ? slot1_valid : slot0_valid;
    wire [21:0] guard_bytes=target_slot ? {slot1_samples,1'b0} : {slot0_samples,1'b0};
    wire [31:0] guard_expected_crc=target_slot ? slot1_crc : slot0_crc;
    reg [23:0] jedec;
    reg [15:0] header_generation;
    reg [31:0] header_samples,header_pcm_crc;
    reg [7:0] header_commit;
    reg header_bad;
    reg [5:0] header_index;
    reg [9:0] erase_index;
    // One 1024-word FIFO decouples sample capture from NOR page latency.
    (* syn_ramstyle="block_ram" *) reg [15:0] fifo [0:1023];
    reg [10:0] wr_pointer,rd_pointer;
    wire fifo_empty=wr_pointer==rd_pointer;
    wire fifo_full={~wr_pointer[10],wr_pointer[9:0]}==rd_pointer;
    wire [10:0] fifo_count=wr_pointer-rd_pointer;
    reg [15:0] fifo_q;
    always @(posedge clk)fifo_q<=fifo[rd_pointer[9:0]];
    reg [8:0] page_bytes,page_position;
    reg [23:0] data_address;
    reg stop_pending;
    reg [21:0] verify_remaining;

    // Download packet staging and acknowledgement state.
    (* syn_ramstyle="block_ram" *) reg [7:0] packet [0:511];
    reg [8:0] packet_read_address;
    reg [7:0] packet_q;
    reg stream_pause;
    always @(posedge clk)packet_q<=packet[packet_read_address];
    reg [9:0] load_count,payload_size;
    reg [15:0] packet_sequence,download_session;
    reg [20:0] packet_index;
    reg [21:0] download_remaining;
    reg [9:0] stream_position;
    reg [15:0] packet_crc;
    reg [1:0] packet_type;
    localparam integer ACK_BITS=$clog2(ACK_TIMEOUT_CYCLES+1);
    reg [ACK_BITS-1:0] ack_watchdog;
    assign stored_samples=!valid ? 21'd0 : active_slot ? slot1_samples : slot0_samples;
    assign stored_generation=!valid ? 16'd0 : active_slot ? slot1_generation : slot0_generation;
    wire [31:0] stored_crc=active_slot ? slot1_crc : slot0_crc;
    wire [31:0] stored_bytes={10'd0,stored_samples,1'b0};
    wire [31:0] capture_bytes={10'd0,sample_count,1'b0};
    wire [31:0] committed_crc=~capture_crc;
    assign stream_last=stream_valid && stream_position==17+payload_size;
    wire [15:0] generation_delta=slot1_generation-slot0_generation;
    wire [15:0] next_generation=stored_generation+1'b1;
    wire header_ok=!header_bad && header_samples>0 && header_samples<=MAX_SAMPLES && work_crc==32'hdebb20e3;
    reg [7:0] fixed_header_byte;
    always @*begin
        case(header_index)
            0:fixed_header_byte="F";1:fixed_header_byte="A";2:fixed_header_byte="T";3:fixed_header_byte="1";
            4:fixed_header_byte=1;5:fixed_header_byte=0;
            16:fixed_header_byte=CLK_HZ[7:0];17:fixed_header_byte=CLK_HZ[15:8];
            18:fixed_header_byte=CLK_HZ[23:16];19:fixed_header_byte=CLK_HZ[31:24];
            20:fixed_header_byte=SAMPLE_DIVISOR[7:0];21:fixed_header_byte=SAMPLE_DIVISOR[15:8];
            22:fixed_header_byte=16;23:fixed_header_byte=1;
            default:fixed_header_byte=8'hff;
        endcase
    end
    reg [7:0] metadata_byte;
    always @*begin
        case(header_index)
            0:metadata_byte="F";
            1:metadata_byte="A";
            2:metadata_byte="T";
            3:metadata_byte="1";
            4:metadata_byte=8'd1;
            5:metadata_byte=8'd0;
            6:metadata_byte=next_generation[7:0];
            7:metadata_byte=next_generation[15:8];
            8:metadata_byte=sample_count[7:0];
            9:metadata_byte=sample_count[15:8];
            10:metadata_byte={3'd0,sample_count[20:16]};
            11:metadata_byte=8'd0;
            12:metadata_byte=committed_crc[7:0];
            13:metadata_byte=committed_crc[15:8];
            14:metadata_byte=committed_crc[23:16];
            15:metadata_byte=committed_crc[31:24];
            16:metadata_byte=CLK_HZ[7:0];
            17:metadata_byte=CLK_HZ[15:8];
            18:metadata_byte=CLK_HZ[23:16];
            19:metadata_byte=CLK_HZ[31:24];
            20:metadata_byte=SAMPLE_DIVISOR[7:0];
            21:metadata_byte=SAMPLE_DIVISOR[15:8];
            22:metadata_byte=8'd16;
            23:metadata_byte=8'd1;
            24:metadata_byte=~work_crc[7:0];
            25:metadata_byte=~work_crc[15:8];
            26:metadata_byte=~work_crc[23:16];
            default:metadata_byte=~work_crc[31:24];
        endcase
    end
    reg [7:0] packet_header_byte;
    always @*begin
        case(stream_position)
            0:packet_header_byte="F";
            1:packet_header_byte="A";
            2:packet_header_byte="R";
            3:packet_header_byte="1";
            4:packet_header_byte={6'd0,packet_type};
            5:packet_header_byte=(packet_type==1 || packet_type==3 ? 8'd1 : 8'd0);
            6:packet_header_byte=payload_size[7:0];
            7:packet_header_byte={6'd0,payload_size[9:8]};
            8:packet_header_byte=packet_sequence[7:0];
            9:packet_header_byte=packet_sequence[15:8];
            10:packet_header_byte=download_session[7:0];
            11:packet_header_byte=download_session[15:8];
            12:packet_header_byte=packet_index[7:0];
            13:packet_header_byte=packet_index[15:8];
            14:packet_header_byte={3'd0,packet_index[20:16]};
            default:packet_header_byte=8'd0;
        endcase
    end
    reg [7:0] start_payload;
    always @*begin
        case(stream_position)
            16:start_payload=CLK_HZ[7:0];
            17:start_payload=CLK_HZ[15:8];
            18:start_payload=CLK_HZ[23:16];
            19:start_payload=CLK_HZ[31:24];
            20:start_payload=SAMPLE_DIVISOR[7:0];
            21:start_payload=SAMPLE_DIVISOR[15:8];
            22:start_payload=8'd16;
            23:start_payload=8'd1;
            24:start_payload=stored_samples[7:0];
            25:start_payload=stored_samples[15:8];
            26:start_payload={3'd0,stored_samples[20:16]};
            default:start_payload=8'd0;
        endcase
    end
    reg [7:0] end_payload;
    always @*begin
        case(stream_position)
            16:end_payload=stored_crc[7:0];
            17:end_payload=stored_crc[15:8];
            18:end_payload=stored_crc[23:16];
            default:end_payload=stored_crc[31:24];
        endcase
    end
    // These CRC users occupy disjoint phases. Time-share one byte updater
    // rather than instantiate separate XOR networks for all five registers.
    // The two bytes of a captured sample are handled on consecutive clocks.
    reg capture_crc_high_pending;
    reg [7:0] capture_crc_high;
    wire capture_crc_low=sample_ce && capturing && !fifo_full;
    wire [31:0] crc_source=(capture_crc_low || capture_crc_high_pending) ? capture_crc :
        work_crc;
    wire [7:0] crc_byte=capture_crc_low ? sample[7:0] : capture_crc_high_pending ? capture_crc_high :
        state==HEADER_WAIT ? metadata_byte : op_read_data;
    wire [31:0] crc_result=crc32_byte(crc_source,crc_byte);
    task request_op;
        input [2:0] kind;
        input [23:0] address;
        input [9:0] length;
        begin op_kind<=kind;op_address<=address;op_length<=length;op_start<=1;end
    endtask
    task fail;
        input [3:0] code;
        begin
            error<=code;status<=4'hf;capturing<=0;prepared<=0;stream_valid<=0;state<=IDLE;
            if(status==1)id_ok<=0;
        end
    endtask
    task begin_packet;
        input [1:0] kind;
        input [9:0] size;
        input [31:0] index;
        begin
            packet_type<=kind;payload_size<=size;packet_index<=index[20:0];
            stream_position<=0;packet_read_address<=0;stream_pause<=0;packet_crc<=16'hffff;stream_valid<=1;state<=DL_PACKET;
        end
    endtask
    integer i;
    always @*begin
        op_write_valid=0;op_write_data=0;
        if(state==PAGE_WAIT)begin
            op_write_valid=!fifo_empty;
            op_write_data=page_position[0] ? fifo_q[15:8] : fifo_q[7:0];
        end else if(state==HEADER_WAIT)begin op_write_valid=1;op_write_data=metadata_byte;end
        else if(state==COMMIT_WAIT)begin op_write_valid=1;op_write_data=0;end
        stream_data=0;
        if(stream_position<16)stream_data=packet_header_byte;
        else if(stream_position<16+payload_size)
            stream_data=packet_type==1 ? start_payload : packet_type==3 ? end_payload : packet_q;
        else if(stream_position==16+payload_size)stream_data=packet_crc[7:0];
        else stream_data=packet_crc[15:8];
    end
    always @(posedge clk)begin
        if(!resetn)begin
            state<=BOOT_ID;return_state<=0;op_start<=0;status<=1;error<=0;valid<=0;prepared<=0;capturing<=0;overflow<=0;
            sample_count<=0;target_slot<=0;active_slot<=0;
            slot0_valid<=0;slot1_valid<=0;slot0_generation<=0;slot1_generation<=0;slot0_samples<=0;slot1_samples<=0;
            slot0_crc<=0;slot1_crc<=0;capture_crc<=32'hffffffff;work_crc<=32'hffffffff;
            id_ok<=0;abort_pending<=0;guard_dirty<=0;guard_offset<=0;boot_scan<=0;
            header_index<=0;work_crc<=32'hffffffff;erase_index<=0;wr_pointer<=0;rd_pointer<=0;page_bytes<=0;page_position<=0;
            data_address<=0;stop_pending<=0;verify_remaining<=0;load_count<=0;payload_size<=0;
            packet_sequence<=0;download_session<=0;packet_index<=0;download_remaining<=0;stream_position<=0;
            packet_crc<=16'hffff;packet_type<=0;packet_read_address<=0;stream_pause<=0;ack_watchdog<=0;stream_valid<=0;
            capture_crc_high_pending<=0;capture_crc_high<=0;jedec<=0;header_generation<=0;header_samples<=0;header_pcm_crc<=0;header_commit<=0;header_bad<=0;
        end else begin
            op_start<=0;
            if(capture_crc_high_pending)begin capture_crc<=crc_result;capture_crc_high_pending<=0;end
            if(stop && capturing)begin capturing<=0;stop_pending<=1;status<=6;end
            if(abort && busy && status!=1)begin capturing<=0;abort_pending<=1;end
            if(state==DL_PACKET && stream_pause)begin stream_pause<=0;stream_valid<=1;end
            if(sample_ce && capturing)begin
                if(fifo_full)begin overflow<=1;capturing<=0;stop_pending<=1;end
                else begin
                    fifo[wr_pointer[9:0]]<=sample;wr_pointer<=wr_pointer+1'b1;sample_count<=sample_count+1'b1;
                    capture_crc<=crc_result;capture_crc_high<=sample[15:8];capture_crc_high_pending<=1;
                    if(sample_count==MAX_SAMPLES-1)begin capturing<=0;stop_pending<=1;status<=6;end
                end
            end
            if(op_read_valid)begin
                if(state==BOOT_ID_WAIT)jedec<={jedec[15:0],op_read_data};
                else if(state==BOOT_H0_WAIT || state==BOOT_H1_WAIT || state==HEADER_CHECK_WAIT)begin
                    // Validate constants and CRC while bytes arrive. Retain
                    // only semantic fields instead of a variable-write array.
                    if(header_index>=6 && header_index<=7)header_generation[header_index[0]*8 +: 8]<=op_read_data;
                    else if(header_index>=8 && header_index<=11)header_samples[header_index[1:0]*8 +: 8]<=op_read_data;
                    else if(header_index>=12 && header_index<=15)header_pcm_crc[header_index[1:0]*8 +: 8]<=op_read_data;
                    else if(header_index==32)header_commit<=op_read_data;
                    else if((header_index<24 || header_index>=28) && op_read_data!=fixed_header_byte)header_bad<=1;
                    // IEEE CRC32 of a message followed by its little-endian
                    // final CRC has this fixed unfinalized residue.
                    if(header_index<28)work_crc<=crc_result;
                    header_index<=header_index+1'b1;
                end
                else if(state==VERIFY_WAIT)begin work_crc<=crc_result;verify_remaining<=verify_remaining-1'b1;end
                else if(state==DL_LOAD_WAIT)begin packet[load_count]<=op_read_data;load_count<=load_count+1'b1;end
                else if(state==COMMIT_CHECK_WAIT)header_commit<=op_read_data;
                else if(state==GUARD_WAIT)begin
                    guard_offset<=guard_offset+1'b1;
                    if(guard_owned && guard_offset>=4096 && guard_offset<4096+guard_bytes)
                        work_crc<=crc_result;
                    else if(!(guard_owned && guard_offset<33) && op_read_data!=8'hff)guard_dirty<=1;
                end
            end
            if(op_write_ready && op_write_valid)begin
                if(state==PAGE_WAIT)begin
                    page_position<=page_position+1'b1;
                    if(page_position[0])rd_pointer<=rd_pointer+1'b1;
                end else if(state==HEADER_WAIT)begin
                    if(header_index<24)work_crc<=crc_result;
                    header_index<=header_index+1'b1;
                end
            end
            if(stream_valid && stream_ready)begin
                if(stream_position<16+payload_size)packet_crc<=crc16_byte(packet_crc,stream_data);
                if(stream_position==17+payload_size)begin
                    stream_valid<=0;ack_watchdog<=0;state<=DL_ACK;
                end else begin
                    stream_position<=stream_position+1'b1;
                    // The data packet buffer is a synchronous BSRAM. UART has
                    // thousands of fabric clocks between bytes; one explicit
                    // prefetch bubble prevents a 512:1 LUT read mux.
                    if(packet_type==2 && (stream_position==15 ||
                        (stream_position>=16 && stream_position<15+payload_size)))begin
                        stream_valid<=0;stream_pause<=1;
                        if(stream_position>=16)packet_read_address<=packet_read_address+1'b1;
                    end
                end
            end
            if(state==DL_ACK)ack_watchdog<=ack_watchdog+1'b1;
            case(state)
                BOOT_ID:begin header_index<=0;request_op(1,0,3);state<=BOOT_ID_WAIT;end
                BOOT_ID_WAIT:if(op_read_valid)header_index<=header_index+1'b1;
                    else if(op_done)begin
                        if(op_error || jedec!=24'hef4017)fail(1);
                        else begin id_ok<=1;state<=BOOT_H0;end
                    end
                BOOT_H0:begin header_index<=0;header_bad<=0;work_crc<=32'hffffffff;request_op(2,SLOT0,33);state<=BOOT_H0_WAIT;end
                BOOT_H0_WAIT:if(op_done)begin if(op_error)fail(6);else state<=BOOT_H0_EVAL;end
                BOOT_H0_EVAL:begin
                    slot0_valid<=header_ok && header_commit==0;
                    slot0_generation<=header_generation;slot0_samples<=header_samples[20:0];
                    slot0_crc<=header_pcm_crc;state<=BOOT_H1;
                end
                BOOT_H1:begin header_index<=0;header_bad<=0;work_crc<=32'hffffffff;request_op(2,SLOT1,33);state<=BOOT_H1_WAIT;end
                BOOT_H1_WAIT:if(op_done)begin if(op_error)fail(6);else state<=BOOT_H1_EVAL;end
                BOOT_H1_EVAL:begin
                    slot1_valid<=header_ok && header_commit==0;
                    slot1_generation<=header_generation;slot1_samples<=header_samples[20:0];
                    slot1_crc<=header_pcm_crc;
                    state<=BOOT_VALIDATE0;
                end
                BOOT_VALIDATE0,BOOT_VALIDATE1:begin
                    if(state==BOOT_VALIDATE0 ? slot0_valid : slot1_valid)begin
                        target_slot<=state==BOOT_VALIDATE1;boot_scan<=1;state<=GUARD_INIT;
                    end else state<=state==BOOT_VALIDATE0 ? BOOT_VALIDATE1 : BOOT_SELECT;
                end
                BOOT_SELECT:begin
                    boot_scan<=0;
                    if(slot0_valid || slot1_valid)begin
                        if(slot1_valid && (!slot0_valid || generation_delta<16'h8000))begin
                            active_slot<=1;valid<=1;
                        end else begin active_slot<=0;valid<=1;end
                    end
                    status<=0;state<=IDLE;
                end
                IDLE:begin
                    status<=error!=0 ? 4'hf : prepared ? 4'd5 : valid ? 4'd2 : 0;
                    abort_pending<=0;
                    if(abort)begin prepared<=0;capturing<=0;overflow<=0;end
                    else if(prepare)begin
                        if(!id_ok)fail(1);
                        else begin
                            target_slot<=valid ? !active_slot : 0;erase_index<=0;prepared<=0;error<=0;status<=3;
                            boot_scan<=0;state<=GUARD_INIT;
                        end
                    end else if(start)begin
                        if(!prepared)error<=2;
                        else begin
                            wr_pointer<=0;rd_pointer<=0;sample_count<=0;capture_crc<=32'hffffffff;overflow<=0;stop_pending<=0;
                            data_address<=slot_base(target_slot)+24'h1000;capturing<=1;prepared<=0;error<=0;status<=4;state<=RECORD;
                        end
                    end else if(send)begin
                        if(!valid)error<=3;
                        else begin download_session<=session;packet_sequence<=0;ack_watchdog<=0;error<=0;download_remaining<=stored_bytes[21:0];data_address<=slot_base(active_slot)+24'h1000;status<=8;state<=DL_KICK;end
                    end
                end
                GUARD_INIT:begin
                    guard_dirty<=0;guard_offset<=0;work_crc<=32'hffffffff;state<=GUARD_GO;
                end
                GUARD_GO:begin request_op(2,slot_base(target_slot)+guard_offset,512);state<=GUARD_WAIT;end
                GUARD_WAIT:if(op_done)begin
                    if(op_error)fail(6);
                    else if(!boot_scan && (abort_pending || abort))fail(12);
                    else if(guard_offset==ERASE_SECTORS*4096)state<=GUARD_EVAL;
                    else state<=GUARD_GO;
                end
                GUARD_EVAL:begin
                    if(boot_scan)begin
                        if(guard_dirty || ~work_crc!=guard_expected_crc)begin
                            if(target_slot)slot1_valid<=0;else slot0_valid<=0;
                        end
                        state<=target_slot ? BOOT_SELECT : BOOT_VALIDATE1;
                    end else if(guard_dirty || (guard_owned && ~work_crc!=guard_expected_crc))fail(13);
                    else begin
                        if(target_slot)slot1_valid<=0;else slot0_valid<=0;
                        state<=ERASE_GO;
                    end
                end
                ERASE_GO:begin request_op(3,slot_base(target_slot)+{erase_index,12'd0},0);state<=ERASE_WAIT;end
                ERASE_WAIT:if(op_done)begin
                    if(op_error)fail(4);
                    else if(abort_pending || abort)fail(12);
                    else if(erase_index==ERASE_SECTORS-1)begin prepared<=1;status<=5;state<=IDLE;end
                    else begin erase_index<=erase_index+1'b1;state<=ERASE_GO;end
                end
                RECORD:begin
                    if(abort || abort_pending)fail(12);
                    else if(stop)begin capturing<=0;stop_pending<=1;status<=6;state<=DRAIN;end
                    else if(!capturing)state<=DRAIN;
                    else if(fifo_count>=128)begin page_bytes<=256;page_position<=0;state<=PAGE_GO;return_state<=RECORD;end
                end
                DRAIN:begin
                    if(abort_pending || abort)fail(12);
                    else if(overflow)fail(15);
                    else if(sample_count==0)fail(14);
                    else if(fifo_empty)begin work_crc<=32'hffffffff;verify_remaining<=capture_bytes[21:0];data_address<=slot_base(target_slot)+24'h1000;state<=VERIFY_GO;end
                    else begin
                        page_bytes<=fifo_count>=128 ? 256 : {fifo_count[7:0],1'b0};
                        page_position<=0;state<=PAGE_GO;return_state<=DRAIN;
                    end
                end
                PAGE_GO:begin request_op(4,data_address,page_bytes);state<=PAGE_WAIT;end
                PAGE_WAIT:if(op_done)begin
                    if(op_error)fail(5);else begin data_address<=data_address+page_bytes;state<=return_state;end
                end
                VERIFY_GO:begin
                    if(verify_remaining==0)state<=VERIFY_EVAL;
                    else begin op_length<=verify_remaining>512 ? 512 : verify_remaining[9:0];request_op(2,data_address,verify_remaining>512 ? 512 : verify_remaining[9:0]);state<=VERIFY_WAIT;end
                end
                VERIFY_WAIT:if(op_done)begin if(op_error)fail(6);else begin data_address<=data_address+op_length;state<=VERIFY_GO;end end
                VERIFY_EVAL:begin
                    if((~work_crc)!=committed_crc)fail(7);
                    else if(abort_pending || abort)fail(12);
                    else begin header_index<=0;work_crc<=32'hffffffff;state<=HEADER_GO;end
                end
                HEADER_GO:begin request_op(4,slot_base(target_slot),28);state<=HEADER_WAIT;end
                HEADER_WAIT:if(op_done)begin if(op_error)fail(8);else state<=HEADER_CHECK;end
                HEADER_CHECK:begin header_index<=0;header_bad<=0;work_crc<=32'hffffffff;request_op(2,slot_base(target_slot),33);state<=HEADER_CHECK_WAIT;end
                HEADER_CHECK_WAIT:if(op_done)begin if(op_error)fail(8);else state<=HEADER_CHECK_EVAL;end
                HEADER_CHECK_EVAL:begin
                    if(!header_ok || header_commit!=8'hff || header_samples!=sample_count ||
                        header_generation!=next_generation ||
                        header_pcm_crc!=committed_crc)fail(8);
                    else if(abort_pending || abort)fail(12);
                    else state<=COMMIT_GO;
                end
                COMMIT_GO:begin request_op(4,slot_base(target_slot)+32,1);state<=COMMIT_WAIT;end
                COMMIT_WAIT:if(op_done)begin
                    if(op_error)fail(9);else state<=COMMIT_CHECK;
                end
                COMMIT_CHECK:begin request_op(2,slot_base(target_slot)+32,1);state<=COMMIT_CHECK_WAIT;end
                COMMIT_CHECK_WAIT:if(op_done)begin
                    if(op_error || header_commit!=0)fail(9);else begin
                        active_slot<=target_slot;valid<=1;prepared<=0;status<=2;state<=IDLE;
                        if(target_slot)begin slot1_valid<=1;slot1_generation<=next_generation;slot1_samples<=sample_count;slot1_crc<=committed_crc;end
                        else begin slot0_valid<=1;slot0_generation<=next_generation;slot0_samples<=sample_count;slot0_crc<=committed_crc;end
                    end
                end
                DL_KICK:begin
                    ack_watchdog<=ack_watchdog+1'b1;
                    if(abort)state<=IDLE;
                    else if(ack_valid && ack_sequence==16'hffff)begin packet_index<=0;begin_packet(1,12,0);end
                    else if(ack_watchdog>=ACK_TIMEOUT_CYCLES)begin error<=11;status<=2;state<=IDLE;end
                end
                DL_START:begin_packet(1,12,0);
                DL_LOAD:begin
                    load_count<=0;payload_size<=download_remaining>512 ? 512 : download_remaining[9:0];
                    request_op(2,data_address,download_remaining>512 ? 512 : download_remaining[9:0]);state<=DL_LOAD_WAIT;
                end
                DL_LOAD_WAIT:if(op_done)begin if(op_error)fail(10);else begin packet_index<=(stored_bytes-download_remaining)>>1;begin_packet(2,payload_size,(stored_bytes-download_remaining)>>1);end end
                // Never cut a packet: the UART arbiter releases ownership only
                // on the last byte. Abort is acted on at the following ACK boundary.
                DL_PACKET:begin end
                DL_ACK:begin
                    if(abort || abort_pending)state<=IDLE;
                    else if(ack_watchdog>=ACK_TIMEOUT_CYCLES)begin error<=11;status<=2;state<=IDLE;end
                    else if(ack_valid && ack_sequence==packet_sequence)begin
                        if(packet_type==3)begin status<=2;state<=IDLE;end
                        else if(packet_type==1)begin packet_sequence<=packet_sequence+1'b1;state<=DL_LOAD;end
                        else begin
                            data_address<=data_address+payload_size;download_remaining<=download_remaining-payload_size;packet_sequence<=packet_sequence+1'b1;
                            state<=download_remaining==payload_size ? DL_END : DL_LOAD;
                        end
                    end
                end
                DL_END:begin packet_index<=stored_samples;begin_packet(3,4,stored_samples);end
                default:state<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(MAX_SAMPLES<1 || MAX_SAMPLES>21'h1fffff || SAMPLE_DIVISOR>65535 || ERASE_SECTORS*4096>24'h37e000)$fatal(1,"Audio slot geometry invalid");
    end
`endif
endmodule
