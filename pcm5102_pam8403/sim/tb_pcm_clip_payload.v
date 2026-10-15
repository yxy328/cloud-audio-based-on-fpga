`timescale 1ns/1ps
// Optional complete-payload regression; run from the project directory:
// tools/run_sim.ps1 -Tests tb_pcm_clip_payload
// Defaults match audio_clips/settlement_4s.json. Other prepared clips can use
// +pcm_hex=path.hex +pcm_samples=COUNT +pcm_sum16=CHECKSUM with vvp.
module tb_pcm_clip_payload;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0,sample_ce=0,request=0;
    reg [2:0] operation=0;
    reg [15:0] arg0=0,arg1=0,arg2=0;
    wire done,valid,playing;
    wire [2:0] error;
    wire signed [15:0] sample;
    reg [7:0] data [0:32767];
    reg [2047:0] hex_path;
    reg [63:0] expected_frames;
    integer sample_count,expected_sum;
    integer i,frames=0,index=0,modelphase=0,expected;
    pcm_clip_player dut(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),
        .request(request),.operation(operation),.arg0(arg0),.arg1(arg1),.arg2(arg2),
        .edit_allowed(1'b1),.toggle_play(1'b0),.restart(1'b0),
        .done(done),.error(error),.valid(valid),.playing(playing),.sample(sample));
    task command;
        input [2:0] op;
        input [15:0] a,b,c;
        integer guard;
        begin
            @(negedge clk);operation=op;arg0=a;arg1=b;arg2=c;request=1;
            @(negedge clk);request=0;guard=0;
            while(!done && guard<100000) begin @(negedge clk);guard=guard+1; end
            if(!done || error!==0)
                $fatal(1,"Payload command op %0d address %0d: done=%b error=%0d",op,a,done,error);
        end
    endtask
    initial begin
        hex_path="audio_clips/settlement_4s.hex";
        sample_count=32000;expected_sum=29699;
        if($value$plusargs("pcm_hex=%s",hex_path)) begin end
        if($value$plusargs("pcm_samples=%d",sample_count)) begin end
        if($value$plusargs("pcm_sum16=%d",expected_sum)) begin end
        if(sample_count<1 || sample_count>32768 || expected_sum<0 || expected_sum>65535)
            $fatal(1,"Payload metadata outside PCM protocol ranges");
        expected_frames=(sample_count*64'd50000000+64'd8191999)/64'd8192000;
        $readmemh(hex_path,data,0,sample_count-1);
        for(i=0;i<sample_count;i=i+1)
            if(^data[i]===1'bx) $fatal(1,"Missing/invalid payload byte %0d",i);
        repeat(3) @(negedge clk);resetn=1;
        command(1,sample_count,expected_sum,0);
        for(i=0;i<sample_count;i=i+1)
            command(2,i,data[i],(i%16==0 ? 1 : 0) |
                (i%16==15 || i==sample_count-1 ? 2 : 0));
        command(3,0,0,0);
        if(!valid) $fatal(1,"Payload did not commit");
        command(4,0,0,0);repeat(6) @(negedge clk);
        while(playing && frames<=expected_frames) begin
            @(negedge clk);sample_ce=1;
            @(negedge clk);sample_ce=0;
            // Real hardware enables occur every 1024 clocks; six clocks here
            // retain RAM latency while accelerating the four-second scenario.
            repeat(5) @(negedge clk);
            frames=frames+1;modelphase=modelphase+8192000;
            if(modelphase>=50000000) begin
                modelphase=modelphase-50000000;index=index+1;
            end
            if(index<sample_count) begin
                expected=$signed(data[index])*256;
                if(!playing || sample!==expected)
                    $fatal(1,"Payload mismatch frame %0d index %0d got %0d want %0d",frames,index,sample,expected);
            end else if(playing || sample!==0) $fatal(1,"Payload end not silent");
        end
        if(frames!=expected_frames)
            $fatal(1,"Payload duration got %0d frames, wanted %0d",frames,expected_frames);
        $display("PASS [PCM payload]: %0d bytes, sum16=%0d, all %0d frames match 8kHz resampling; automatic silence",sample_count,expected_sum,frames);
        $finish;
    end
    initial begin #200000000;$fatal(1,"Payload test timeout");end
endmodule
