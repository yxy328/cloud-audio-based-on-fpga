`timescale 1ns/1ps
module tb_display_mode_control;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0, ce=0, button=0;
    wire restart;
    wire [1:0] visual;
    reg xy_write=0;
    reg visual_write=0;
    reg [1:0] remote_mode=0;
    reg [1:0] ratio_in=0,phase_in=0;
    wire [1:0] ratio,phase;
    integer restarts=0;
    display_mode_control #(.HOLD_FRAMES(4)) dut (
        .clk(clk),.resetn(resetn),.frame_ce(ce),.button_level(button),
        .xy_write(xy_write),.xy_ratio(ratio_in),.xy_phase(phase_in),
        .visual_write(visual_write),.remote_mode(remote_mode),
        .reference_ratio(ratio),.reference_phase(phase),
        .restart(restart),.visual_mode(visual));
    always @(negedge clk) if(restart) restarts=restarts+1;
    task frames;
        input integer count; integer n;
        begin for(n=0;n<count;n=n+1) begin
            @(negedge clk); ce=1;
            @(negedge clk); ce=0;
        end end
    endtask
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        @(negedge clk); button=1; frames(3);
        if(restart || visual) $fatal(1,"Short hold took action before release");
        @(negedge clk); button=0;
        repeat(3) @(negedge clk);
        if(restarts!=1 || visual) $fatal(1,"Short release did not restart exactly once");
        button=1; frames(4);
        if(visual!=1 || restart) $fatal(1,"Long hold did not switch without restart");
        frames(20);
        if(visual!=1) $fatal(1,"Held button repeated its toggle");
        @(negedge clk); button=0;
        repeat(3) @(negedge clk);
        if(restarts!=1) $fatal(1,"Long release restarted the score");
        button=1; frames(4);
        if(visual!=2) $fatal(1,"Second hold did not select XY");
        button=0;frames(1);
        if(ratio!=2 || phase!=0) $fatal(1,"Default XY must be an eight");
        // Every short release selects one complete reference preset, never restart.
        button=1;frames(1);button=0;frames(1);
        if(ratio!=3 || phase!=0 || restarts!=1) $fatal(1,"Multi-loop preset");
        button=1;frames(1);button=0;frames(1);
        if(ratio!=1 || phase!=2 || restarts!=1) $fatal(1,"Circle preset");
        button=1;frames(1);button=0;frames(1);
        if(ratio!=1 || phase!=1) $fatal(1,"Ellipse preset");
        button=1;frames(1);button=0;frames(1);
        if(ratio!=1 || phase!=0) $fatal(1,"Line preset");
        button=1;frames(1);button=0;frames(1);
        if(ratio!=0) $fatal(1,"Live mix preset");
        button=1;frames(1);button=0;frames(1);
        if(ratio!=2 || phase!=0) $fatal(1,"Preset wrap");
        ratio_in=3;phase_in=3;xy_write=1;frames(1);xy_write=0;frames(1);
        if(ratio!=3 || phase!=3 || restarts!=1) $fatal(1,"Independent remote ratio/phase");
        button=0;frames(1);button=1;frames(4);
        if(visual!=3) $fatal(1,"Third hold did not select spectrum");
        button=0;frames(1);button=1;frames(4);
        if(visual!=0) $fatal(1,"Fourth hold did not return to guide");
        // Remote page requests win over a threshold/release and suppress
        // the remainder of a held local button; no score restart is emitted.
        button=0;frames(1);button=1;frames(3);
        remote_mode=2;visual_write=1;frames(1);visual_write=0;
        if(visual!=2 || restart)$fatal(1,"Remote page did not win at hold threshold");
        frames(8);button=0;frames(1);
        if(visual!=2 || restarts!=1)$fatal(1,"Held local key undid remote page");
        button=1;frames(1);button=0;remote_mode=1;visual_write=1;frames(1);visual_write=0;
        if(visual!=1 || restarts!=1)$fatal(1,"Remote/local release race restarted score");
        @(negedge clk); resetn=0;
        repeat(3) @(negedge clk); button=0; resetn=1;
        repeat(3) @(negedge clk);
        if(visual || restart || restarts!=1) $fatal(1,"Reset leaked a button action");
        $display("PASS display mode: short release, threshold, one action/hold, long release suppression, guide/wave/XY/spectrum cycle, reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"Mode control timeout"); end
endmodule
