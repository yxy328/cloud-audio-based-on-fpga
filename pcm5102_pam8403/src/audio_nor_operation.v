`timescale 1ns/1ps
// Bounded W25Q64 operations for the dedicated audio partition. Erase and
// page-program requests always perform WREN, verify WEL, and poll BUSY.
module audio_nor_operation #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer HALF_CYCLES=5,
    parameter [23:0] DATA_BASE=24'h100000,
    parameter [23:0] DATA_END=24'h7fc000
)(
    input wire clk,resetn,start,
    input wire [2:0] kind, // 1=JEDEC, 2=read, 3=erase4K, 4=page program
    input wire [23:0] address,
    input wire [9:0] length,
    input wire [7:0] write_data,
    input wire write_valid,
    output wire write_ready,
    output wire [7:0] read_data,
    output wire read_valid,
    output reg busy,done,error,
    output wire cs_n,sck,mosi,
    input wire miso
);
    localparam IDLE=0,DIRECT_WAIT=1,WREN_WAIT=2,WEL_WAIT=3,
        MUTATE_WAIT=4,POLL_WAIT=5;
    localparam integer WATCHDOG_CYCLES=CLK_HZ*2;
    reg [2:0] state,saved_kind;
    reg go,authorized,address_valid,writing,spi_reset;
    reg [23:0] saved_address;
    reg [9:0] saved_length;
    reg [7:0] opcode;
    reg [23:0] op_address;
    reg [14:0] op_length;
    reg [31:0] watchdog;
    wire raw_done,raw_error;
    wire [7:0] raw_read_data;
    wire raw_read_valid;
    assign read_data=raw_read_data;
    assign read_valid=raw_read_valid && (state==DIRECT_WAIT);
    take_spi_transaction #(.HALF_CYCLES(HALF_CYCLES),.DATA_BASE(DATA_BASE),.DATA_END(DATA_END)) u_spi(
        .clk(clk),.resetn(resetn && !spi_reset),.go(go),.authorized(authorized),.opcode(opcode),
        .address(op_address),.address_valid(address_valid),.writing(writing),.length(op_length),
        .write_data(write_data),.write_valid(write_valid),.write_ready(write_ready),
        .read_data(raw_read_data),.read_valid(raw_read_valid),.done(raw_done),.error(raw_error),
        .cs_n(cs_n),.sck(sck),.mosi(mosi),.miso(miso));
    task launch;
        input [7:0] command;
        input [23:0] addr;
        input addr_valid,is_write;
        input [14:0] size;
        begin
            opcode<=command;op_address<=addr;address_valid<=addr_valid;
            writing<=is_write;op_length<=size;go<=1;
        end
    endtask
    task fail;
        begin busy<=0;done<=1;error<=1;authorized<=0;spi_reset<=1;go<=0;state<=IDLE;end
    endtask
    always @(posedge clk)begin
        if(!resetn)begin
            state<=IDLE;saved_kind<=0;go<=0;authorized<=0;address_valid<=0;writing<=0;
            opcode<=0;op_address<=0;op_length<=0;watchdog<=0;busy<=0;done<=0;error<=0;
            spi_reset<=0;saved_address<=0;saved_length<=0;
        end else begin
            go<=0;done<=0;spi_reset<=0;
            if(busy)watchdog<=watchdog+1'b1;else watchdog<=0;
            if(busy && watchdog>=WATCHDOG_CYCLES)fail();
            else case(state)
                IDLE:if(start)begin
                    busy<=1;error<=0;saved_kind<=kind;watchdog<=0;
                    saved_address<=address;saved_length<=length;
                    if(kind==1)begin launch(8'h9f,0,0,0,3);state<=DIRECT_WAIT;end
                    else if(kind==2 && length!=0)begin launch(8'h03,address,1,0,{5'd0,length});state<=DIRECT_WAIT;end
                    else if(kind==3 || (kind==4 && length!=0))begin
                        authorized<=1;launch(8'h06,0,0,0,0);state<=WREN_WAIT;
                    end else fail();
                end
                DIRECT_WAIT:if(raw_done)begin
                    busy<=0;done<=1;error<=raw_error;state<=IDLE;
                end
                WREN_WAIT:if(raw_done)begin
                    if(raw_error)fail();else begin launch(8'h05,0,0,0,1);state<=WEL_WAIT;end
                end
                WEL_WAIT:if(raw_done)begin
                    if(raw_error || !raw_read_data[1] || raw_read_data[0])fail();
                    else begin
                        if(saved_kind==3)launch(8'h20,saved_address,1,0,0);
                        else launch(8'h02,saved_address,1,1,{5'd0,saved_length});
                        state<=MUTATE_WAIT;
                    end
                end
                MUTATE_WAIT:if(raw_done)begin
                    if(raw_error)fail();else begin launch(8'h05,0,0,0,1);state<=POLL_WAIT;end
                end
                POLL_WAIT:if(raw_done)begin
                    if(raw_error)fail();
                    else if(raw_read_data[0])begin launch(8'h05,0,0,0,1);state<=POLL_WAIT;end
                    else begin busy<=0;done<=1;authorized<=0;state<=IDLE;end
                end
                default:fail();
            endcase
        end
    end
endmodule
