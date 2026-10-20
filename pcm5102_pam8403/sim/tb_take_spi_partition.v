`timescale 1ns/1ps
module tb_take_spi_partition;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,go=0,authorized=1,address_valid=1,writing=1,event_partition=0;
    reg [7:0] opcode=8'h02,write_data=8'h55;
    reg [23:0] address=0;reg [14:0] length=1;
    wire write_valid=1,miso=1;
    wire write_ready,read_valid,done,error,cs_n,sck,mosi;
    wire [7:0] read_data;
    take_spi_transaction #(.HALF_CYCLES(3),.DATA_BASE(24'h100000),
        .DATA_END(24'h800000),.PARTITIONED(1)) dut(.*);
    integer checks=0,transactions=0;
    always @(negedge cs_n)transactions=transactions+1;
    task attempt;
        input owner;input [7:0] op;input [23:0] addr;
        input [14:0] size;input reject;
        integer before_count;
        begin
            @(negedge clk);event_partition=owner;opcode=op;address=addr;
            length=size;writing=op==8'h02;before_count=transactions;go=1;
            @(negedge clk);go=0;wait(done);#1;
            if(error!==reject || transactions!=before_count+(reject ? 0 : 1) || !cs_n)
                $fatal(1,"partition owner=%b opcode=%h address=%h length=%0d",owner,op,addr,size);
            checks=checks+1;@(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        attempt(0,8'h02,24'h0fffff,1,1);
        attempt(0,8'h02,24'h100000,1,0);
        attempt(0,8'h02,24'h7fbfff,1,0);
        attempt(0,8'h02,24'h7fbfff,2,1);
        attempt(0,8'h02,24'h7fc000,1,1);
        attempt(0,8'h20,24'h7fb000,0,0);
        attempt(0,8'h20,24'h7fc000,0,1);
        attempt(1,8'h02,24'h100000,1,1);
        attempt(1,8'h02,24'h7fbfff,1,1);
        attempt(1,8'h02,24'h7fc000,1,0);
        attempt(1,8'h02,24'h7fffff,1,0);
        attempt(1,8'h02,24'h7fffff,2,1);
        attempt(1,8'h20,24'h7fc000,0,0);
        attempt(1,8'h20,24'h800000,0,1);
        $display("PASS shared SPI partition: %0d PCM/event/config/page/end boundary checks",checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"partition guard timeout");end
endmodule
