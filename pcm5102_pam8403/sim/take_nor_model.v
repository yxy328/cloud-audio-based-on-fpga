`timescale 1ns/1ps
// Behavioral SPI model, only the guarded top 16KiB is writable. Every other
// address is a fatal test failure. This is not a vendor timing model.
module take_nor_model(input wire cs_n,sck,mosi,output reg miso=1);
    reg [7:0] bytes[0:16383];
    reg [7:0] rx=0,tx=8'hff,command=0;
    reg [23:0] address=0;
    integer bits=0,phase=0,addr_bytes=0,id_index=0,i;
    reg wel=0,write_protect=0;
    reg stuck_busy=0,drop_program=0;
    time busy_until=0;
    integer polls=0;
    reg [23:0] jedec=24'hef4017;
    integer erases=0,programs=0,wren_count=0;
    initial for(i=0;i<16384;i=i+1)bytes[i]=8'hff;
    function [7:0] at;
        input [23:0] addr;
        begin
            if(addr>=24'h7fc000 && addr<24'h800000)at=bytes[addr-24'h7fc000];
            else at=8'h5a;
        end
    endfunction
    always @(negedge cs_n)begin
        rx=0;tx=8'hff;command=0;address=0;bits=0;phase=0;addr_bytes=0;id_index=0;
    end
    always @(posedge sck)if(!cs_n)begin
        rx={rx[6:0],mosi};bits=bits+1;
        if(bits==8)begin
            bits=0;
            case(phase)
                0:begin
                    command=rx;
                    case(rx)
                        8'h9f:begin phase=2;id_index=0;tx=jedec[23:16];end
                        8'h05:begin phase=2;tx={6'd0,wel,(stuck_busy || $time<busy_until)};polls=polls+1;end
                        8'h03,8'h02,8'h20:begin phase=1;addr_bytes=0;end
                        8'h06:begin if(!write_protect)wel=1;wren_count=wren_count+1;phase=3;end
                        8'h04:begin wel=0;phase=3;end
                        default:$fatal(1,"Forbidden NOR opcode %h",rx);
                    endcase
                end
                1:begin
                    address={address[15:0],rx};addr_bytes=addr_bytes+1;
                    if(addr_bytes==3)begin
                        phase=2;
                        if(command==8'h03)tx=at(address);
                        if(command==8'h02 || command==8'h20)begin
                            if(!wel || address<24'h7fc000 || address>=24'h800000)
                                $fatal(1,"Boot-region write or missing WREN: %h",address);
                        end
                    end
                end
                2:case(command)
                    8'h9f:begin
                        id_index=id_index+1;
                        tx=id_index==1 ? jedec[15:8] : id_index==2 ? jedec[7:0] : 8'hff;
                    end
                    8'h05:begin
                        tx={6'd0,wel,(stuck_busy || $time<busy_until)};
                    end
                    8'h03:begin address=address+1'b1;tx=at(address);end
                    8'h02:begin
                        if(address<24'h7fc000 || address>=24'h800000)$fatal(1,"Program range");
                        if(!drop_program)bytes[address-24'h7fc000]=bytes[address-24'h7fc000] & rx;
                        address=address+1'b1;
                    end
                    default:begin end
                endcase
            endcase
        end
    end
    always @(negedge sck)if(!cs_n)begin miso=tx[7];tx={tx[6:0],1'b1};end
    always @(posedge cs_n)begin
        miso=1;
        if(command==8'h20 && wel && !write_protect)begin
            if(address[11:0]!=0 || address<24'h7fc000 || address>=24'h800000)$fatal(1,"Erase range");
            for(i=0;i<4096;i=i+1)bytes[address-24'h7fc000+i]=8'hff;
            erases=erases+1;wel=0;busy_until=$time+6000;
        end
        if(command==8'h02)begin wel=0;programs=programs+1;busy_until=$time+6000;end
    end
endmodule
