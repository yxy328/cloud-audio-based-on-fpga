`timescale 1ns/1ps
// Sparse-behavior W25Q64 model for the audio partition. Only bytes touched by
// the recorder are initialized/changed; the two headers start erased.
module audio_nor_model(input wire cs_n,sck,mosi,output reg miso=1);
    localparam BASE=24'h100000,END_ADDR=24'h7fc000,SIZE=END_ADDR-BASE;
    reg [7:0] bytes[0:SIZE-1];
    reg [7:0] rx=0,tx=8'hff,command=0;
    reg [23:0] address=0;
    integer bits=0,phase=0,addr_bytes=0,id_index=0,i;
    reg wel=0;
    time busy_until=0;
    integer erases=0,programs=0;
    reg [23:0] jedec=24'hef4017;
    reg write_protected=0,drop_program=0;
    time program_delay=1000,erase_delay=1000;
    initial begin
        for(i=0;i<33;i=i+1)begin bytes[i]=8'hff;bytes[24'h37e000+i]=8'hff;end
    end
    function [7:0] at;
        input [23:0] addr;
        begin at=(addr>=BASE&&addr<END_ADDR&&bytes[addr-BASE]!==8'hxx) ? bytes[addr-BASE] : 8'hff;end
    endfunction
    always @(negedge cs_n)begin rx=0;tx=8'hff;command=0;address=0;bits=0;phase=0;addr_bytes=0;id_index=0;end
    always @(posedge sck)if(!cs_n)begin
        rx={rx[6:0],mosi};bits=bits+1;
        if(bits==8)begin
            bits=0;
            case(phase)
                0:begin command=rx;
                    case(rx)
                        8'h9f:begin phase=2;id_index=0;tx=jedec[23:16];end
                        8'h05:begin phase=2;tx={6'd0,wel,($time<busy_until)};end
                        8'h03,8'h02,8'h20:begin phase=1;addr_bytes=0;end
                        8'h06:begin wel=!write_protected;phase=3;end
                        default:$fatal(1,"Forbidden audio NOR opcode %h",rx);
                    endcase
                end
                1:begin
                    address={address[15:0],rx};addr_bytes=addr_bytes+1;
                    if(addr_bytes==3)begin
                        phase=2;
                        if(command==8'h03)tx=at(address);
                        if((command==8'h02||command==8'h20)&&(!wel||address<BASE||address>=END_ADDR))$fatal(1,"Unsafe audio NOR write %h",address);
                    end
                end
                2:case(command)
                    8'h9f:begin id_index=id_index+1;tx=id_index==1?jedec[15:8]:id_index==2?jedec[7:0]:8'hff;end
                    8'h05:tx={6'd0,wel,($time<busy_until)};
                    8'h03:begin address=address+1'b1;tx=at(address);end
                    8'h02:begin if(!drop_program)bytes[address-BASE]=at(address)&rx;address=address+1'b1;end
                endcase
            endcase
        end
    end
    always @(negedge sck)if(!cs_n)begin miso=tx[7];tx={tx[6:0],1'b1};end
    always @(posedge cs_n)begin
        miso=1;
        if(command==8'h20&&wel)begin
            if(address[11:0]!=0)$fatal(1,"Unaligned audio erase");
            for(i=0;i<4096;i=i+1)bytes[address-BASE+i]=8'hff;
            erases=erases+1;wel=0;busy_until=$time+erase_delay;
        end
        if(command==8'h02)begin programs=programs+1;wel=0;busy_until=$time+program_delay;end
    end
endmodule
