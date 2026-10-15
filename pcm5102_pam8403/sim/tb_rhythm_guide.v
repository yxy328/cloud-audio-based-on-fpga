`timescale 1ns/1ps
module tb_rhythm_guide;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0;
    reg [8:0] x=0;
    reg [6:0] y=0;
    reg [6:0] guide=0, touch=0, spawn_keys=0;
    reg playing=0, tick=0, spawn=0;
    reg [15:0] delay_ms=0;
    wire ready, overflow;
    wire [4:0] red, green, blue;
    rhythm_guide #(.NOTE_SLOTS(2)) dut (
        .clk(clk),.resetn(resetn),.pixel_x(x),.pixel_y(y),
        .guide_keys(guide),.touch_keys(touch),.playing(playing),.ms_tick(tick),
        .note_spawn(spawn),.spawn_keys(spawn_keys),.spawn_delay_ms(delay_ms),
        .note_ready(ready),.note_overflow(overflow),.red(red),.green(green),.blue(blue)
    );
    task elapse;
        input integer count;
        integer k;
        begin
            for(k=0;k<count;k=k+1) begin
                @(negedge clk); tick=1;
                @(negedge clk); tick=0;
            end
            #1;
        end
    endtask
    task submit;
        input [6:0] key_mask;
        input [15:0] ms;
        begin
            @(negedge clk); spawn_keys=key_mask; delay_ms=ms; spawn=1;
            @(negedge clk); spawn=0;
            #1;
        end
    endtask
    task pixel;
        input [8:0] px;
        input [6:0] py;
        input [14:0] expected;
        begin
            x=px; y=py; #1;
            if({red,green,blue} !== expected)
                $fatal(1,"pixel (%0d,%0d): RGB=%0d/%0d/%0d expected=%h",px,py,red,green,blue,expected);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        resetn=1; playing=1;
        @(negedge clk);
        if(!ready) $fatal(1,"empty renderer not ready");
        pixel(0,0,15'd0);
        pixel(64,20,15'd0);
        pixel(6,64,15'd0);
        guide=7'b0000001; touch=7'b0000001;
        pixel(6,54,{5'd31,5'd18,5'd0});
        pixel(6,60,{5'd31,5'd31,5'd31});
        pixel(14,60,{5'd2,5'd3,5'd5});
        touch=7'b1000000;
        pixel(54,60,{5'd0,5'd25,5'd6});
        submit(7'b0000001,1500);
        pixel(6,2,{5'd0,5'd24,5'd31});
        pixel(14,2,{5'd1,5'd1,5'd2});
        elapse(750);
        pixel(6,28,{5'd0,5'd24,5'd31});
        pixel(6,2,{5'd1,5'd1,5'd2});
        elapse(750);
        pixel(6,54,{5'd0,5'd24,5'd31});
        // A second equal pitch can coexist; a third reports overflow.
        submit(7'b0000001,750);
        pixel(6,28,{5'd0,5'd24,5'd31});
        if(ready) $fatal(1,"full renderer still ready");
        submit(7'b0000010,1500);
        if(!overflow) $fatal(1,"full renderer did not report overflow");
        elapse(100);
        if(!ready) $fatal(1,"hit window did not release a slot");
        if(!overflow) $fatal(1,"overflow was not sticky");
        @(negedge clk); playing=0;
        @(negedge clk); #1;
        if(overflow || dut.used!=0) $fatal(1,"stop did not clear notes/overflow");
        @(negedge clk); playing=1;
        // Long lookahead waits offscreen; a chord occupies multiple lanes.
        submit(7'b1000001,1600);
        pixel(6,2,{5'd1,5'd1,5'd2});
        elapse(100);
        pixel(6,2,{5'd0,5'd24,5'd31});
        pixel(54,2,{5'd0,5'd24,5'd31});
        elapse(1500);
        pixel(54,54,{5'd0,5'd24,5'd31});
        elapse(100);
        if(dut.used!=0) $fatal(1,"notes never retired");
        $display("PASS rhythm_guide: seven lanes, exact 1500ms fall, late/early lookahead, chords, touch, overflow, stop");
        $finish;
    end
    initial begin #1000000; $fatal(1,"rhythm guide timeout"); end
endmodule
