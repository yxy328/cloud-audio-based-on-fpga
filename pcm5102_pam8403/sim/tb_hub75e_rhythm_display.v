`timescale 1ns/1ps
module tb_hub75e_rhythm_display;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, playing=0, ms_tick=0, note_spawn=0;
    reg [6:0] touch_keys=0, guide_keys=0, spawn_keys=0;
    reg [15:0] spawn_delay_ms=0;
    wire ready, overflow, r1,g1,b1,r2,g2,b2,a,b,c,d,e,ck,st,oe;
    wire [4:0] panel_row={e,d,c,b,a};
    wire [5:0] rgb={r1,g1,b1,r2,g2,b2};
    hub75e_rhythm_display dut (
        .clk(clk),.resetn(resetn),.touch_keys(touch_keys),.guide_keys(guide_keys),
        .playing(playing),.ms_tick(ms_tick),.note_spawn(note_spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),
        .visual_mode(2'd0),.sample_ce(1'b0),.mixed_sample(16'sd0),
        .touch0(16'sd0),.touch1(16'sd0),.sensor_sample(16'sd0),.guitar_sample(16'sd0),
        .note_ready(ready),.overflow(overflow),
        .hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(a),.hub_B(b),.hub_C(c),.hub_D(d),.hub_E(e),
        .hub_CK(ck),.hub_ST(st),.hub_OE(oe)
    );
    integer shifts=0, latches=0, cycles=0, previous_latch=-1;
    integer red_count=0, green_count=0, blue_count=0;
    integer touch_r=0, touch_g=0, touch_b=0;
    integer pwm_rows=0;
    integer committed_spawns=0;
    reg count_pwm=0;
    reg [5:0] pixels[0:63];
    time last_rgb_change=0, last_ck_change=0, last_st_change=0;
    time blank_started=0;
    reg [4:0] active_row=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(resetn && playing && dut.valid_s2)
            committed_spawns=committed_spawns+1;
    end
    always @(rgb) last_rgb_change=$time;
    always @(ck) begin
        if (resetn && $time-last_ck_change < 20)
            $fatal(1,"HUB clock pulse shorter than one master cycle");
        last_ck_change=$time;
    end
    always @(st) begin
        if (resetn && $time-last_st_change < 20)
            $fatal(1,"LAT pulse shorter than one master cycle");
        last_st_change=$time;
    end
    always @(posedge oe) blank_started=$time;
    always @(panel_row) begin
        if (resetn && (oe !== 1 || $time-blank_started < 20))
            $fatal(1,"row address changed before a complete blank cycle");
    end
    always @(posedge ck) begin
        if (resetn) begin
            if (st !== 0 || panel_row !== active_row)
                $fatal(1,"CK overlaps LAT or changes the displayed row");
            if ($time-last_rgb_change < 20)
                $fatal(1,"RGB did not have one master cycle setup");
            if (shifts >= 64) $fatal(1,"too many shift clocks");
            pixels[shifts]=rgb;
            shifts=shifts+1;
        end
    end
    always @(posedge st) begin
        if (resetn) begin
            if (shifts != 64 || oe !== 1 || ck !== 0)
                $fatal(1,"LAT without 64 pixels or without blanking");
            if (panel_row !== (latches%32))
                $fatal(1,"row scan order %0d expected %0d",panel_row,latches%32);
            if (previous_latch >= 0 && cycles-previous_latch != 133)
                $fatal(1,"row period %0d expected 133 master cycles",cycles-previous_latch);
            if (count_pwm && panel_row == 2) begin
                red_count=red_count+pixels[6][5];
                green_count=green_count+pixels[6][4];
                blue_count=blue_count+pixels[6][3];
                pwm_rows=pwm_rows+1;
            end
            if (count_pwm && panel_row == 28) begin
                touch_r=touch_r+pixels[6][2];
                touch_g=touch_g+pixels[6][1];
                touch_b=touch_b+pixels[6][0];
            end
            active_row=panel_row;
            previous_latch=cycles;
            latches=latches+1;
            shifts=0;
        end
    end

    task submit;
        input [6:0] keys;
        input [15:0] delay_ms;
        begin
            @(negedge clk); spawn_keys=keys; spawn_delay_ms=delay_ms; note_spawn=1;
            @(negedge clk); note_spawn=0;
            repeat(3) @(negedge clk); // Distance / quotient pipeline commit.
            #1;
        end
    endtask
    task elapse;
        input integer milliseconds;
        integer k;
        begin
            for(k=0;k<milliseconds;k=k+1) begin
                @(negedge clk); ms_tick=1;
                @(negedge clk); ms_tick=0;
            end
            #1;
        end
    endtask
    task inspect_pixel;
        input integer x,y;
        input [2:0] expected;
        integer row_pair;
        begin
            row_pair=y%32;
            // Threshold zero makes every nonzero native color visible.
            wait(dut.pwm_phase == 0 && panel_row == row_pair && st == 1);
            #1;
            if (y < 32) begin
                if(pixels[x][5:3] !== expected)
                    $fatal(1,"upper pixel (%0d,%0d)=%b expected %b",x,y,pixels[x][5:3],expected);
            end else if(pixels[x][2:0] !== expected)
                $fatal(1,"lower pixel (%0d,%0d)=%b expected %b",x,y,pixels[x][2:0],expected);
            @(negedge st);
        end
    endtask
    integer k, stage, commits_before, phase_case, expected_y, phase_value;
    initial begin
        repeat(4) @(negedge clk);
        resetn=1; playing=1; guide_keys=1; touch_keys=1;
        submit(7'b0000001,1500);
        if(!ready || overflow) $fatal(1,"bitmap did not accept a note");
        // Row 2 starts as cyan, lower row 60 shows a correct held key.
        inspect_pixel(6,2,3'b011);
        inspect_pixel(6,60,3'b111);
        // Count one complete 32-phase PWM cycle through the actual pins.
        wait(dut.pwm_phase == 31 && panel_row == 31 && st == 1);
        @(negedge st); count_pwm=1;
        wait(pwm_rows == 32);
        wait(panel_row == 31 && st == 1);
        #1; count_pwm=0;
        if(red_count!=0 || green_count!=24 || blue_count!=31)
            $fatal(1,"native RGB5 PWM count %0d/%0d/%0d",red_count,green_count,blue_count);
        if(touch_r!=31 || touch_g!=31 || touch_b!=31)
            $fatal(1,"white key PWM count %0d/%0d/%0d",touch_r,touch_g,touch_b);
        elapse(750);
        inspect_pixel(6,28,3'b011);
        inspect_pixel(6,2,3'b111); // Background only after head moves away.
        elapse(750);
        inspect_pixel(6,54,3'b011);
        // All 128 events can coexist in the representable raster without
        // stalling, and simultaneous lanes survive a same-row merge.
        commits_before=committed_spawns;
        for(k=0;k<128;k=k+1) begin
            @(negedge clk); note_spawn=1;
            spawn_keys=7'b0000001 << (k%7); spawn_delay_ms=1500;
            if(!ready || overflow) $fatal(1,"dense score stalled/overflowed at %0d",k);
        end
        @(negedge clk); note_spawn=0;
        repeat(3) @(negedge clk); #1;
        if(committed_spawns-commits_before != 128)
            $fatal(1,"pipeline accepted 128 notes but committed %0d",committed_spawns-commits_before);
        if(dut.note_rows[2] !== 7'h7f)
            $fatal(1,"dense raster lost one or more key lanes");
        // Spawn and scroll on the same master edge must preserve both
        // the shifted old content and the newly merged note.
        playing=0;
        repeat(2) @(negedge clk);
        playing=1;
        submit(7'b0000001,1500);
        elapse(28);
        @(negedge clk); ms_tick=1; note_spawn=1;
        spawn_keys=7'b0000010; spawn_delay_ms=1471;
        @(negedge clk); ms_tick=0; note_spawn=0;
        repeat(3) @(negedge clk);
        #1;
        if(dut.note_rows[3] !== 7'b0000011)
            $fatal(1,"scroll/spawn collision lost an event");
        // Independently hit each pipeline boundary with the fractional
        // scroll edge. The 1500ms head must commit at row 3, never row 2.
        for(stage=0;stage<3;stage=stage+1) begin
            @(negedge clk); playing=0;
            @(negedge clk); playing=1;
            elapse(28);
            @(negedge clk); note_spawn=1; spawn_keys=7'b0000100; spawn_delay_ms=1500;
            @(negedge clk); note_spawn=0;
            repeat(stage) @(negedge clk);
            ms_tick=1;
            @(negedge clk); ms_tick=0;
            repeat(4) @(negedge clk); #1;
            if(dut.note_rows[3] !== 7'b0000100 || dut.note_rows[2] !== 0)
                $fatal(1,"pipeline stage %0d did not compensate a scroll",stage);
        end
        // STOP at each pending stage invalidates every in-flight spawn.
        for(stage=0;stage<3;stage=stage+1) begin
            @(negedge clk); playing=0;
            @(negedge clk); playing=1;
            @(negedge clk); note_spawn=1; spawn_keys=1; spawn_delay_ms=1500;
            @(negedge clk); note_spawn=0;
            repeat(stage) @(negedge clk);
            playing=0;
            @(negedge clk); playing=1;
            repeat(5) @(negedge clk); #1;
            for(k=0;k<64;k=k+1)
                if(dut.note_rows[k] !== 0)
                    $fatal(1,"STOP leaked pending pipeline stage %0d",stage);
        end
        // Exhaustive delay arithmetic at two fractional scroll phases.
        // No valid event is submitted, so this exercises the quotient
        // datapath independently of OR-merging an already occupied pixel.
        for(phase_case=0;phase_case<2;phase_case=phase_case+1) begin
            @(negedge clk); playing=0;
            @(negedge clk); playing=1;
            if(phase_case==1) elapse(28);
            phase_value=dut.motion_phase;
            for(k=0;k<=1500;k=k+1) begin
                @(negedge clk); spawn_delay_ms=k;
                repeat(3) @(negedge clk); #1;
                expected_y=54-(phase_value+k*52)/1500;
                if(dut.insert_y_s2 !== expected_y[6:0])
                    $fatal(1,"delay %0d phase %0d yielded row %0d expected %0d",k,phase_value,dut.insert_y_s2,expected_y);
            end
        end
        guide_keys=0; touch_keys=1;
        inspect_pixel(6,60,3'b011);
        touch_keys=0;
        // A stopped score clears its raster without disturbing scanning.
        playing=0;
        repeat(2) @(negedge clk);
        for(k=0;k<64;k=k+1)
            if(dut.note_rows[k] !== 0) $fatal(1,"stop left stale notes");
        if(ready || overflow) $fatal(1,"stop handshake/reset mismatch");
        inspect_pixel(6,60,3'b111);
        if(latches < 1024) $fatal(1,"insufficient scan coverage");
        $display("PASS hub75e_rhythm_display: external scan/RGB5 PWM, 1500ms descent, 128 commits at one/clock, every pipeline scroll/STOP boundary, 3002 delay/phase arithmetic cases, touch");
        $finish;
    end
    initial begin #30000000; $fatal(1,"HUB rhythm display timeout"); end
endmodule
