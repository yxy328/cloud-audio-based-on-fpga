`timescale 1ns/1ps
module tb_audio_take_safety;
    reg clk=0,resetn=0,sample_ce=0,prepare=0,start=0,stop=0,abort=0,send=0,ack_valid=0;
    reg signed [15:0] sample=0;
    reg [15:0] session=16'h1234,ack_sequence=0;
    wire [7:0] stream_data;wire stream_valid,stream_last;
    reg stream_ready=1,auto_ack=1;
    wire [3:0] status,error;wire valid,prepared,capturing,overflow,busy;
    wire [20:0] sample_count,stored_samples;wire [15:0] stored_generation;
    wire cs_n,sck,mosi,miso;
    integer checks=0,packets=0,count=0,n,cycle=0,ack_delay=0,old_erases;
    reg [15:0] pending_ack;
    reg [7:0] received[0:8191];
    always #10 clk=~clk;
    // Same page/FIFO/slot geometry; short maximum keeps exhaustive scans fast.
    audio_take_store #(.CLK_HZ(50000000),.SAMPLE_DIVISOR(65535),.MAX_SECONDS(2),.HALF_CYCLES(3),.ACK_TIMEOUT_CYCLES(100000)) dut(.spi_request(),.spi_response(12'd0),.nor_request(),.nor_response(12'd0),.*);
    audio_nor_model flash(.*);
    task check;
        input condition;input [511:0] message;
        begin checks=checks+1;if(!condition)$fatal(1,"FAIL %0s state=%0d err=%0d",message,dut.state,error);end
    endtask
    task reset;
        begin @(negedge clk);resetn=0;repeat(5)@(negedge clk);resetn=1;wait(!busy);@(negedge clk);end
    endtask
    task prep;
        begin @(negedge clk);prepare=1;@(negedge clk);prepare=0;repeat(5)@(negedge clk);wait(!busy);@(negedge clk);end
    endtask
    task begin_capture;
        begin @(negedge clk);start=1;@(negedge clk);start=0;check(capturing,"prepared capture starts");end
    endtask
    task finish_capture;
        begin @(negedge clk);stop=1;@(negedge clk);stop=0;wait(!busy);@(negedge clk);end
    endtask
    function [15:0] pcm;input integer k;begin pcm=(k*73)^16'hb631;end endfunction
    task samples;
        input integer how_many,spacing;
        integer k;
        begin for(k=0;k<how_many;k=k+1)begin
            @(negedge clk);sample=pcm(k);sample_ce=1;@(negedge clk);sample_ce=0;repeat(spacing)@(negedge clk);
        end end
    endtask
    task download;
        begin @(negedge clk);send=1;@(negedge clk);send=0;repeat(5)@(negedge clk);
            pending_ack=16'hffff;ack_delay=1;wait(!busy);@(negedge clk);end
    endtask
    always @(negedge clk)begin
        cycle=cycle+1;stream_ready=(cycle%7)!=0;ack_valid=0;
        if(ack_delay!=0)begin ack_delay=ack_delay-1;if(ack_delay==0)begin ack_valid=1;ack_sequence=pending_ack;end end
    end
    always @(posedge clk)if(stream_valid&&stream_ready)begin
        received[count]=stream_data;count=count+1;
        if(stream_last)begin packets=packets+1;if(auto_ack)begin pending_ack=dut.packet_sequence;ack_delay=25;end end
    end
    function [15:0] u16;input integer p;begin u16={received[p+1],received[p]};end endfunction
    function [31:0] u32;input integer p;begin u32={received[p+3],received[p+2],received[p+1],received[p]};end endfunction
    function [15:0] crc16;
        input integer p,size;integer a,b;reg [15:0] c;
        begin c=65535;for(a=0;a<size;a=a+1)begin c=c^{received[p+a],8'd0};for(b=0;b<8;b=b+1)c=c[15]?(c<<1)^16'h1021:c<<1;end crc16=c;end
    endfunction
    integer off,size,seq,seen,j;
    initial begin
        reset();check(error==0&&!valid,"empty boot");
        flash.bytes[4090]=0;prep();check(error==13&&flash.erases==0,"foreign padding never erased");flash.bytes[4090]=8'hff;
        flash.jedec=24'hef4016;reset();check(error==1,"wrong JEDEC rejected");prep();check(error==1&&flash.erases==0,"JEDEC failure stays locked");
        flash.jedec=24'hef4017;reset();flash.write_protected=1;prep();
        check(error==4&&flash.erases==0,"write protection is respected without status-register override");
        flash.write_protected=0;prep();check(prepared&&flash.erases==2,"blank scan and bounded prepare");
        begin_capture();samples(520,200);
        // STOP must survive a page program rather than be lost while busy.
        wait(dut.state==14);finish_capture();check(valid&&stored_samples==520&&stored_generation==1&&!overflow&&error==0,"page-time STOP commits correct length");
        for(n=0;n<520;n=n+1)check({flash.bytes[4097+2*n],flash.bytes[4096+2*n]}===pcm(n),"NOR preserves every signed PCM word");
        download();check(error==0&&packets==5,"START three DATA END all acknowledged");
        off=0;seq=0;seen=0;
        while(off<count)begin
            size=u16(off+6);check({received[off],received[off+1],received[off+2],received[off+3]}=="FAR1","packet magic");
            check(u16(off+8)==seq&&u16(off+10)==session&&u32(off+12)==seen,"sequence session sample offset");
            check(crc16(off,16+size)==u16(off+16+size),"packet independent CRC16");
            if(seq==0)check(size==12&&u32(off+24)==520&&received[off+5]==1,"START declares exact total samples");
            else if(received[off+4]==2)for(j=0;j<size/2;j=j+1)begin check(u16(off+16+j*2)===pcm(seen),"synchronous packet RAM preserves every sample");seen=seen+1;end
            off=off+18+size;seq=seq+1;
        end
        check(seen==520,"no dropped/duplicated samples");
        reset();check(valid&&stored_samples==520&&stored_generation==1,"reboot selects committed header");
        prep();check(prepared&&dut.target_slot==1,"next preparation preserves previous active slot");
        begin_capture();samples(150,200);@(negedge clk);abort=1;@(negedge clk);abort=0;wait(!busy);check(valid&&stored_generation==1,"abort preserves last recording");
        old_erases=flash.erases;prep();check(error==13&&flash.erases==old_erases,"partial uncommitted recording is locked after abort");
        // Deliberate service erase of only this test's inactive slot.
        for(n=0;n<8192;n=n+1)flash.bytes[24'h37e000+n]=8'hff;
        prep();begin_capture();flash.program_delay=30000000;samples(1200,1022);wait(!busy);
        check(error==15&&overflow&&stored_generation==1,"30ms NOR stall at real 1024-clock sampling cannot commit truncated take");flash.program_delay=1000;
        for(n=0;n<8192;n=n+1)flash.bytes[24'h37e000+n]=8'hff;
        prep();begin_capture();finish_capture();check(error==14&&stored_generation==1,"empty recording cannot replace prior take");
        prep();flash.drop_program=1;begin_capture();samples(150,200);finish_capture();flash.drop_program=0;
        check(error==7&&stored_generation==1,"ignored page writes fail full data readback CRC");
        for(n=0;n<8192;n=n+1)flash.bytes[24'h37e000+n]=8'hff;
        prep();begin_capture();samples(8,200);
        fork begin wait(dut.state==18);flash.drop_program=1;end begin finish_capture();end join
        flash.drop_program=0;check(error==8&&stored_generation==1,"unwritten header never reaches commit");
        for(n=0;n<8192;n=n+1)flash.bytes[24'h37e000+n]=8'hff;
        prep();begin_capture();samples(8,200);
        fork begin wait(dut.state==20);flash.drop_program=1;end begin finish_capture();end join
        flash.drop_program=0;check(error==9&&stored_generation==1,"ignored commit marker fails readback");
        reset();check(valid&&stored_generation==1,"power cycle with uncommitted new header recovers old take");
        old_erases=flash.erases;prep();check(error==13&&flash.erases==old_erases,"uncommitted header stays protected after reboot");
        for(n=0;n<8192;n=n+1)flash.bytes[24'h37e000+n]=8'hff;
        prep();begin_capture();samples(1525,200);wait(!busy);check(valid&&error==0&&stored_samples==1525&&stored_generation==2&&!overflow,"capacity auto-stop is a complete take");
        $writememh("sim/build/audio_take_slot.hex",flash.bytes,24'h37e000,24'h37ffff);
        reset();check(valid&&stored_samples==1525&&stored_generation==2,"newest generation recovered");
        flash.bytes[4096]=flash.bytes[4096]^8'h01;old_erases=flash.erases;prep();check(error==13&&flash.erases==old_erases,"damaged owned slot rejected by full PCM CRC");
        auto_ack=0;count=0;packets=0;download();check(error==11&&valid&&stored_generation==2,"missing ACK times out and keeps recording");
        flash.bytes[4096]=flash.bytes[4096]^8'h01;
        flash.bytes[24'h37f000]=flash.bytes[24'h37f000]^8'h01;
        reset();check(valid&&stored_generation==1&&stored_samples==520,"boot checks whole PCM and falls back from corrupt newest take");
        old_erases=flash.erases;prep();check(error==13&&flash.erases==old_erases,"corrupt newest slot remains locked while older good take survives");
        $display("PASS audio take safety: %0d checks; page/FIFO/CRC/ownership/JEDEC/abort/reboot/capacity/ACK timeout",checks);$finish;
    end
    initial begin #500000000;$fatal(1,"timeout state=%0d err=%0d count=%0d",dut.state,error,sample_count);end
endmodule
