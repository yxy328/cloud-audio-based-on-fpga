`timescale 1ns/1ps
module tb_pcm_clip_player;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, sample_ce=0, request=0, edit_allowed=1;
    reg toggle_play=0, restart=0;
    reg [2:0] operation=0;
    reg [15:0] arg0=0,arg1=0,arg2=0;
    wire done,valid,playing;
    wire [2:0] error;
    wire signed [15:0] sample;
    integer i,frames,expected_index,expected_value;
    pcm_clip_player #(.MAX_SAMPLES(32)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.request(request),
        .operation(operation),.arg0(arg0),.arg1(arg1),.arg2(arg2),
        .edit_allowed(edit_allowed),.toggle_play(toggle_play),.restart(restart),
        .done(done),.error(error),.valid(valid),.playing(playing),.sample(sample));
    task command;
        input [2:0] op;
        input [15:0] a,b,c;
        input [2:0] expected_error;
        integer guard;
        begin
            @(negedge clk); operation=op;arg0=a;arg1=b;arg2=c;request=1;
            @(negedge clk); request=0; guard=0;
            while(!done && guard<1000) begin @(negedge clk);guard=guard+1; end
            if(!done || error!==expected_error)
                $fatal(1,"op %0d addr %0d: done=%b error=%0d expected %0d",op,a,done,error,expected_error);
            @(negedge clk);
        end
    endtask
    task tick;
        begin
            @(negedge clk);sample_ce=1;
            @(negedge clk);sample_ce=0;
            repeat(5) @(negedge clk);
        end
    endtask
    task settle;
        begin repeat(6) @(negedge clk); end
    endtask
    task first_block;
        input [7:0] base;
        integer j;
        begin
            for(j=0;j<16;j=j+1)
                command(2,j,base+j,(j==0 ? 1 : (j==15 ? 2 : 0)),0);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);resetn=1;
        command(4,0,0,0,3);
        command(2,0,0,3,3);
        command(1,0,0,0,2);
        command(1,33,0,0,2);
        edit_allowed=0;command(1,17,2312,0,1);edit_allowed=1;
        command(1,17,2312,0,0);
        first_block(128);
        first_block(128); // A complete retry must not double-count checksum.
        command(3,0,0,0,4);
        if(valid) $fatal(1,"Missing tail became valid");
        command(2,16,144,3,0);
        command(3,0,0,0,0);
        if(!valid) $fatal(1,"Complete clip was not committed");
        command(4,0,0,0,0);settle;
        if(sample!==-16'sd32768 || !playing) $fatal(1,"Signed first sample / PLAY failed");
        command(1,16,0,0,1);
        frames=0;
        while(playing && frames<110) begin
            tick;frames=frames+1;
            expected_index=(frames*8192000)/50000000;
            if(expected_index<17) begin
                expected_value=(-128+expected_index)*256;
                if(!playing || sample!==expected_value)
                    $fatal(1,"Resampling frame %0d index %0d sample %0d expected %0d",frames,expected_index,sample,expected_value);
            end else if(playing || sample!==0) $fatal(1,"Clip did not end at its exact duration");
        end
        if(frames!=104) $fatal(1,"17 samples should occupy 104 output frames, got %0d",frames);

        // An interrupted transfer preserves the old active bank.
        command(1,16,2032,0,0);
        for(i=0;i<8;i=i+1) command(2,i,127,(i==0 ? 1 : 0),0);
        command(3,0,0,0,4);
        command(4,0,0,0,0);settle;
        if(sample!==-16'sd32768) $fatal(1,"Interrupted transfer destroyed old clip");
        command(5,0,0,0,0);
        if(playing || sample!==0) $fatal(1,"STOP did not silence output");
        // Malformed continuation and short non-tail block never become valid.
        command(2,0,127,1,0);
        command(2,2,127,0,3);
        command(2,0,127,3,2);
        command(3,0,0,0,4);
        // Checksum failure also preserves the old active bank.
        command(1,16,2033,0,0);
        for(i=0;i<16;i=i+1) command(2,i,127,(i==0 ? 1 : (i==15 ? 2 : 0)),0);
        command(3,0,0,0,5);
        command(4,0,0,0,0);settle;
        if(sample!==-16'sd32768) $fatal(1,"Bad checksum destroyed old clip");
        command(5,0,0,0,0);
        // Retry a previously complete block only partly, then finish the retry.
        command(1,16,2032,0,0);
        for(i=0;i<16;i=i+1) command(2,i,127,(i==0 ? 1 : (i==15 ? 2 : 0)),0);
        command(2,0,127,1,0);
        command(3,0,0,0,4);
        for(i=1;i<16;i=i+1) command(2,i,127,(i==15 ? 2 : 0),0);
        command(3,0,0,0,0);
        command(4,0,0,0,0);settle;
        if(sample!==16'sd32512) $fatal(1,"Replacement bank was not played");
        @(negedge clk);toggle_play=1;
        @(negedge clk);toggle_play=0;settle;
        if(playing || sample!==0) $fatal(1,"Physical toggle did not stop");
        @(negedge clk);restart=1;
        @(negedge clk);restart=0;settle;
        if(!playing || sample!==16'sd32512) $fatal(1,"Physical restart did not play");
        command(5,0,0,0,0);
        // BEGIN at the configured maximum capacity and signed FF expansion.
        command(1,32,8160,0,0);
        for(i=0;i<32;i=i+1) command(2,i,255,(i%16==0 ? 1 : (i%16==15 ? 2 : 0)),0);
        command(3,0,0,0,0);
        command(4,0,0,0,0);settle;
        if(sample!==-16'sd256) $fatal(1,"Signed FF was not -256");
        command(5,0,0,0,0);
        $display("PASS [PCM clip]: double bank, missing/partial/retried blocks, sum16, signed PCM, 8kHz timing, physical controls and STOP");
        $finish;
    end
    initial begin #2000000;$fatal(1,"PCM clip test timeout");end
endmodule
