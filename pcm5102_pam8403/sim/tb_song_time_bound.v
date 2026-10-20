`timescale 1ns/1ps
// Longest legal score, including a blocked display after audio finishes.
// Fast-forward elapsed time between event boundaries; RAM/command handshakes,
// cursor advancement, lookahead and gate outputs still use real RTL clocks.
module tb_song_time_bound;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,request=0,ready=0;
    reg [2:0] op=0;
    reg [15:0] a=0,b=0,c=0;
    wire done,playing,gate,spawn;
    wire [2:0] error;
    wire [6:0] keys;
    wire [15:0] delay_ms;
    downloadable_song #(.CLK_HZ(1000),.ENABLE_LOOKAHEAD(1)) dut(
        .clk(clk),.resetn(resetn),.request(request),.operation(op),
        .arg0(a),.arg1(b),.arg2(c),.edit_allowed(1'b1),
        .note_map({8'd72,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60}),
        .toggle_play(1'b0),.restart(1'b0),.done(done),.error(error),
        .playing(playing),.gate(gate),.guide_keys(keys),.note_ready(ready),
        .note_spawn(spawn),.spawn_delay_ms(delay_ms));
    integer i,waited,spawn_count=0;
    reg [22:0] stopped_time;
    always @(posedge clk)if(resetn && spawn)begin
        spawn_count=spawn_count+1;
        if(delay_ms!==0)$fatal(1,"late display event should have zero delay");
    end
    task command;
        input [2:0] operation;
        input [15:0] arg0,arg1,arg2;
        begin
            @(negedge clk);op=operation;a=arg0;b=arg1;c=arg2;request=1;
            @(negedge clk);request=0;waited=0;
            while(!done && waited<1000)begin @(negedge clk);waited=waited+1;end
            if(!done || error!=0)$fatal(1,"long score command failed: op=%0d error=%0d",op,error);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        if(dut.TIME_BITS!=23)$fatal(1,"production timeline must use 23 bits");
        command(1,128,0,0);
        for(i=0;i<128;i=i+1)command(2,i,60,60000);
        command(3,0,0,0);command(4,0,0,0);
        wait(dut.state==5);
        for(i=0;i<128;i=i+1)begin
            wait(dut.cur_index==i && dut.cur_have);
            if(i<127)wait(dut.next_have);
            @(negedge clk);
            if(dut.cur_end_ms !== 1500+(i+1)*60000)$fatal(1,"end time wrapped at event %0d",i);
            // Last audible millisecond, then the exact end boundary.
            dut.elapsed_ms=dut.cur_end_ms-2;
            @(negedge clk);
            if(keys!==1 || gate!==0)$fatal(1,"1ms articulation gap at %0d",i);
            @(negedge clk);
        end
        repeat(3)@(negedge clk);
        if(!playing || !dut.current_finished || keys!=0 || gate!=0)
            $fatal(1,"blocked display must drain after final audio note");
        stopped_time=dut.elapsed_ms;
        if(stopped_time!==23'd7681500)$fatal(1,"maximum score duration incorrect");
        // Backpressure cannot turn a finished score into a wrapping timer.
        repeat(2000)@(negedge clk);
        if(dut.elapsed_ms!==stopped_time || spawn_count!=0)$fatal(1,"finished timeline advanced under backpressure");
        ready=1;waited=0;
        while(playing && waited<2000)begin @(negedge clk);waited=waited+1;end
        if(playing || spawn_count!=128)$fatal(1,"blocked lookahead failed to drain all 128 notes");
        $display("PASS song bound: 128 x 60000ms, 23-bit horizon, note-off boundaries, stalled visual drain without wrap");
        $finish;
    end
    initial begin #1000000;$fatal(1,"long-score timeout");end
endmodule
