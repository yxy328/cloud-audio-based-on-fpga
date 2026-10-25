`timescale 1ns/1ps
module tb_downloadable_song;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, request=0, edit_allowed=1, toggle_play=0, restart=0;
    reg [2:0] operation=0;
    reg [15:0] arg0=0, arg1=0, arg2=0;
    reg [55:0] note_map={8'd72,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    reg note_ready=1;
    wire done, valid, playing, gate, ms_tick, guide_reset, note_spawn;
    wire [2:0] error;
    wire [7:0] current_note;
    wire [6:0] guide_keys, spawn_keys;
    wire [12:0] current_mask;
    wire [15:0] spawn_delay_ms;
    downloadable_song #(.CLK_HZ(20000),.ENABLE_LOOKAHEAD(1)) dut(
        .clk(clk),.resetn(resetn),.request(request),.edit_allowed(edit_allowed),
        .toggle_play(toggle_play),.restart(restart),.operation(operation),
        .arg0(arg0),.arg1(arg1),.arg2(arg2),.note_map(note_map),
        .done(done),.valid(valid),.playing(playing),.gate(gate),.error(error),
        .current_note(current_note),.guide_keys(guide_keys),.ms_tick(ms_tick),
        .guide_reset(guide_reset),.note_spawn(note_spawn),.spawn_keys(spawn_keys),
        .spawn_delay_ms(spawn_delay_ms),.note_ready(note_ready),.current_mask(current_mask)
    );
    // Default mode works for old named-port callers with note_ready unconnected.
    wire legacy_playing, legacy_gate;
    wire [6:0] legacy_keys;
    downloadable_song #(.CLK_HZ(20000)) legacy(
        .clk(clk),.resetn(resetn),.request(request),.edit_allowed(edit_allowed),
        .toggle_play(toggle_play),.restart(restart),.operation(operation),
        .arg0(arg0),.arg1(arg1),.arg2(arg2),.note_map(note_map),
        .playing(legacy_playing),.gate(legacy_gate),.guide_keys(legacy_keys)
    );

    downloadable_song_reference #(.CLK_HZ(20000),.ENABLE_LOOKAHEAD(1)) ref_dut(
        .clk(clk),.resetn(resetn),.request(request),.operation(operation),.arg0(arg0),.arg1(arg1),.arg2(arg2),.edit_allowed(edit_allowed),.note_map(note_map),.toggle_play(toggle_play),.restart(restart),.note_ready(note_ready));
    always @(negedge clk) if(resetn) begin
        if({dut.done,dut.error,dut.valid,dut.playing,dut.gate,dut.current_note,dut.guide_keys,dut.ms_tick,dut.guide_reset,dut.note_spawn,dut.spawn_keys,dut.spawn_delay_ms,dut.current_mask,dut.busy} !==
           {ref_dut.done,ref_dut.error,ref_dut.valid,ref_dut.playing,ref_dut.gate,ref_dut.current_note,ref_dut.guide_keys,ref_dut.ms_tick,ref_dut.guide_reset,ref_dut.note_spawn,ref_dut.spawn_keys,ref_dut.spawn_delay_ms,ref_dut.current_mask,ref_dut.busy})
            $fatal(1,"cycle-exact original/candidate mismatch");
    end

    integer timeout, i, epoch=0, origin=0, spawn_count=0, reset_epoch=-100;
    integer spawn_epoch[0:255];
    reg [6:0] observed_keys[0:255];
    reg [15:0] observed_delay[0:255];
    always @(posedge clk) begin
        if(ms_tick) epoch=epoch+1;
        #1;
        if(guide_reset) reset_epoch=epoch;
        if(note_spawn) begin
            if(guide_reset) $fatal(1,"spawn and reset coincide");
            if(epoch<=reset_epoch) $fatal(1,"spawn preceded renderer reset");
            if(!note_ready) $fatal(1,"spawn while consumer blocked");
            if(spawn_count>=256) $fatal(1,"unexpected extra spawns");
            spawn_epoch[spawn_count]=epoch;
            observed_keys[spawn_count]=spawn_keys;
            observed_delay[spawn_count]=spawn_delay_ms;
            spawn_count=spawn_count+1;
        end
    end
    task command;
        input [2:0] op;
        input [15:0] a,b,c;
        input [2:0] expected;
        begin
            @(negedge clk); request=1; operation=op; arg0=a; arg1=b; arg2=c;
            @(negedge clk); request=0;
            timeout=0;
            while(!done && timeout<2000) begin @(negedge clk); timeout=timeout+1; end
            if(!done || error!==expected)
                $fatal(1,"command %0d expected %0d got done=%b error=%0d",op,expected,done,error);
            @(negedge clk);
        end
    endtask
    task next_ms;
        begin
            @(negedge clk);
            while(!ms_tick) @(negedge clk);
            @(posedge clk); #2;
        end
    endtask
    task await_start;
        begin
            wait(dut.state==5); @(negedge clk); origin=epoch;
        end
    endtask
    task expect_guide;
        input [12:0] mask;
        input [6:0] keys;
        begin
            if(current_mask!==mask || guide_keys!==keys)
                $fatal(1,"time %0d expected mask/keys %h/%h got %h/%h",
                    epoch-origin,mask,keys,current_mask,guide_keys);
        end
    endtask
    task basic_score;
        begin
            command(1,5,0,0,0);
            command(2,0,60,60000,0);
            command(2,0,60,3,0); // overwrite and duplicate-safe retry
            command(6,2,145,2,0); // C/E/G chord, deliberately out of order
            command(6,3,0,2,0); // rest
            command(2,4,69,1,0);
            command(3,0,0,0,4);
            command(2,1,60,1,0);
            command(3,0,0,0,0);
        end
    endtask
    initial begin
        #20000000; $fatal(1,"song timeout");
    end
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        command(4,0,0,0,3);
        command(1,0,0,0,2);
        command(1,129,0,0,2);
        command(2,0,60,1,3);
        command(1,1,0,0,0);
        command(2,1,60,1,2);
        command(2,0,59,1,2);
        command(2,0,73,1,2);
        command(2,0,60,0,2);
        command(2,0,60,60001,2);
        command(6,0,8192,1,2);
        basic_score;
        if(!valid) $fatal(1,"score not committed");
        spawn_count=0;
        command(4,0,0,0,0);
        await_start;
        expect_guide(0,0);
        if(legacy_keys!==1 || !legacy_gate)
            $fatal(1,"legacy mode did not start immediately");
        for(i=1;i<=1499;i=i+1) begin next_ms; expect_guide(0,0); end
        next_ms; expect_guide(1,1);
        next_ms; expect_guide(1,1);
        next_ms; expect_guide(1,1);
        if(gate) $fatal(1,"repeated-note release missing");
        next_ms; expect_guide(1,1); // next repeated record starts at 1503
        if(!gate) $fatal(1,"1ms repeated note was silenced");
        next_ms; expect_guide(145,7'h15);
        if(current_note!==60) $fatal(1,"chord legacy pitch not lowest MIDI");
        next_ms; expect_guide(145,7'h15);
        next_ms; expect_guide(0,0);
        if(gate) $fatal(1,"rest audible");
        next_ms; expect_guide(0,0);
        next_ms; expect_guide(512,7'h20);
        next_ms; expect_guide(0,0);
        repeat(3) @(negedge clk);
        if(playing || gate) $fatal(1,"score did not end at 1509ms");
        if(spawn_count!=4) $fatal(1,"expected 4 visual events, got %0d",spawn_count);
        for(i=0;i<4;i=i+1)
            if(observed_delay[i]!=1500) $fatal(1,"wrong lookahead delay");
        if(observed_keys[0]!=1 || observed_keys[1]!=1 ||
            observed_keys[2]!=7'h15 || observed_keys[3]!=7'h20 ||
            spawn_epoch[0]-origin!=0 || spawn_epoch[1]-origin!=3 ||
            spawn_epoch[2]-origin!=4 || spawn_epoch[3]-origin!=8)
            $fatal(1,"chord/rest/repeated event schedule mismatch");

        // Failed downloads and changed mappings never replace the active bank.
        command(1,2,0,0,0);
        command(2,0,62,1,0);
        command(3,0,0,0,4);
        command(2,1,61,1,0);
        command(3,0,0,0,5);
        note_map[7:0]=61;
        command(4,0,0,0,5);
        if(playing) $fatal(1,"invalid PLAY mapping accepted");
        note_map[7:0]=60;
        command(4,0,0,0,0);
        await_start;
        wait(note_spawn); #1;
        if(spawn_keys!=1) $fatal(1,"failed replacement changed active bank");
        command(5,0,0,0,0);
        if(playing || gate || guide_keys) $fatal(1,"STOP did not clear guidance");

        // A blocked renderer retains its event and gets a corrected deadline.
        spawn_count=0; note_ready=0;
        command(4,0,0,0,0); await_start;
        for(i=0;i<10;i=i+1) next_ms;
        if(spawn_count!=0) $fatal(1,"backpressure dropped handshake");
        @(negedge clk); note_ready=1;
        wait(note_spawn); #2;
        if(spawn_delay_ms!=1490 || spawn_keys!=1)
            $fatal(1,"blocked event did not retain its deadline");
        command(5,0,0,0,0);

        spawn_count=0;
        @(negedge clk); restart=1;
        @(negedge clk); restart=0;
        await_start;
        wait(note_spawn); #2;
        if(spawn_delay_ms!=1500 || spawn_keys!=1) $fatal(1,"restart not rewound");
        @(negedge clk); toggle_play=1;
        @(negedge clk); toggle_play=0;
        if(playing) $fatal(1,"hardware toggle did not stop");

        edit_allowed=0;
        command(1,1,0,0,1);
        command(2,0,60,1,1);
        command(3,0,0,0,1);
        edit_allowed=1;
        command(1,1,0,0,0);
        command(6,0,8191,1,0);
        command(3,0,0,0,5); // every chord pitch must be covered

        // Full-capacity 1ms score: no timing gaps or lost repeated events.
        command(1,128,0,0,0);
        for(i=0;i<128;i=i+1) command(2,i,60,1,0);
        @(negedge clk); request=1; operation=3;
        @(negedge clk); request=0;
        command(2,0,60,2,1);
        wait(done); #2;
        if(error!=0) $fatal(1,"128 record commit failed");
        spawn_count=0;
        command(4,0,0,0,0); await_start;
        for(i=1;i<=1628;i=i+1) begin
            next_ms;
            if(i>=1500 && i<1628) begin
                expect_guide(1,1);
                if(!gate) $fatal(1,"dense 1ms note gap at %0d",i);
            end else expect_guide(0,0);
        end
        repeat(3) @(negedge clk);
        if(playing || spawn_count!=128) $fatal(1,"dense score lost notes");
        for(i=0;i<128;i=i+1)
            if(spawn_epoch[i]-origin!=i || observed_delay[i]!=1500 || observed_keys[i]!=1)
                $fatal(1,"dense note %0d scheduled incorrectly",i);
        command(7,0,0,0,2);
        $display("PASS tb_downloadable_song: atomic banks, chords/rests, shared RAM, timing, lookahead, backpressure, STOP/restart, 128 dense notes");
        $finish;
    end
endmodule
