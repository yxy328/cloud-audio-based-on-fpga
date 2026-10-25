`timescale 1ns/1ps
module tb_hub75e_audio_display;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,playing=0,spawn=0,ms_tick=0,feed=0;
    reg [1:0] visual=0;
    reg [7:0] divider=0;
    integer samples=0;
    wire ce=feed && divider==255 && samples<512;
    wire signed [15:0] mixed=samples<11 ? 16'sd1024 : -16'sd1024;
    always @(posedge clk) divider<=divider+1'b1;
    always @(posedge clk) if(resetn && ce) samples<=samples+1;
    wire r1,g1,b1,r2,g2,b2,a,b,c,d,e,ck,st,oe;
    wire [4:0] panel_row={e,d,c,b,a};
    wire [5:0] rgb={r1,g1,b1,r2,g2,b2};
    hub75e_rhythm_display #(.ENABLE_AUDIO_VISUAL(1)) dut (
        .clk(clk),.resetn(resetn),.touch_keys(7'd0),.guide_keys(7'd0),
        .playing(playing),.ms_tick(ms_tick),.note_spawn(spawn),
        .spawn_keys(7'd1),.spawn_delay_ms(16'd1500),
        .visual_mode(visual),.sample_ce(ce),.mixed_sample(mixed),
        .reference_ratio(2'd0),.reference_phase(2'd0),.scope_fsr_gain(16'hffff),
        .touch0(16'sd1280),.touch1(16'sd0),.sensor_sample(16'sd2560),.guitar_sample(-16'sd3840),
        .hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(a),.hub_B(b),.hub_C(c),.hub_D(d),.hub_E(e),.hub_CK(ck),.hub_ST(st),.hub_OE(oe));
    integer columns=0,latches=0,cycles=0,last_latch=0,n,preview;
    reg [5:0] pixels[0:63];
    reg [1:0] old_mode=0;
    reg old_boundary=0;
    time last_rgb=0;
    reg capture_screen=0;
    integer screen_r[0:4095],screen_g[0:4095],screen_b[0:4095];
    integer px,ui,li;
    always @(rgb) last_rgb=$time;
    always @(posedge clk) begin
        cycles=cycles+1;
        old_boundary=dut.display_boundary;
        #1;
        if(resetn && dut.visual_active!=old_mode && !old_boundary)
            $fatal(1,"Mode switched within a PWM frame");
        old_mode=dut.visual_active;
    end
    always @(posedge ck) if(resetn) begin
        if(columns>=64 || st || $time-last_rgb<20) $fatal(1,"HUB shift/setup failure");
        pixels[columns]=rgb; columns=columns+1;
    end
    always @(posedge st) if(resetn) begin
        if(columns!=64 || !oe || ck) $fatal(1,"HUB latch/blank failure");
        if(panel_row!==latches%32) $fatal(1,"HUB row order changed");
        if(last_latch && cycles-last_latch!=133) $fatal(1,"HUB scan period changed");
        columns=0; latches=latches+1; last_latch=cycles;
        if(capture_screen)for(px=0;px<64;px=px+1)begin
            ui=panel_row*64+px;li=(panel_row+32)*64+px;
            screen_r[ui]=screen_r[ui]+pixels[px][5];screen_g[ui]=screen_g[ui]+pixels[px][4];screen_b[ui]=screen_b[ui]+pixels[px][3];
            screen_r[li]=screen_r[li]+pixels[px][2];screen_g[li]=screen_g[li]+pixels[px][1];screen_b[li]=screen_b[li]+pixels[px][0];
        end
    end
    task inspect;
        input integer x,y; input [2:0] expected;
        begin
            wait(dut.pwm_phase==0 && panel_row==y%32 && st);
            #1;
            if(y<32) begin
                if(pixels[x][5:3]!==expected) $fatal(1,"Upper pixel %0d,%0d = %b",x,y,pixels[x][5:3]);
            end else if(pixels[x][2:0]!==expected) $fatal(1,"Lower pixel %0d,%0d = %b",x,y,pixels[x][2:0]);
            @(negedge st);
        end
    endtask
    task save_scope;
        integer p;
        begin
            wait(dut.pwm_phase==31 && panel_row==31 && st);@(negedge st);
            for(p=0;p<4096;p=p+1)begin screen_r[p]=0;screen_g[p]=0;screen_b[p]=0;end
            capture_screen=1;
            wait(dut.pwm_phase==31 && panel_row==31 && st);#2;capture_screen=0;
            preview=$fopen("sim/build/scope_external_panel.ppm","w");
            if(!preview)$fatal(1,"Cannot save external scope frame");
            $fdisplay(preview,"P3\n64 64\n31");
            for(p=0;p<4096;p=p+1)$fdisplay(preview,"%0d %0d %0d",screen_r[p],screen_g[p],screen_b[p]);
            $fclose(preview);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); resetn=1;
        repeat(50000) @(negedge clk);feed=1;
        inspect(6,60,3'b111); // Existing guide at startup.
        @(negedge clk); visual=1;
        wait(dut.visual_active);
        wait(dut.audio_visual.u_visualizer.display_valid);
        save_scope;
        inspect(16,23,3'b111);inspect(16,28,3'b000);
        inspect(63,31,3'b111);inspect(63,27,3'b011); // Quiet grid node only.
        inspect(32,59,3'b111);inspect(33,59,3'b000); // Fixed PCM peak meter.
        visual=2;wait(dut.visual_active==2);
        inspect(28,14,3'b111);inspect(29,14,3'b000);
        inspect(15,40,3'b011);inspect(16,40,3'b111); // Source meters retained in XY.
        visual=3;wait(dut.visual_active==3);
        inspect(16,16,3'b000); // No spectrum before a complete FFT window.
        inspect(16,31,3'b111);
        // Score input remains active while its pixels are hidden.
        playing=1; @(negedge clk); spawn=1;
        @(negedge clk); spawn=0;
        repeat(5) @(negedge clk);
        if(dut.note_rows[2]!==1) $fatal(1,"Hidden guide lost its event");
        for(n=0;n<750;n=n+1) begin
            @(negedge clk); ms_tick=1;
            @(negedge clk); ms_tick=0;
        end
        if(dut.note_rows[28]!==1 || dut.note_rows[2]!==0)
            $fatal(1,"Hidden guide did not continue its descent");
        visual=0; wait(!dut.visual_active);
        inspect(6,28,3'b011);
        if(latches<2048) $fatal(1,"Insufficient PWM boundary coverage");
        $display("PASS HUB audio display: external wave/XY pixels, FFT startup blanking, RAM prefetch, three group bars, unchanged 133-clock scan, whole-PWM four-mode switch, hidden guide descent");
        $finish;
    end
    initial begin #80000000; $fatal(1,"HUB audio display timeout"); end
endmodule
