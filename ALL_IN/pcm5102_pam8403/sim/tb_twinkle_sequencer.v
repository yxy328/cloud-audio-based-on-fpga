`timescale 1ns/1ps
module tb_twinkle_sequencer;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, toggle_play=0, restart=0;
    reg [4:0] divider=0;
    always @(posedge clk) begin
        if(!resetn || divider==19) divider<=0;
        else divider<=divider+1'b1;
    end
    wire ce=divider==19;
    wire playing;
    wire [5:0] note_index;
    wire [3:0] gates;
    wire [127:0] increments;
    twinkle_sequencer dut(.clk(clk),.resetn(resetn),.sample_ce(ce),
        .toggle_play(toggle_play),.restart(restart),.playing(playing),
        .note_index(note_index),.gates(gates),.phase_increments(increments));
    // Independent musical score, not the implementation's lookup function.
    reg [8*42-1:0] score="CCGGAAGFFEEDDCGGFFEEDGGFFEEDCCGGAAGFFEEDDC";
    integer n, duration, frames=0, checks=0;
    reg [127:0] held_pitch;
    reg [3:0] held_gates;
    function [31:0] expected_pitch;
        input [7:0] letter;
        real hz;
        begin
            case(letter)
                "C":hz=523.2511306011972;
                "D":hz=587.3295358348151;
                "E":hz=659.2551138257398;
                "F":hz=698.4564628660078;
                "G":hz=783.9908719634985;
                "A":hz=880.0;
                default:hz=0;
            endcase
            expected_pitch=$rtoi(hz*4294967296.0/48828.125+0.5);
        end
    endfunction
    task advance;
        input integer amount;
        integer k;
        begin
            for(k=0;k<amount;k=k+1) begin
                @(negedge clk);while(!ce) @(negedge clk);
                @(posedge clk);#1;frames=frames+1;
            end
        end
    endtask
    task pulse_toggle;
        begin @(negedge clk);toggle_play=1;@(negedge clk);toggle_play=0;end
    endtask
    initial begin
        repeat(3) @(negedge clk);resetn=1;
        advance(5);
        if(playing || gates!=0) $fatal(1,"Power-on must be silent");
        pulse_toggle;
        if(!playing || gates!=14 || note_index!=0) $fatal(1,"Start failed");
        advance(1952);if(gates!=14) $fatal(1,"Intro ended early");
        advance(1);
        for(n=0;n<42;n=n+1) begin
            if(note_index!=n || gates!=15 || increments[31:0]!=expected_pitch(score[(41-n)*8 +: 8]))
                $fatal(1,"Wrong musical event %0d, index=%0d inc=%0d",n,note_index,increments[31:0]);
            duration=((n%7)==6) ? 2*19531-4883 : 19531-4883;
            held_gates=gates;held_pitch=increments;
            repeat(2) @(negedge clk);
            if(gates!=held_gates || increments!=held_pitch) $fatal(1,"Score changed between frames");
            advance(duration-1);
            if(gates!=15 || note_index!=n) $fatal(1,"Note-on duration off by one");
            advance(1);if(gates!=14) $fatal(1,"Missing articulation gap");
            advance(4882);if(gates!=14 || note_index!=n) $fatal(1,"Gap duration off by one");
            advance(1);checks=checks+1;
        end
        if(gates!=0 || !playing) $fatal(1,"Expected release tail");
        advance(17099);if(!playing) $fatal(1,"Tail ended early");
        advance(1);if(playing || gates!=0) $fatal(1,"Song failed to stop");
        if(frames!=5+1953+48*19531+17100) $fatal(1,"Wrong full song frame count: %0d",frames);
        advance(100);if(playing || gates!=0) $fatal(1,"Unexpected auto-loop");
        pulse_toggle;advance(1953+2*19531+20);
        if(note_index!=2) $fatal(1,"Stop setup failed to reach G5");
        held_pitch=increments;
        pulse_toggle;
        if(playing || gates!=0 || increments!=held_pitch) $fatal(1,"Stop must preserve tail pitch");
        @(negedge clk);toggle_play=1;restart=1;
        @(negedge clk);toggle_play=0;restart=0;
        if(!playing || note_index!=0 || gates!=14) $fatal(1,"Restart priority failed");
        advance(1953+3*19531+20);
        if(note_index!=3) $fatal(1,"Restart setup failed to reach later note");
        @(negedge clk);restart=1;@(negedge clk);restart=0;
        if(note_index!=0 || gates!=14) $fatal(1,"Active restart failed");
        @(negedge clk);resetn=0;@(negedge clk);
        if(playing || gates!=0) $fatal(1,"Reset failed");
        $display("PASS [twinkle sequencer]: %0d exact score events; production beat/gap/intro/tail counts; six double beats; one-shot end, stop, idle/active restart, simultaneous event priority and reset",checks);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Score test timeout");end
endmodule
