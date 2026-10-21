`timescale 1ns/1ps
module tb_tdm_adsr;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0,ev=0,test32=0;
    reg [129:0] cfg={1'b1,16'd4,16'd4,16'd8,9'd128,24'd4194304,24'd4194304,24'd2097152};
    wire busy,overrun;wire [5:0] count;wire signed [15:0] pcm;
    tdm_synth #(.RUNTIME_ADSR(1)) dut(.tuning_ratio(16'd16384),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),.clk(clk),.resetn(resetn),.sample_ce(ce),
        .event_valid(ev),.event_inc(32'd23012828),.event_timbre(3'd0),.event_frames(17'd20),
        .event_adsr(cfg),.chord_valid(1'b0),.test_valid(test32),.vibrato_enabled(1'b0),
        .voice_active(),.voice_count(count),.sample(pcm),.busy(busy),.overrun(overrun),.event_ready());
    integer i,cycles,max_cycles=0,expected;
    reg [364:0] ctx;
    task frame;
        begin ce=1;@(negedge clk);ce=0;cycles=1;
            while(busy)begin @(negedge clk);cycles=cycles+1;end
            if(cycles>max_cycles)max_cycles=cycles;
            if(overrun||cycles>=1024)$fatal(1,"Runtime TDM deadline");
            ctx=dut.peek_context(0);
        end
    endtask
    task gain_is;
        input integer value;
        begin frame;if(((ctx>>245)&511)!=value)$fatal(1,"TDM ADSR got %0d expected %0d",(ctx>>245)&511,value);end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;wait(!busy);@(negedge clk);
        ev=1;@(negedge clk);ev=0;
        cfg={1'b1,16'd1,16'd1,16'd1,9'd0,24'hffffff,24'hffffff,24'hffffff};
        // Wait for the reserved voice's fade/initialization to finish.
        frame;
        while(((ctx>>254)&131071)!=20)frame;
        gain_is(64);gain_is(128);gain_is(192);gain_is(256);
        gain_is(224);gain_is(192);gain_is(160);gain_is(128);
        repeat(12)gain_is(128);gain_is(128);
        for(i=1;i<=8;i=i+1)gain_is(128-16*i);
        repeat(6)frame;if(count || pcm) $fatal(1,"Custom envelope never released");
        test32=1;@(negedge clk);test32=0;
        repeat(400)frame;
        if(count!=32 || ((ctx>>245)&511)!=256) $fatal(1,"TEST32 inherited edited ADSR");
        resetn=0;repeat(4)@(negedge clk);resetn=1;wait(!busy);@(negedge clk);
        // All 32 contexts carry different edited sustain values, including
        // notes accepted back-to-back before a single sample boundary.
        for(i=0;i<32;i=i+1)begin
            cfg={1'b1,16'd1,16'd1,16'd2,9'd0,24'hffffff,24'hffffff,24'd8388608};
            cfg[80:72]=(i+1)*4;ev=1;@(negedge clk);
        end
        ev=0;cfg=0;repeat(36)frame;
        if(count!=32) $fatal(1,"Edited 32-voice occupancy");
        for(i=0;i<32;i=i+1)begin
            ctx=dut.peek_context(i);
            if(((ctx>>245)&511)!=(i+1)*4)$fatal(1,"Voice %0d lost independent sustain",i);
        end
        repeat(35)frame;if(count || pcm)$fatal(1,"32 edited release tails did not end");
        $display("PASS TDM ADSR: exact A4/D4/S128/R8, event snapshot, timed note-off, silence, TEST32 bypass, 32 voices max %0d clocks",max_cycles);$finish;
    end
    initial begin #20000000;$fatal(1,"TDM ADSR timeout");end
endmodule
