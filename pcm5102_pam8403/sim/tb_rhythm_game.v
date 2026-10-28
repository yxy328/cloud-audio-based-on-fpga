`timescale 1ns/1ps
module tb_rhythm_game;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,playing=0,ms_tick=0,event_start=0,event_end=0;
    reg [11:0] touch_keys=0,event_keys=0;
    reg [15:0] event_duration=100;
    reg [7:0] settings=8'he4;
    wire session,holding;wire [23:0] score;wire [11:0] combo,best,miss,flash_keys;
    wire [1:0] judge;wire [7:0] flash;wire [111:0] snapshot;
    rhythm_game dut(.clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),
        .event_start(event_start),.event_end(event_end),.touch_keys(touch_keys),
        .event_keys(event_keys),.event_duration(event_duration),.settings(settings),
        .session(session),.score_bcd(score),.combo_bcd(combo),.best_bcd(best),.miss_bcd(miss),
        .judgement(judge),.flash(flash),.flash_keys(flash_keys),.holding(holding),.snapshot(snapshot));
    task elapse;
        input integer count;integer i;
        begin for(i=0;i<count;i=i+1)begin
            @(negedge clk);ms_tick=1;@(negedge clk);ms_tick=0;repeat(38)@(negedge clk);
        end end
    endtask
    task start_note;
        input [11:0] keys;input [15:0] duration;
        begin @(negedge clk);event_keys=keys;event_duration=duration;event_start=1;
            @(negedge clk);event_start=0;repeat(40)@(negedge clk);end
    endtask
    task press;
        input [11:0] keys;
        begin @(negedge clk);touch_keys=keys;repeat(40)@(negedge clk);end
    endtask
    task end_note;
        begin @(negedge clk);event_end=1;@(negedge clk);event_end=0;repeat(40)@(negedge clk);end
    endtask
    task expect_result;
        input [23:0] expected_score;input [11:0] expected_combo,expected_miss;
        begin if(score!==expected_score || combo!==expected_combo || miss!==expected_miss)
            $fatal(1,"score=%h combo=%h miss=%h expected=%h/%h/%h",score,combo,miss,expected_score,expected_combo,expected_miss);end
    endtask
    task new_game;
        begin touch_keys=0;playing=0;repeat(40)@(negedge clk);playing=1;repeat(40)@(negedge clk);end
    endtask
    integer k;
    initial begin
        repeat(4)@(negedge clk);resetn=1;playing=1;repeat(40)@(negedge clk);
        start_note(1,200);press(1);expect_result(24'h001000,1,0);
        // A held key cannot score a second tap. Fresh release/repress is needed.
        start_note(1,200);elapse(121);expect_result(24'h001000,0,1);press(0);
        // Early hit at -40ms is consumed by the following note.
        press(2);elapse(40);start_note(2,200);expect_result(24'h002000,1,1);press(0);
        // +90ms is Good in the normal +/-120ms window.
        start_note(4,200);elapse(90);press(4);expect_result(24'h002500,2,1);press(0);
        // Chord edges may arrive separately within the same window.
        start_note(12'h009,200);press(1);elapse(20);press(9);expect_result(24'h003500,3,1);press(0);
        // Long note awards only when it finishes, not merely at acquisition.
        start_note(16,600);press(16);elapse(300);expect_result(24'h003500,3,1);
        if(!holding)$fatal(1,"long note not held");elapse(300);end_note;
        expect_result(24'h005000,4,1);press(0);
        // Early release invalidates the long note exactly once.
        start_note(32,600);press(32);elapse(200);press(0);elapse(400);end_note;
        expect_result(24'h005000,0,2);
        // An edge older than the window never returns after the 8-bit timer wraps.
        press(64);elapse(400);start_note(64,200);elapse(121);expect_result(24'h005000,0,3);press(0);
        // Dense repeated events still need individual edges and increment BCD.
        for(k=0;k<16;k=k+1)begin start_note(128,1);press(128);press(0);end
        expect_result(24'h021000,12'h016,3);
        if(best!==12'h016)$fatal(1,"best combo did not update");
        playing=0;repeat(40)@(negedge clk);
        if(!session || score!=24'h021000)$fatal(1,"result disappeared after song");
        playing=1;repeat(40)@(negedge clk);expect_result(0,0,0);
        // Maximum chart length and maximum award exercise every high BCD carry
        // and the registered ROM address at the legal 768-credit upper bound.
        for(k=0;k<256;k=k+1)begin
            start_note(1,500);press(1);elapse(1);end_note;press(0);
        end
        expect_result(24'h384000,12'h256,0);
        if(best!==12'h256)$fatal(1,"256-event maximum combo");
        new_game;
        for(k=0;k<256;k=k+1)begin start_note(1,1);end_note;end
        expect_result(0,0,12'h256);
        playing=0;repeat(40)@(negedge clk);playing=1;repeat(40)@(negedge clk);
        start_note(1,600);press(1);elapse(50);playing=0;repeat(80)@(negedge clk);
        expect_result(0,0,1);press(0);
        playing=1;repeat(40)@(negedge clk);expect_result(0,0,0);
        for(k=0;k<4;k=k+1)begin
            settings=8'he0|(k<<2);
            new_game;press(1);elapse(80+k*40);start_note(1,300);expect_result(24'h000500,1,0);
            new_game;press(1);elapse(81+k*40);start_note(1,300);elapse(81+k*40);expect_result(0,0,1);
            new_game;start_note(1,300);elapse(80+k*40);press(1);expect_result(24'h000500,1,0);
            new_game;start_note(1,300);elapse(81+k*40);press(1);expect_result(0,0,1);
        end
        new_game;
        settings=8'h64;start_note(1,100);press(1);elapse(150);expect_result(0,0,0);
        if(session)$fatal(1,"disabled game kept session");
        $display("PASS rhythm_game: single/chord/repeat/long, all4 inclusive +/-window edges and expired timestamps, full256 x1500=384000, BCD256 combo/miss, STOP hold rejection, reset, disable");$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
