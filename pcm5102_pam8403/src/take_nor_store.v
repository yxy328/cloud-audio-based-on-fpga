`timescale 1ns/1ps
// W25Q64 (JEDEC EF4017), two 8KiB slots at 7FC000/7FE000.
// Read-only ownership scan precedes all WREN commands. Unknown contents are
// locked. A commit byte is programmed LAST, after body and header readback.
// Header: FPT1, generation:u16, count+full:u16, duration_ms:u24, crc32:u32,
// commit:u8. Integers and 48-bit timeline words are little endian. CRC32
// covers header bytes 0..10 followed by count*6 body bytes at offset 256.
// Count word bit15 retains the capacity-full flag; low15 bits are the count.
// count=0 is a persistent deletion tombstone, ordered like any other take.
module take_nor_store #(
    parameter integer CLK_HZ=50000000,DEPTH=1024,HALF_CYCLES=5,EXTERNAL_SPI=0,EXTERNAL_NOR=0
)(
    input wire clk,resetn,save,delete_take,take_full,
    input wire [$clog2(DEPTH):0] count,
    input wire [23:0] duration,
    output reg busy,boot_done,valid,done,ok,loaded_full,
    output reg [3:0] error,
    output reg [$clog2(DEPTH):0] loaded_count,
    output reg [23:0] loaded_duration,
    output reg ram_we,
    output reg [$clog2(DEPTH)-1:0] ram_address,
    output reg [47:0] ram_data,
    input wire [47:0] ram_q,
    output wire cs_n,sck,mosi,
    input wire miso,
    output wire [60:0] spi_request,
    input wire [11:0] spi_response,
    output wire [52:0] nor_request,
    input wire [11:0] nor_response
);
    localparam AW=$clog2(DEPTH);
    localparam START=0,ID_WAIT=1,SCAN_BEGIN=2,SCAN_WAIT=3,SCAN_EVAL=4,SELECT=5,
        LOAD_META=6,LOAD_BEGIN=7,LOAD_WAIT=8,IDLE=9,META=10,META_DONE=11,
        WREN_BEGIN=12,WREN_WAIT=13,WEL_WAIT=14,OP_WAIT=15,POLL_BEGIN=16,POLL_WAIT=17,
        BODY_VERIFY_BEGIN=18,BODY_VERIFY_WAIT=19,HEADER_BEGIN=20,HEADER_VERIFY_WAIT=21,
        COMMIT_VERIFY_WAIT=22,FINISH=23,SELECT_HEADER_WAIT=24,SELECT_APPLY=25;
    reg [4:0] state;
    reg go,authorized,spi_address_valid,writing,abort_spi;
    reg [7:0] opcode,write_data;
    reg [13:0] spi_low;reg spi_region;
    wire [23:0] spi_address={spi_region ? 10'h1ff : 10'd0,spi_low};
    reg [14:0] length;
    wire write_ready,read_valid,spi_done,raw_spi_done,spi_error;
    reg [7:0] done_delay;
    // The serial CRC needs eight fabric clocks after each received byte.
    // SPI byte spacing is >=48 clocks; delay only transaction completion.
    assign spi_done=done_delay[7];
    always @(posedge clk)
        if(!resetn || abort_spi)done_delay<=0;
        else done_delay<={done_delay[6:0],raw_spi_done};
    wire [7:0] read_data;
    reg [1:0] operation,fetch_delay;
    wire write_valid=state==OP_WAIT && operation!=0 && (operation!=1 || fetch_delay==0);
    assign spi_request={resetn && !abort_spi,go,authorized,opcode,spi_address,spi_address_valid,writing,length,write_data,write_valid};
    wire [2:0] nor_kind=opcode==8'h9f ? 3'd1 : opcode==8'h03 ? 3'd2 : opcode==8'h20 ? 3'd3 : 3'd4;
    assign nor_request={resetn && !abort_spi,go,nor_kind,spi_address,length,write_data,write_valid};
    generate if(EXTERNAL_NOR)begin: external_nor
        assign {spi_error,raw_spi_done,read_valid,write_ready,read_data}=nor_response;
        assign cs_n=1;assign sck=0;assign mosi=0;
    end else if(EXTERNAL_SPI)begin: external_spi
        assign {spi_error,raw_spi_done,read_valid,write_ready,read_data}=spi_response;
        assign cs_n=1;assign sck=0;assign mosi=0;
    end else begin: internal_spi
    take_spi_transaction #(.HALF_CYCLES(HALF_CYCLES)) u_spi(
        .clk(clk),.resetn(resetn && !abort_spi),.go(go),.authorized(authorized),
        .opcode(opcode),.address(spi_address),.address_valid(spi_address_valid),
        .writing(writing),.length(length),.write_data(write_data),.write_valid(write_valid),
        .write_ready(write_ready),.read_data(read_data),.read_valid(read_valid),
        .done(raw_spi_done),.error(spi_error),.cs_n(cs_n),.sck(sck),.mosi(mosi),.miso(miso),.event_partition(1'b1));
    end endgenerate
    reg [23:0] jedec;
    reg [7:0] status_byte;
    reg scan_slot,active_slot,target_slot,active_present;
    reg [1:0] owned,candidate;
    reg all_blank,padding_blank;
    reg [13:0] offset;
    reg [127:0] header;
    reg [15:0] generation0;
    reg [31:0] crc,meta_crc;
    reg verify_error;
    reg [3:0] crc_bits;
    reg [15:0] generation,take_count;
    reg [3:0] meta_index,header_index;
    reg [2:0] byte_index;
    reg [47:0] word_shift;
    reg [12:0] remaining;
    reg [8:0] page_size;
    reg erase_second,save_active;
    reg [13:0] operation_offset;
    wire [23:0] operation_address={10'h1ff,operation_offset};
    localparam integer WATCHDOG_BITS=$clog2(CLK_HZ*2+1);
    reg [WATCHDOG_BITS-1:0] watchdog;
    wire [12:0] scan_bytes=({header[58:48],2'b0}+{1'b0,header[58:48],1'b0});
    wire [12:0] body_bytes=({take_count[10:0],2'b0}+{1'b0,take_count[10:0],1'b0});
    wire header_shape=header[31:0]==32'h31545046 && header[62:48]<=DEPTH &&
        (header[62:48]!=0 || (header[87:64]==0 && !header[63]));
    wire checksum_ok=(~crc)==header[119:88];
    wire header_owned=header_shape && checksum_ok && padding_blank &&
        (header[127:120]==8'hff || header[127:120]==0);
    // Data validity and permission to erase are different: foreign padding
    // locks this slot against future erase, but must not resurrect an older
    // recording when the newest committed entry is a deletion tombstone.
    wire header_valid=header_shape && checksum_ok && header[127:120]==0;
    wire [15:0] generation_difference=header[47:32]-generation0;
    wire choose1=candidate[1] && (!candidate[0] || !generation_difference[15]);
    wire [3:0] selected_header_index=(state==META || state==LOAD_META) ? meta_index : header_index;
    wire [7:0] selected_header_byte=header[selected_header_index*8 +: 8];
    wire [7:0] header_byte=operation==3 && header_index==15 ? 8'd0 : selected_header_byte;
    function [23:0] base;
        input slot;
        begin base=slot ? 24'h7fe000 : 24'h7fc000;end
    endfunction
    wire [7:0] crc_input=(state==META || state==LOAD_META) ? selected_header_byte :
        (state==OP_WAIT && operation==1) ? write_data : read_data;
    wire crc_start=((state==META || state==LOAD_META) && crc_bits==0) ||
        (read_valid && (state==LOAD_WAIT || state==BODY_VERIFY_WAIT ||
            (state==SCAN_WAIT && (offset<11 || (offset>=256 && offset<256+scan_bytes))))) ||
        (write_ready && write_valid && operation==1);
    task launch;
        input [7:0] op;
        input [23:0] addr;
        input address_enable,is_write;
        input [14:0] size;
        input [4:0] next;
        begin
            opcode<=op;spi_low<=addr[13:0];spi_region<=|addr[23:14];spi_address_valid<=address_enable;
            writing<=is_write;length<=size;go<=1;state<=next;
        end
    endtask
    task failure;
        input [3:0] code;
        begin
            error<=code;ok<=0;busy<=0;abort_spi<=1;authorized<=0;save_active<=0;
            if(save_active)done<=1;else boot_done<=1;
            state<=IDLE;
        end
    endtask
    task finish_operation;
        begin
            case(operation)
                        0:if(!erase_second)begin
                            erase_second<=1;operation_offset<={target_slot,13'd0}+14'd4096;state<=WREN_BEGIN;
                        end else if(take_count==0)begin
                            header[119:88]<=~meta_crc;state<=HEADER_BEGIN;
                        end else begin
                            operation<=1;operation_offset<={target_slot,13'd0}+14'd256;
                            remaining<=body_bytes;page_size<=body_bytes>256 ? 9'd256 : body_bytes[8:0];
                            ram_address<=0;byte_index<=0;fetch_delay<=3;crc<=meta_crc;state<=WREN_BEGIN;
                        end
                        1:if(remaining!=0)begin
                            operation_offset<=operation_offset+14'd256;
                            page_size<=remaining>256 ? 9'd256 : remaining[8:0];state<=WREN_BEGIN;
                        end else begin header[119:88]<=~crc;state<=BODY_VERIFY_BEGIN;end
                        2:begin
                            header_index<=0;verify_error<=0;
                            launch(8'h03,base(target_slot),1,0,16,HEADER_VERIFY_WAIT);
                        end
                        3:begin
                            header_index<=0;verify_error<=0;
                            launch(8'h03,base(target_slot),1,0,16,COMMIT_VERIFY_WAIT);
                        end
                    endcase
        end
    endtask
    always @*begin
        case(operation)
            1:write_data=word_shift[7:0];
            2:write_data=header_byte;
            default:write_data=0;
        endcase
    end
    always @(posedge clk)begin
        if(!resetn)begin
            state<=START;busy<=1;boot_done<=0;valid<=0;done<=0;ok<=0;error<=0;
            loaded_count<=0;loaded_duration<=0;loaded_full<=0;ram_we<=0;ram_address<=0;ram_data<=0;
            go<=0;authorized<=0;spi_address_valid<=0;writing<=0;abort_spi<=0;
            opcode<=0;spi_low<=0;spi_region<=0;length<=0;jedec<=0;status_byte<=0;scan_slot<=0;active_slot<=0;
            target_slot<=0;active_present<=0;owned<=0;candidate<=0;all_blank<=1;padding_blank<=1;offset<=0;
            header<=0;generation0<=0;crc<=32'hffffffff;meta_crc<=0;crc_bits<=0;
            verify_error<=0;generation<=0;take_count<=0;meta_index<=0;
            header_index<=0;byte_index<=0;word_shift<=0;remaining<=0;page_size<=0;
            operation<=0;fetch_delay<=0;erase_second<=0;save_active<=0;operation_offset<=0;watchdog<=0;
        end else begin
            go<=0;abort_spi<=0;boot_done<=0;done<=0;ram_we<=0;
            if(crc_start)begin crc<=crc ^ {24'd0,crc_input};crc_bits<=8;end
            else if(crc_bits!=0)begin
                crc<=crc[0] ? (crc>>1)^32'hedb88320 : crc>>1;
                crc_bits<=crc_bits-1'b1;
            end
            if(busy)watchdog<=watchdog+1'b1;else watchdog<=0;
            if(fetch_delay!=0)begin
                fetch_delay<=fetch_delay-1'b1;
                if(fetch_delay==1)word_shift<=ram_q;
            end
            if(read_valid)begin
                case(state)
                    ID_WAIT:jedec<={jedec[15:0],read_data};
                    SCAN_WAIT:begin
                        if(read_data!=8'hff)all_blank<=0;
                        // Header recognition never grants ownership of
                        // unrelated data in the rest of an erase slot.
                        if(read_data!=8'hff && offset>=16 &&
                            (offset<256 || offset>=256+scan_bytes))padding_blank<=0;
                        if(offset<16)header<={read_data,header[127:8]};
                        offset<=offset+1'b1;
                    end
                    SELECT_HEADER_WAIT:header<={read_data,header[127:8]};
                    LOAD_WAIT:begin
                        word_shift<={read_data,word_shift[47:8]};
                        if(byte_index==5)begin
                            ram_data<={read_data,word_shift[47:8]};ram_we<=1;
                            byte_index<=0;
                        end else byte_index<=byte_index+1'b1;
                    end
                    WEL_WAIT,POLL_WAIT:status_byte<=read_data;
                    HEADER_VERIFY_WAIT,COMMIT_VERIFY_WAIT:begin
                        if(read_data!=header_byte)verify_error<=1;
                        header_index<=header_index+1'b1;
                    end
                    default:begin end
                endcase
            end
            // RAM write address advances one cycle AFTER its write pulse.
            if(ram_we)ram_address<=ram_address+1'b1;
            if(write_ready && write_valid)begin
                if(operation==1)begin
                    remaining<=remaining-1'b1;
                    word_shift<=word_shift>>8;
                    if(byte_index==5)begin
                        byte_index<=0;ram_address<=ram_address+1'b1;fetch_delay<=3;
                    end else byte_index<=byte_index+1'b1;
                end else if(operation==2)header_index<=header_index+1'b1;
            end
            case(state)
                START:launch(8'h9f,0,0,0,3,ID_WAIT);
                ID_WAIT:if(spi_done)begin
                    if(jedec!=24'hef4017)failure(8);
                    else begin scan_slot<=0;state<=SCAN_BEGIN;end
                end
                SCAN_BEGIN:begin
                    offset<=0;header<=0;crc<=32'hffffffff;all_blank<=1;padding_blank<=1;
                    launch(8'h03,base(scan_slot),1,0,8192,SCAN_WAIT);
                end
                SCAN_WAIT:if(spi_done)state<=SCAN_EVAL;
                SCAN_EVAL:begin
                    owned[scan_slot]<=all_blank || header_owned;candidate[scan_slot]<=header_valid;
                    if(!scan_slot)begin generation0<=header[47:32];scan_slot<=1;state<=SCAN_BEGIN;end
                    else state<=SELECT;
                end
                SELECT:begin
                    if(candidate!=0)begin
                        active_present<=1;active_slot<=choose1;
                        // Keep only slot zero's generation while comparing.
                        // Its full header can be reread once if it wins.
                        if(choose1)state<=SELECT_APPLY;
                        else launch(8'h03,base(1'b0),1,0,16,SELECT_HEADER_WAIT);
                    end else begin
                        busy<=0;boot_done<=1;state<=IDLE;
                        if(owned!=2'b11)error<=8;
                    end
                end
                SELECT_HEADER_WAIT:if(spi_done)state<=SELECT_APPLY;
                SELECT_APPLY:begin
                    if(!header_shape || header[127:120]!=0)failure(10);
                    else begin
                        generation<=header[47:32];take_count<={1'b0,header[62:48]};
                        loaded_count<=header[48 +: AW+1];
                        loaded_duration<=header[87:64];loaded_full<=header[63];
                        meta_index<=0;crc<=32'hffffffff;state<=LOAD_META;
                    end
                end
                LOAD_META:if(crc_bits==1)begin
                    if(meta_index==10)state<=LOAD_BEGIN;else meta_index<=meta_index+1'b1;
                end
                LOAD_BEGIN:begin
                    if(take_count==0)begin
                        if((~crc)!=header[119:88])failure(10);
                        else begin valid<=0;busy<=0;boot_done<=1;state<=IDLE;end
                    end else begin
                        ram_address<=0;byte_index<=0;
                        launch(8'h03,base(active_slot)+256,1,0,{2'd0,body_bytes},LOAD_WAIT);
                    end
                end
                LOAD_WAIT:if(spi_done)begin
                    if((~crc)!=header[119:88])begin valid<=0;loaded_count<=0;failure(10);end
                    else begin valid<=1;busy<=0;boot_done<=1;state<=IDLE;end
                end
                IDLE:if(save || delete_take)begin
                    // An unknown or interrupted unrecognizable slot stays
                    // locked even when the other slot is a valid recording.
                    if(jedec!=24'hef4017 ||
                        (active_present && !owned[!active_slot]) ||
                        (!active_present && owned==0))begin
                        done<=1;ok<=0;error<=8;
                    end else if(!delete_take && (count==0 || count>DEPTH))begin
                        done<=1;ok<=0;error<=10;
                    end else begin
                        target_slot<=active_present ? !active_slot : !owned[0];
                        header<={8'hff,32'hffffffff,delete_take ? 24'd0 : duration,
                            delete_take ? 16'd0 : {take_full,{(14-AW){1'b0}},count},generation+16'd1,32'h31545046};
                        take_count<=delete_take ? 0 : count;
                        busy<=1;ok<=0;error<=0;save_active<=1;authorized<=1;watchdog<=0;
                        meta_index<=0;crc<=32'hffffffff;state<=META;
                    end
                end
                META:if(crc_bits==1)begin
                    if(meta_index==10)state<=META_DONE;else meta_index<=meta_index+1'b1;
                end
                META_DONE:begin
                    meta_crc<=crc;operation<=0;erase_second<=0;
                    operation_offset<={target_slot,13'd0};state<=WREN_BEGIN;
                end
                WREN_BEGIN:if(EXTERNAL_NOR)begin
                    if(operation==0)launch(8'h20,operation_address,1,0,0,OP_WAIT);
                    else launch(8'h02,operation_address,1,1,
                        operation==1 ? {6'd0,page_size} : operation==2 ? 15'd16 : 15'd1,OP_WAIT);
                end else launch(8'h06,0,0,0,0,WREN_WAIT);
                WREN_WAIT:if(spi_done)launch(8'h05,0,0,0,1,WEL_WAIT);
                WEL_WAIT:if(spi_done)begin
                    if(!status_byte[1] || status_byte[0])failure(9);
                    else if(operation==0)launch(8'h20,operation_address,1,0,0,OP_WAIT);
                    else launch(8'h02,operation_address,1,1,
                        operation==1 ? {6'd0,page_size} : operation==2 ? 15'd16 : 15'd1,OP_WAIT);
                end
                OP_WAIT:if(spi_done)begin if(EXTERNAL_NOR)finish_operation;else state<=POLL_BEGIN;end
                POLL_BEGIN:launch(8'h05,0,0,0,1,POLL_WAIT);
                POLL_WAIT:if(spi_done)begin
                    if(status_byte[0])state<=POLL_BEGIN;
                    else finish_operation;
                end
                BODY_VERIFY_BEGIN:begin
                    crc<=meta_crc;launch(8'h03,base(target_slot)+256,1,0,{2'd0,body_bytes},BODY_VERIFY_WAIT);
                end
                BODY_VERIFY_WAIT:if(spi_done)begin
                    if((~crc)!=header[119:88])failure(10);else state<=HEADER_BEGIN;
                end
                HEADER_BEGIN:begin
                    operation<=2;operation_offset<={target_slot,13'd0};header_index<=0;state<=WREN_BEGIN;
                end
                HEADER_VERIFY_WAIT:if(spi_done)begin
                    if(verify_error)failure(10);
                    else begin operation<=3;operation_offset<={target_slot,13'd0}+14'd15;state<=WREN_BEGIN;end
                end
                COMMIT_VERIFY_WAIT:if(spi_done)begin
                    if(verify_error)failure(10);else state<=FINISH;
                end
                FINISH:begin
                    active_slot<=target_slot;active_present<=1;owned[target_slot]<=1;
                    generation<=header[47:32];loaded_count<=take_count[AW:0];loaded_duration<=header[87:64];loaded_full<=header[63];
                    valid<=take_count!=0;busy<=0;done<=1;ok<=1;authorized<=0;save_active<=0;state<=IDLE;
                end
                default:failure(10);
            endcase
            if(spi_error)failure(8);
            if(busy && watchdog>=CLK_HZ*2)failure(9);
        end
    end
endmodule
