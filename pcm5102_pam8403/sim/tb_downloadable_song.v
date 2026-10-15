`timescale 1ns/1ps
module tb_downloadable_song;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, request=0, edit_allowed=1, toggle_play=0, restart=0;
    reg [2:0] operation=0;
    reg [15:0] arg0=0, arg1=0, arg2=0;
    reg [55:0] note_map={8'd72,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    wire done, valid, playing, gate;
    wire [2:0] error;
    wire [7:0] current_note;
    wire [6:0] guide_keys;
    downloadable_song #(.CLK_HZ(10000)) dut(.*);
    integer timeout, ticks, audible, i;

    task command;
        input [2:0] op;
        input [15:0] a,b,c;
        input [2:0] expected;
        begin
            @(negedge clk); request=1; operation=op; arg0=a; arg1=b; arg2=c;
            @(negedge clk); request=0;
            timeout=0;
            while(!done && timeout<1000) begin @(negedge clk); timeout=timeout+1; end
            if(!done || error!==expected)
                $fatal(1,"command %0d expected %0d got done=%b error=%0d",op,expected,done,error);
            @(negedge clk);
        end
    endtask
    task record;
        input [7:0] note;
        input integer duration;
        input [6:0] keys;
        begin
            wait(guide_keys!=0);
            ticks=0; audible=0;
            while(guide_keys!=0) begin
                @(negedge clk);
                if(guide_keys!=0) begin
                    if(current_note!==note || guide_keys!==keys)
                        $fatal(1,"wrong note/guide: %0d/%h",current_note,guide_keys);
                    ticks=ticks+1; audible=audible+gate;
                end
            end
            if(ticks!=duration*10 || audible!=((duration==1)?10:(duration-1)*10))
                $fatal(1,"note %0d expected %0d ticks, got %0d (%0d audible)",note,duration*10,ticks,audible);
        end
    endtask
    initial begin
        #1000000; $fatal(1,"song timeout");
    end
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        command(4,0,0,0,3); // no committed score
        command(1,0,0,0,2);
        command(1,129,0,0,2);
        command(2,0,60,1,3);
        command(1,3,0,0,0);
        command(2,3,60,1,2);
        command(2,0,59,1,2);
        command(2,0,73,1,2);
        command(2,0,60,0,2);
        command(2,0,60,60001,2);
        command(2,0,60,60000,0);
        command(2,0,60,3,0); // idempotent overwrite
        command(2,2,67,2,0); // out-of-order writes are allowed
        command(3,0,0,0,4);
        if(valid) $fatal(1,"incomplete score committed");
        command(2,1,60,1,0);
        edit_allowed=0;
        command(2,1,60,2,1);
        command(3,0,0,0,1);
        edit_allowed=1;
        command(3,0,0,0,0);
        if(!valid) $fatal(1,"score not committed");
        command(4,0,0,0,0);
        record(60,3,7'h01);
        record(60,1,7'h01);
        record(67,2,7'h10);
        if(playing || gate) $fatal(1,"score did not stop");

        // An interrupted staging download never replaces the valid bank.
        command(1,2,0,0,0);
        command(2,0,62,1,0);
        repeat(20) @(negedge clk);
        command(4,0,0,0,0);
        record(60,3,7'h01);
        command(5,0,0,0,0);
        if(playing || gate || guide_keys) $fatal(1,"STOP did not silence playback");
        command(3,0,0,0,4);

        // A complete replacement with an uncovered MIDI also leaves old bank.
        command(2,1,61,1,0);
        command(3,0,0,0,5);
        note_map[7:0]=61;
        command(4,0,0,0,5); // PLAY rechecks the current key mapping
        note_map[7:0]=60;
        command(4,0,0,0,0);
        record(60,3,7'h01);
        command(5,0,0,0,0);

        // Full 128-record boundary and busy response while validating.
        command(1,128,0,0,0);
        for(i=0;i<128;i=i+1) command(2,i,60,1,0);
        @(negedge clk); request=1; operation=3;
        @(negedge clk); request=0;
        command(2,0,60,2,1);
        wait(done); #1;
        if(error!=0) $fatal(1,"128 record commit failed");
        @(negedge clk);
        command(4,0,0,0,0);
        record(60,1,7'h01);
        @(negedge clk); toggle_play=1;
        @(negedge clk); toggle_play=0;
        if(playing || gate) $fatal(1,"hardware toggle failed to stop");
        @(negedge clk); restart=1;
        @(negedge clk); restart=0;
        wait(guide_keys!=0);
        command(5,0,0,0,0);
        command(7,0,0,0,2);
        $display("PASS tb_downloadable_song: atomic banks, retry, limits, map, timing, STOP");
        $finish;
    end
endmodule
