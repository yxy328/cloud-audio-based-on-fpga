`timescale 1ns/1ps
module tb_audio_take_store;
    reg clk=0,resetn=0,sample_ce=0,prepare=0,start=0,stop=0,abort=0,send=0,ack_valid=0;
    reg signed [15:0] sample=0;
    reg [15:0] session=16'h1234,ack_sequence=0;
    wire [7:0] stream_data;wire stream_valid,stream_last;
    reg stream_ready=1;
    wire [3:0] status,error;wire valid,prepared,capturing,overflow,busy;
    wire [20:0] sample_count,stored_samples;wire [15:0] stored_generation;
    wire cs_n,sck,mosi,miso;
    integer checks=0,packets=0,bytes=0,n;
    reg [15:0] observed_sequence;
    reg [7:0] received[0:2047];
    always #10 clk=~clk;
    audio_take_store #(.CLK_HZ(50000000),.SAMPLE_DIVISOR(65535),.MAX_SECONDS(1),.HALF_CYCLES(3),.ACK_TIMEOUT_CYCLES(100000)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.sample(sample),.prepare(prepare),.start(start),.stop(stop),.abort(abort),.send(send),
        .session(session),.ack_valid(ack_valid),.ack_sequence(ack_sequence),.stream_data(stream_data),.stream_valid(stream_valid),
        .stream_last(stream_last),.stream_ready(stream_ready),.status(status),.error(error),.valid(valid),.prepared(prepared),
        .capturing(capturing),.overflow(overflow),.sample_count(sample_count),.stored_samples(stored_samples),.stored_generation(stored_generation),
        .busy(busy),.cs_n(cs_n),.sck(sck),.mosi(mosi),.miso(miso));
    audio_nor_model flash(.*);
    task check;
        input condition;input [255:0] message;
        begin checks=checks+1;if(!condition)$fatal(1,"FAIL %0s",message);end
    endtask
    always @(posedge clk)begin
        ack_valid<=0;
        if(stream_valid&&stream_ready)begin received[bytes]=stream_data;bytes=bytes+1;end
        if(stream_last)begin
            ack_sequence<=dut.packet_sequence;ack_valid<=1;packets=packets+1;
        end
    end
    initial begin
        repeat(5)@(posedge clk);resetn=1;
        wait(!busy);check(error==0,"boot JEDEC/header scan");
        @(posedge clk);prepare<=1;@(posedge clk);prepare<=0;wait(prepared);check(flash.erases==2,"bounded two-sector prepare");
        @(posedge clk);start<=1;@(posedge clk);start<=0;@(posedge clk);check(capturing,"capture starts only after prepare");
        for(n=0;n<8;n=n+1)begin
            sample<=16'h1100+n;@(posedge clk);sample_ce<=1;@(posedge clk);sample_ce<=0;repeat(3)@(posedge clk);
        end
        @(posedge clk);stop<=1;@(posedge clk);stop<=0;wait(!busy);check(valid,"verified commit becomes valid");check(stored_samples==8,"stored sample count");check(!overflow,"no capture overflow");
        @(posedge clk);send<=1;@(posedge clk);send<=0;repeat(4)@(posedge clk);ack_sequence<=16'hffff;ack_valid<=1;@(posedge clk);ack_valid<=0;
        wait(!busy);check(packets==3,"START DATA END packets acknowledged");
        check(received[0]=="F"&&received[1]=="A"&&received[2]=="R"&&received[3]=="1","FAR1 magic");
        check(received[4]==1&&received[5]==1,"CRC-capable START");
        check(received[16]==8'h80&&received[17]==8'hf0&&received[18]==8'hfa&&received[20]==8'hff&&received[21]==8'hff&&received[22]==16&&received[23]==1,"exact rational sample format");
        $display("PASS audio take store: %0d checks, %0d packets, %0d stream bytes",checks,packets,bytes);$finish;
    end
    initial begin #40000000;$display("timeout state=%0d op=%0d spi=%0d busy=%b err=%0d prep=%b cap=%b samples=%0d wr=%0d rd=%0d",dut.state,dut.u_nor.state,dut.u_nor.u_spi.state,busy,error,prepared,capturing,sample_count,dut.wr_pointer,dut.rd_pointer);$fatal(1,"timeout");end
endmodule
