`timescale 1ns/1ps
// Mode-0 byte engine plus a deliberately small NOR command whitelist.
// Independent range checks guard every destructive command, even if the
// higher-level store supplies a bad address. Chip/block erase is absent.
module take_spi_transaction #(
    parameter integer HALF_CYCLES=5,
    parameter [23:0] DATA_BASE=24'h7fc000,
    parameter [23:0] DATA_END=24'h800000,
    parameter integer PARTITIONED=0
)(
    input wire clk,resetn,go,authorized,
    input wire [7:0] opcode,
    input wire [23:0] address,
    input wire address_valid,writing,
    input wire [14:0] length,
    input wire [7:0] write_data,
    input wire write_valid,
    output wire write_ready,
    output reg [7:0] read_data,
    output reg read_valid,done,error,
    output reg cs_n,sck,mosi,
    input wire miso,
    input wire event_partition
);
    localparam IDLE=0,PREP=1,BITS=2,ADVANCE=3,DATA=4,FINISH=5;
    localparam DW=HALF_CYCLES<2 ? 1 : $clog2(HALF_CYCLES);
    reg [2:0] state,stage;
    reg [DW-1:0] divider;
    reg [2:0] bit_number;
    reg [7:0] shift_out,shift_in,command;
    reg [23:0] addr;
    reg use_address,is_write;
    reg [14:0] remaining;
    (* syn_preserve=1, syn_srlstyle="registers" *) reg miso_meta,miso_sync;
    wire destructive=opcode==8'h06 || opcode==8'h02 || opcode==8'h20;
    wire whitelist=opcode==8'h9f || opcode==8'h05 || opcode==8'h03 ||
        opcode==8'h04 || destructive;
    // An aligned sector cannot leave the range. PP also checks page end
    // below, so a page wholly inside the range cannot wrap past 8MiB.
    wire range_ok=address>=DATA_BASE && address<DATA_END && (!PARTITIONED ||
        (event_partition ? address>=24'h7fc000 : address<24'h7fc000));
    wire [23:0] partition_end=PARTITIONED && !event_partition ? 24'h7fc000 : DATA_END;
    wire safe=whitelist && (!destructive || authorized) &&
        (opcode!=8'h02 || (range_ok && length!=0 && length<=256 &&
            {1'b0,address[7:0]}+length<=256 && address_valid && writing)) &&
        (opcode!=8'h20 || (range_ok && address[11:0]==0 && address_valid && length==0));
    assign write_ready=state==DATA && is_write && remaining!=0;
    task byte_start;
        input [7:0] value;
        begin
            shift_out<=value;shift_in<=0;bit_number<=7;divider<=0;
            mosi<=value[7];sck<=0;state<=BITS;
        end
    endtask
    always @(posedge clk)begin
        if(!resetn)begin
            state<=IDLE;stage<=0;divider<=0;bit_number<=0;shift_out<=0;shift_in<=0;
            command<=0;addr<=0;use_address<=0;is_write<=0;remaining<=0;
            cs_n<=1;sck<=0;mosi<=0;read_data<=0;read_valid<=0;done<=0;error<=0;
            miso_meta<=1;miso_sync<=1;
        end else begin
            miso_meta<=miso;miso_sync<=miso_meta;
            read_valid<=0;done<=0;error<=0;
            case(state)
                IDLE:if(go)begin
                    if(!safe)begin done<=1;error<=1;end
                    else begin
                        cs_n<=0;command<=opcode;addr<=address;use_address<=address_valid;
                        is_write<=writing;remaining<=length;stage<=0;state<=PREP;
                    end
                end
                PREP:byte_start(command);
                BITS:if(divider==HALF_CYCLES-1)begin
                    divider<=0;sck<=!sck;
                    if(!sck)shift_in<={shift_in[6:0],miso_sync};
                    else if(bit_number==0)state<=ADVANCE;
                    else begin
                        bit_number<=bit_number-1'b1;shift_out<={shift_out[6:0],1'b0};
                        mosi<=shift_out[6];
                    end
                end else divider<=divider+1'b1;
                ADVANCE:begin
                    if(stage==0 && use_address)begin stage<=1;byte_start(addr[23:16]);end
                    else if(stage==1)begin stage<=2;byte_start(addr[15:8]);end
                    else if(stage==2)begin stage<=3;byte_start(addr[7:0]);end
                    else if(stage==4)begin
                        if(!is_write)begin read_data<=shift_in;read_valid<=1;end
                        remaining<=remaining-1'b1;
                        state<=remaining==1 ? FINISH : DATA;
                    end else state<=remaining==0 ? FINISH : DATA;
                end
                DATA:if(!is_write || write_valid)begin
                    stage<=4;byte_start(is_write ? write_data : 8'hff);
                end
                FINISH:begin cs_n<=1;mosi<=0;sck<=0;done<=1;state<=IDLE;end
                default:begin state<=IDLE;cs_n<=1;sck<=0;error<=1;done<=1;end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(HALF_CYCLES<3 || DATA_BASE[11:0]!=0 || DATA_END[11:0]!=0 ||
        DATA_BASE>=DATA_END || DATA_END>24'h800000)
        $fatal(1,"Unsafe SPI parameters");
`endif
endmodule
