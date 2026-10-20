`timescale 1ns/1ps
module tb_take_spi_guard;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,go=0,authorized=0,address_valid=1,writing=1;
    reg [7:0] opcode=0,write_data=8'h55;
    reg [23:0] address=0;reg [14:0] length=0;
    wire write_ready,read_valid,done,error,cs_n,sck,mosi,miso;
    wire write_valid=1;wire [7:0] read_data;
    take_spi_transaction dut(.*);
    take_nor_model flash(.*);
    integer checks=0,transactions=0;reg [23:0] received=0;
    always @(negedge cs_n)transactions=transactions+1;
    always @(posedge clk)if(read_valid)received={received[15:0],read_data};
    task transaction;
        input [7:0] op;input [23:0] addr;input [14:0] size;input auth,av,wr,reject;
        integer before_count;begin
            @(negedge clk);opcode=op;address=addr;length=size;authorized=auth;address_valid=av;writing=wr;
            before_count=transactions;go=1;@(negedge clk);go=0;
            wait(done);#1;checks=checks+1;
            if(error!==reject || (reject && transactions!=before_count) || !cs_n)
                $fatal(1,"SPI guard op=%h addr=%h len=%0d expected reject=%b",op,addr,size,reject);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        transaction(8'hc7,0,0,1,0,0,1);
        transaction(8'hd8,24'h7fc000,0,1,1,0,1);
        transaction(8'h06,0,0,0,0,0,1);
        transaction(8'h02,0,1,1,1,1,1);
        transaction(8'h20,24'h001000,0,1,1,0,1);
        transaction(8'h20,24'h7fc001,0,1,1,0,1);
        transaction(8'h02,24'h7fc0ff,2,1,1,1,1);
        transaction(8'h02,24'h7fffff,2,1,1,1,1);
        transaction(8'h02,24'h7fc000,0,1,1,1,1);
        transaction(8'h02,24'h7fc000,257,1,1,1,1);
        transaction(8'h02,24'h7fc000,1,1,0,1,1);
        transaction(8'h9f,0,3,0,0,0,0);
        if(received!==24'hef4017 || flash.wren_count!=0)$fatal(1,"JEDEC read must be non-destructive");
        transaction(8'h06,0,0,1,0,0,0);
        transaction(8'h02,24'h7fc000,1,1,1,1,0);
        if(flash.bytes[0]!==8'h55)$fatal(1,"Authorized page program failed");
        $display("PASS tb_take_spi_guard: %0d transactions; boot writes, chip erase and page/range overflow blocked",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"SPI guard timeout");end
endmodule
