`timescale 1ns/1ps
module tb_tdm_queue;
    reg clk=0,resetn=0,ce=0,event_valid=0,chord=0,test32=0;
    reg [31:0] inc=0;
    wire [31:0] active;
    wire [5:0] count;
    wire signed [15:0] pcm;
    wire busy,overrun;
    integer i,cycles,max_cycles=0,positive_clip=0,negative_clip=0;
    always #10 clk=~clk;
    tdm_synth dut(.clk(clk),.resetn(resetn),.sample_ce(ce),.event_valid(event_valid),
        .chord_valid(chord),.test_valid(test32),.vibrato_enabled(1'b0),
        .event_inc(inc),.event_timbre(3'd0),.event_frames(17'd1000),
        .voice_active(active),.voice_count(count),.sample(pcm),.busy(busy),.overrun(overrun));
    task run_frame;
        begin
            ce=1; @(negedge clk); ce=0; cycles=1;
            while(busy) begin @(negedge clk); cycles=cycles+1; end
            if(cycles>max_cycles) max_cycles=cycles;
            if(cycles>=1024) $fatal(1,"TDM deadline on full command queue");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); resetn=1; wait(!busy); @(negedge clk);
        for(i=0;i<64;i=i+1) begin event_valid=1; inc=1000+i; @(negedge clk); end
        event_valid=0;
        run_frame;
        if(overrun || count!=32 || dut.write_ptr-dut.read_ptr!=32)
            $fatal(1,"First half of 64-command burst");
        for(i=0;i<32;i=i+1)
            if(((dut.peek_context(i) >> 326) & 32'hffffffff)!=1000+i) $fatal(1,"First batch allocation");
        run_frame;
        if(overrun || count!=32 || dut.write_ptr!=dut.read_ptr) $fatal(1,"Second half burst");
        for(i=0;i<32;i=i+1)
            if(((dut.peek_context(i) >> 326) & 32'hffffffff)!=1032+i) $fatal(1,"Oldest replacement %0d",i);
        // An event accepted during a scan belongs to the next frame.
        ce=1; @(negedge clk); ce=0; repeat(100) @(negedge clk);
        event_valid=1; inc=9999; @(negedge clk); event_valid=0;
        wait(!busy); @(negedge clk);
        if(((dut.peek_context(0) >> 326) & 32'hffffffff)==9999) $fatal(1,"Mid-frame event altered a snapshot");
        run_frame;
        if(((dut.peek_context(0) >> 326) & 32'hffffffff)!=9999 || overrun) $fatal(1,"Mid-frame event lost");
        // Deliberate over-capacity input must be diagnosed and reset cleanly.
        for(i=0;i<65;i=i+1) begin event_valid=1; inc=i; @(negedge clk); end
        event_valid=0;
        if(!overrun) $fatal(1,"FIFO overflow not reported");
        resetn=0; repeat(4) @(negedge clk); resetn=1; wait(!busy); @(negedge clk);
        run_frame;
        if(overrun || pcm || count || active) $fatal(1,"Reset did not silence/clear FIFO");
        // 32 coherent notes exceed signed16 range. Clip rather than wrapping.
        for(i=0;i<32;i=i+1) begin event_valid=1; inc=23012828; @(negedge clk); end
        event_valid=0;
        for(i=0;i<450;i=i+1) begin
            run_frame;
            if(pcm==16'sh7fff) positive_clip=positive_clip+1;
            if(pcm==16'sh8000) negative_clip=negative_clip+1;
        end
        if(!positive_clip || !negative_clip || overrun || count!=32)
            $fatal(1,"32-note signed saturation");
        // Deliberately violate the frame budget; hardware reports underrun.
        ce=1; @(negedge clk); ce=0; repeat(3) @(negedge clk);
        ce=1; @(negedge clk); ce=0;
        if(!overrun) $fatal(1,"Missed sample deadline not reported");
        $display("PASS TDM FIFO64, 32-command budget, oldest replacement, frame snapshot, 32-note signed saturation, overflow/reset/deadline diagnostics; max %0d clocks",max_cycles);
        $finish;
    end
    initial begin #15_000_000; $fatal(1,"TDM queue timeout"); end
endmodule
