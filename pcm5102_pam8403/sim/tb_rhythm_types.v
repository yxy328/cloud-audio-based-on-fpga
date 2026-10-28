`timescale 1ns/1ps
module tb_rhythm_types;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,tick=0,start=0,stop_event=0,gesture=0;
    reg [11:0] keys=0,target=0;reg [1:0] kind=0;
    reg [15:0] duration=100;reg [7:0] settings=8'he4;
    wire [23:0] score;wire [11:0] combo,miss;wire holding;
    rhythm_game #(.TYPED_NOTES(1)) dut(.clk(clk),.resetn(resetn),.playing(playing),.ms_tick(tick),
        .event_start(start),.event_end(stop_event),.touch_keys(keys),.event_keys(target),
        .event_duration(duration),.event_type(kind),.gesture(gesture),.settings(settings),
        .score_bcd(score),.combo_bcd(combo),.miss_bcd(miss),.holding(holding));
    task settle;begin repeat(90)@(negedge clk);end endtask
    task elapse;
        input integer ms;integer n;
        begin for(n=0;n<ms;n=n+1)begin @(negedge clk);tick=1;@(negedge clk);tick=0;settle;end end
    endtask
    task note;
        input [1:0] t;input [11:0] mask;input [15:0] length;
        begin @(negedge clk);kind=t;target=mask;duration=length;start=1;
            @(negedge clk);start=0;settle;end
    endtask
    task expect_score;
        input [23:0] expected;input [11:0] misses;
        begin settle;if(score!==expected || miss!==misses)$fatal(1,"typed score %h miss%h expected %h/%h",score,miss,expected,misses);end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;playing=1;settle;
        // TAP stays a tap even if its musical duration exceeds 500ms.
        note(0,1,1000);keys=1;settle;
        if(holding)$fatal(1,"explicit TAP became HOLD");expect_score(24'h001000,0);
        keys=0;settle;elapse(250);
        // Short explicit HOLD, acquisition awards nothing, release fails.
        note(1,2,200);keys=2;settle;if(!holding)$fatal(1,"short HOLD not acquired");
        expect_score(24'h001000,0);keys=0;settle;expect_score(24'h001000,1);
        note(1,2,200);keys=2;settle;elapse(199);
        stop_event=1;@(negedge clk);stop_event=0;settle;keys=0;expect_score(24'h002500,1);
        // DRAG accepts contact held for longer than the timestamp RAM window.
        keys=4;settle;elapse(300);note(2,4,100);expect_score(24'h003500,1);
        note(2,4,100);expect_score(24'h004500,1);
        // FLICK requires motion; contact by itself cannot score.
        keys=0;settle;note(3,8,300);keys=8;settle;expect_score(24'h004500,1);
        gesture=1;settle;gesture=0;expect_score(24'h005500,1);
        // A latched/stale gesture cannot hit the following note.
        note(3,8,300);expect_score(24'h005500,1);elapse(121);expect_score(24'h005500,2);
        // Touch slide: an existing target contact moves onto another pad.
        note(3,8,300);keys=24;settle;expect_score(24'h006500,2);
        keys=0;settle;
        // DRAG chords still require every mapped key.
        note(2,3,100);keys=1;settle;expect_score(24'h006500,2);
        keys=3;settle;expect_score(24'h007500,2);
        // The target may be released while the next pad is acquired.
        keys=8;settle;note(3,8,300);keys=16;settle;expect_score(24'h008500,2);
        keys=0;settle;note(3,8,300);gesture=1;settle;gesture=0;
        keys=8;settle;expect_score(24'h008500,2);elapse(121);expect_score(24'h008500,3);
        // Disabling HOLD changes the explicit HOLD to a normal TAP.
        keys=0;settle;settings[6]=0;note(1,4,1000);keys=4;settle;
        if(holding)$fatal(1,"disabled HOLD still acquired");expect_score(24'h009500,3);
        $display("PASS four types: explicit long TAP/short HOLD, broken/completed HOLD, held/repeated DRAG/chord, FLICK motion/gesture/slide/stale rejection, settings");$finish;
    end
    initial begin #20000000;$fatal(1,"typed judgement timeout");end
endmodule
