`timescale 1ns/1ps
module tb_audio_record_stream;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,start=0,stop=0,abort=0,cts=0;
    reg [15:0] session=16'h9234;
    reg [9:0] divider=0;
    reg [31:0] source_index=0;
    wire ce=divider==1023;
    wire signed [15:0] sample=(source_index*73)^16'hb631;
    always @(posedge clk)begin divider<=divider+1'b1;if(ce)source_index<=source_index+1'b1;end
    wire tx,busy,ready,capturing,overflow;
    audio_record_stream #(.FIFO_DEPTH(64),.BLOCK_SAMPLES(16)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.sample(sample),.start(start),.stop(stop),
        .abort(abort),.session(session),.cts_n(cts),.tx(tx),.busy(busy),.ready(ready),
        .capturing(capturing),.overflow(overflow));
    reg [7:0] bytes[0:65535];
    reg [15:0] expected[0:4095];
    integer received=0,expected_count=0,expected_limit=1501;
    reg model_enabled=0,ignore_uart=0;
    always @(posedge clk)if(resetn && ce && capturing && !stop && model_enabled && expected_count<expected_limit)begin
        expected[expected_count]=sample;expected_count=expected_count+1;
    end
    integer b;
    reg [7:0] byte_in;
    initial forever begin
        @(negedge tx);repeat(12)@(posedge clk);
        for(b=0;b<8;b=b+1)begin repeat(25)@(posedge clk);byte_in[b]=tx;end
        repeat(25)@(posedge clk);
        if(!ignore_uart)begin
            if(tx!==1)$fatal(1,"Recording UART stop bit");
            bytes[received]=byte_in;received=received+1;
        end
    end
    function [15:0] get16;
        input integer index;
        begin get16={bytes[index+1],bytes[index]};end
    endfunction
    function [31:0] get32;
        input integer index;
        begin get32={bytes[index+3],bytes[index+2],bytes[index+1],bytes[index]};end
    endfunction
    function [15:0] crc16;
        input integer index,length;
        integer j,k;reg [15:0] c;
        begin c=16'hffff;
            for(j=0;j<length;j=j+1)begin
                c=c^{bytes[index+j],8'd0};
                for(k=0;k<8;k=k+1)c=c[15] ? (c<<1)^16'h1021 : c<<1;
            end
            crc16=c;
        end
    endfunction
    task begin_take;
        begin wait(!busy);@(negedge clk);received=0;expected_count=0;model_enabled=1;start=1;
            @(negedge clk);start=0;end
    endtask
    task stop_take;
        begin @(negedge clk);stop=1;@(negedge clk);stop=0;wait(!busy);repeat(300)@(negedge clk);end
    endtask
    integer offset,length,seq,samples_seen,j,kind,packets;
    task check_take;
        input integer count,failed;
        begin offset=0;seq=0;samples_seen=0;packets=0;
            while(offset<received)begin
                if({bytes[offset],bytes[offset+1],bytes[offset+2],bytes[offset+3]}!=="FAR1")$fatal(1,"Packet magic at %0d",offset);
                kind=bytes[offset+4];length=get16(offset+6);
                if(get16(offset+8)!==seq[15:0] || get16(offset+10)!==session)$fatal(1,"Packet seq/session");
                if(get32(offset+12)!==samples_seen)$fatal(1,"Packet sample index");
                if(crc16(offset,16+length)!==get16(offset+16+length))$fatal(1,"Packet CRC");
                if(seq==0)begin
                    if(kind!=1 || length!=8 || get32(offset+16)!=50000000 || get16(offset+20)!=1024 ||
                       bytes[offset+22]!=16 || bytes[offset+23]!=1)$fatal(1,"Start format");
                end else if(kind==2)begin
                    if(length==0 || length>32 || length[0])$fatal(1,"Data length");
                    for(j=0;j<length/2;j=j+1)begin
                        if(get16(offset+16+j*2)!==expected[samples_seen])$fatal(1,"PCM mismatch at %0d",samples_seen);
                        samples_seen=samples_seen+1;
                    end
                end else if(kind==3)begin
                    if(length!=4 || get32(offset+16)!=failed || bytes[offset+5]!=failed || offset+22!=received)
                        $fatal(1,"End status/position");
                end else $fatal(1,"Packet type");
                offset=offset+18+length;seq=seq+1;packets=packets+1;
            end
            if(samples_seen!=count || kind!=3)$fatal(1,"Missing PCM or final END");
            $display("PASS audio take session=%0d samples=%0d packets=%0d overflow=%0d",session,count,packets,failed);
        end
    endtask
    integer file_id;
    initial begin
        repeat(5)@(negedge clk);resetn=1;repeat(5)@(negedge clk);
        begin_take;
        wait(expected_count==100);
        // Pause in the middle of UART traffic without cutting a byte.
        cts=1;repeat(16000)@(negedge clk);cts=0;
        wait(expected_count==1501);stop_take;check_take(1501,0);
        file_id=$fopen("sim/build/audio_record_stream.bin","wb");
        for(j=0;j<received;j=j+1)$fwrite(file_id,"%c",bytes[j]);$fclose(file_id);
        // A prolonged CTS stall must terminate with an explicit incomplete END.
        session=65535;expected_limit=64;begin_take;cts=1;
        wait(overflow);if(capturing)$fatal(1,"FIFO overflow did not end capture");
        repeat(2000)@(negedge clk);cts=0;wait(!busy);repeat(300)@(negedge clk);
        check_take(64,1);
        // Abort can cut a transport byte, but the following take is clean.
        session=7;expected_limit=99;begin_take;wait(tx==0);ignore_uart=1;
        @(negedge clk);abort=1;@(negedge clk);abort=0;
        repeat(300)@(negedge clk);ignore_uart=0;session=8;begin_take;
        wait(expected_count==99);stop_take;check_take(99,0);
        $display("PASS audio record stream: exact live PCM, real 2Mbps UART, CTS slots, CRC/seq/session/index, partial tail, overflow abort and clean restart");$finish;
    end
    initial begin #100000000;$fatal(1,"Audio record timeout");end
endmodule
