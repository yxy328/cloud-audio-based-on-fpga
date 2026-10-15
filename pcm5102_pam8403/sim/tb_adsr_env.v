`timescale 1ns/1ps
module tb_adsr_env;
    localparam RELEASE_TICKS=24414;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, sample_ce=0, gate=0;
    wire [15:0] gain;
    wire [2:0] state;
    wire active;
    adsr_env dut(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),
                 .gate(gate),.gain(gain),.state(state),.active(active));
    reg edge_ce=0, edge_gate=0;
    wire [15:0] edge_full, edge_zero;
    wire [2:0] full_state, zero_state;
    adsr_env #(.ATTACK_SAMPLES(0),.DECAY_SAMPLES(1),
        .SUSTAIN_LEVEL(65535),.RELEASE_SAMPLES(0)) full_env (
        .clk(clk),.resetn(resetn),.sample_ce(edge_ce),.gate(edge_gate),
        .gain(edge_full),.state(full_state),.active());
    adsr_env #(.ATTACK_SAMPLES(1),.DECAY_SAMPLES(0),
        .SUSTAIN_LEVEL(0),.RELEASE_SAMPLES(1)) zero_env (
        .clk(clk),.resetn(resetn),.sample_ce(edge_ce),.gate(edge_gate),
        .gain(edge_zero),.state(zero_state),.active());
    integer k, start_level, checks=0, capture, sample_index=0;
    task tick;
        begin
            @(negedge clk); sample_ce=1;
            @(posedge clk); #1;
            $fdisplay(capture,"%0d,%0d,%0d",sample_index,gain,state);
            sample_index=sample_index+1;
            @(negedge clk); sample_ce=0;
            repeat(30) @(negedge clk);
        end
    endtask
    task set_gate;
        input level;
        integer old_gain;
        begin
            old_gain=gain;
            @(negedge clk); gate=level;
            repeat(20) @(negedge clk);
            if (gain != old_gain) $fatal(1,"Gate transition jumped in amplitude");
        end
    endtask
    // Independent closed-form linear reference; no DUT counters inspected.
    task ramp;
        input integer begin_level, end_level, length, count, end_state;
        integer j, expected;
        begin
            for(j=1;j<=count;j=j+1) begin
                tick;
                if(end_level>=begin_level)
                    expected=begin_level+((end_level-begin_level)*j)/length;
                else expected=begin_level-((begin_level-end_level)*j)/length;
                if(gain != expected)
                    $fatal(1,"Ramp sample %0d/%0d: got %0d expected %0d",j,length,gain,expected);
                checks=checks+1;
            end
            if(count==length && state!=end_state)
                $fatal(1,"Wrong endpoint state: got %0d expected %0d",state,end_state);
        end
    endtask
    task edge_tick;
        begin
            @(negedge clk); edge_ce=1;
            @(posedge clk); #1;
            @(negedge clk); edge_ce=0;
            repeat(20) @(negedge clk);
        end
    endtask
    initial begin
        capture=$fopen("sim/build/envelope_samples.csv","w");
        $fdisplay(capture,"sample_index,gain,state");
        repeat(4) @(negedge clk); resetn=1;
        tick;
        if(gain!=0 || state!=0 || active) $fatal(1,"Reset/idle");
        set_gate(1);
        ramp(0,65535,98,98,2);
        ramp(65535,39321,3906,3906,3);
        repeat(200) begin
            tick;
            if(gain!=39321 || state!=3 || !active) $fatal(1,"Sustain not stable");
        end
        set_gate(0);
        ramp(39321,0,RELEASE_TICKS,RELEASE_TICKS,0);
        tick;
        if(gain!=0 || active) $fatal(1,"Release endpoint not silent");
        // Release in mid attack lasts the full R duration from current level.
        set_gate(1); ramp(0,65535,98,17,1);
        start_level=gain;
        set_gate(0); ramp(start_level,0,RELEASE_TICKS,RELEASE_TICKS,0);
        // Release in decay, then retrigger partway through release.
        set_gate(1); ramp(0,65535,98,98,2);
        ramp(65535,39321,3906,357,2);
        start_level=gain;
        set_gate(0); ramp(start_level,0,RELEASE_TICKS,300,4);
        start_level=gain;
        set_gate(1); ramp(start_level,65535,98,98,2);
        ramp(65535,39321,3906,3906,3);
        // Gate edges during the 16-cycle divider must cancel its old result.
        @(negedge clk); gate=0;
        repeat(5) @(negedge clk);
        if(gain!=39321) $fatal(1,"Release setup jumped");
        gate=1;
        repeat(5) @(negedge clk);
        gate=0;
        repeat(20) @(negedge clk);
        ramp(39321,0,RELEASE_TICKS,RELEASE_TICKS,0);
        // A very low release needs fractional steps, not an early cut-off.
        set_gate(1); ramp(0,65535,98,1,1);
        start_level=gain;
        set_gate(0); ramp(start_level,0,RELEASE_TICKS,RELEASE_TICKS,0);
        // No sample enable means no envelope movement, even while held.
        set_gate(1); ramp(0,65535,98,22,1);
        start_level=gain;
        repeat(100) @(negedge clk);
        if(gain!=start_level) $fatal(1,"Envelope moved without sample_ce");
        // Zero durations clamp to one sample; sustain endpoints 0 and 65535.
        edge_gate=1;
        repeat(20) @(negedge clk);
        edge_tick;
        if(edge_full!=65535 || edge_zero!=65535 || full_state!=2 || zero_state!=2)
            $fatal(1,"One-sample attack");
        edge_tick;
        if(edge_full!=65535 || edge_zero!=0 || full_state!=3 || zero_state!=3)
            $fatal(1,"One-sample decay / extreme sustain");
        edge_gate=0;
        repeat(20) @(negedge clk);
        edge_tick;
        if(edge_full!=0 || edge_zero!=0 || full_state!=0 || zero_state!=0)
            $fatal(1,"One-sample release");
        resetn=0; repeat(3) @(negedge clk);
        if(gain!=0 || state!=0 || active) $fatal(1,"Reset during attack");
        $fclose(capture);
        $display("PASS [ADSR]: %0d exact linear samples; A=98 D=3906 S=39321 R=%0d; mid-stage release, continuous retrigger, divider cancellation, low-level release, CE hold, zero/one durations, extreme sustain, reset",checks,RELEASE_TICKS);
        $finish;
    end
    initial begin #100000000; $fatal(1,"ADSR test timeout"); end
endmodule
