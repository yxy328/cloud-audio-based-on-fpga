`timescale 1ns/1ps
// Competition-default integration: scores only guide; audio needs live touch.
// UART is accelerated, while the 50MHz clock and all I2S timings are unchanged.
module tb_top_live;
    localparam BIT_TICKS=100;
    reg clk=0; always #10 clk=~clk;
    reg rx=1,s1=0,s2=0;
    reg [7:0] pads=0;
    wire tx,bck,lrck,din,scl;
    wire r1,g1,b1,r2,g2,b2,ha,hb,hc,hd,he,hck,lat,oe;
    integer panel_columns=0,panel_latches=0,cyan_rows=0;
    reg [31:0] panel_rows=0;
    reg cyan_in_row=0;
    // Deliberately omit ENABLE_DEMO_SCORE: this checks the shipped default.
    top #(.HC05_BAUD(500000),.GUIDE_LEAD_MS(60),.FSR_ENABLE(0),.KEY_CONFIRM_CYCLES(100),
        .TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),.TOUCH_MODE_DEBOUNCE_MS(1),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .ADSR_RELEASE_SAMPLES(32),.TOUCH_ADSR_RELEASE_SAMPLES(32)) dut(
        .clk(clk),.key_s1(s1),.key_s2(s2),.ir_beam(8'hff),.touch_out(pads),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),
        .i2s_din(din),.touch_scl(scl),
        .hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(ha),.hub_B(hb),.hub_C(hc),.hub_D(hd),.hub_E(he),
        .hub_CK(hck),.hub_ST(lat),.hub_OE(oe));
    // Observe serialized panel pins, independently of the pixel function.
    always @(posedge hck) if(dut.resetn) begin
        if(panel_columns>=64) $fatal(1,"Panel shifted too many pixels before latch");
        if(panel_columns>=6 && panel_columns<11 && !r1 && g1 && b1)
            cyan_in_row=1;
        panel_columns=panel_columns+1;
    end
    always @(posedge lat) if(dut.resetn) begin
        if(panel_columns!=64 || oe!==1) $fatal(1,"Panel latch/blank/width invalid");
        panel_columns=0;panel_latches=panel_latches+1;
        panel_rows[{he,hd,hc,hb,ha}]=1;
        if(cyan_in_row && {he,hd,hc,hb,ha}<22 && dut.downloaded_playing && dut.song_guide_keys==0)
            cyan_rows=cyan_rows+1;
        cyan_in_row=0;
    end
    // Decode external pins, checking left/right equality, frame/bit periods,
    // one-bit I2S delay, padding, pin update edge, and output headroom.
    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24576)) monitor(
        .bck(bck),.lrck(lrck),.din(din));
    wire [127:0] gains={dut.touch_voices[1].u_synth.envelope_gains,
                       dut.touch_voices[0].u_synth.envelope_gains};
    wire [23:0] states={dut.touch_voices[1].u_synth.envelope_states,
                       dut.touch_voices[0].u_synth.envelope_states};
    wire [127:0] voices={dut.touch_voices[1].u_synth.voice_samples,
                        dut.touch_voices[0].u_synth.voice_samples};
    reg [511:0] replies[0:31],incoming=0;
    reg [7:0] decoded;
    integer reply_count=0,next_reply=0,rx_bit,first,k;
    reg [6:0] seen_voices;
    integer release_start_gain;
    always @(negedge clk) if(dut.resetn) begin
        if(scl!==1'b1) $fatal(1,"Touch direct-mode SCL not HIGH");
        if(dut.voice_gates!==0 || dut.song_active!==0)
            $fatal(1,"Competition default enabled autonomous audio voices");
        if(dut.u_output_mix.clipped) $fatal(1,"Live mix clipped");
    end
    initial forever begin
        @(negedge tx);repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"UART start bit");
        for(rx_bit=0;rx_bit<8;rx_bit=rx_bit+1) begin
            repeat(BIT_TICKS) @(posedge clk);decoded[rx_bit]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"UART stop bit");
        incoming={incoming[503:0],decoded};
        if(decoded==10) begin
            replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;
        end
    end
    task transact;
        input [511:0] message;
        input integer length;
        input [511:0] expected;
        integer j,b;
        begin
            for(j=length-1;j>=0;j=j-1) begin
                @(negedge clk);rx=0;repeat(BIT_TICKS) @(negedge clk);
                for(b=0;b<8;b=b+1) begin
                    rx=message[j*8+b];repeat(BIT_TICKS) @(negedge clk);
                end
                rx=1;repeat(BIT_TICKS) @(negedge clk);
            end
            wait(reply_count>next_reply);
            if(replies[next_reply]!==expected)
                $fatal(1,"Reply %0d expected '%0s', got '%0s'",next_reply,expected,replies[next_reply]);
            next_reply=next_reply+1;
        end
    endtask
    task check_silence;
        input integer start_sample;
        integer n;
        begin
            for(n=start_sample;n<monitor.pcm_count;n=n+1)
                if(monitor.pcm[n]!=0) $fatal(1,"Uncommanded external I2S audio at sample %0d",n);
        end
    endtask
    task check_sound;
        input integer start_sample;
        integer n,v,peak;
        begin
            peak=0;
            for(n=start_sample;n<monitor.pcm_count;n=n+1) begin
                v=monitor.pcm[n];if(v<0) v=-v;if(v>peak) peak=v;
            end
            if(peak<500) $fatal(1,"Live voices missing from external I2S, peak=%0d",peak);
        end
    endtask
    task check_held;
        input [6:0] held;
        integer n;
        begin
            if(dut.touch_active[6:0]!==held || dut.touch_active[7]!==0)
                $fatal(1,"Independent active voices expected %h got %h",held,dut.touch_active);
            for(n=0;n<7;n=n+1) if(held[n]) begin
                if(states[n*3 +: 3]!==3 || gains[n*16 +: 16]!==16'd39321)
                    $fatal(1,"Held voice %0d failed independent ADSR sustain",n);
            end
        end
    endtask
    task check_voice_outputs;
        input [6:0] expected;
        integer n,i;
        begin
            seen_voices=0;first=monitor.pcm_count;
            for(i=0;i<40;i=i+1) begin
                @(posedge dut.frame_ce);#1;
                for(n=0;n<7;n=n+1)
                    if($signed(voices[n*16 +: 16])!=0) seen_voices[n]=1;
            end
            if((seen_voices & expected)!==expected)
                $fatal(1,"Missing independent per-note sample streams %h / %h",seen_voices,expected);
            check_sound(first);
        end
    endtask
    initial begin
        wait(dut.touch_ready);#10000;
        s1=1;#10000;s1=0;#10000;
        s2=1;#10000;s2=0;#50000;
        if(dut.song_playing) $fatal(1,"S1/S2 started a preset score in competition default");
        transact("PLAY\n",5,{"ERR,STATE",8'd13,8'd10});
        transact("PCM_BEGIN,16,1024\n",18,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_DATA,0,8080\n",16,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_END\n",8,{"ERR,CMD",8'd13,8'd10});
        transact("PCM_PLAY\n",9,{"ERR,CMD",8'd13,8'd10});
        transact("SONG_BEGIN,2\n",13,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,0,60,5\n",17,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,1,64,100\n",19,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("PLAY\n",5,{"OK",8'd13,8'd10});
        if(!dut.downloaded_valid || !dut.downloaded_playing || dut.song_guide_keys!==0)
            $fatal(1,"Downloaded score did not start silent pre-roll");
        wait(dut.song_guide_keys==7'h01);
        if(cyan_rows==0 || panel_rows!==32'hffffffff || panel_latches<64)
            $fatal(1,"Downloaded UART score never appeared as falling pixels on HUB75E pins");
        wait(dut.song_guide_keys==7'h04);#100000;
        if(!dut.downloaded_playing) $fatal(1,"Guide did not advance to next downloaded note");
        check_silence(0);
        $display("PASS [live default]: S1/S2 and downloaded PLAY guide stay silent; old PCM commands rejected");
        pads=8'h0f;wait(dut.touch_keys[6:0]==7'h0f);#300000;
        check_held(7'h0f);check_voice_outputs(7'h0f);
        pads=8'h7f;wait(dut.touch_keys[6:0]==7'h7f);#300000;
        check_held(7'h7f);check_voice_outputs(7'h7f);
        // Release only C4 while the remaining six envelopes stay at sustain.
        pads=8'h7e;wait(dut.touch_keys[6:0]==7'h7e);
        wait(states[2:0]==4);#1;release_start_gain=gains[15:0];
        if(release_start_gain==0 || !dut.touch_active[0]) $fatal(1,"Missing C4 release tail");
        #200000;
        if(gains[15:0]>=release_start_gain || gains[15:0]==0 || states[2:0]!==4)
            $fatal(1,"C4 release envelope did not decay continuously");
        for(k=1;k<7;k=k+1)
            if(states[k*3 +: 3]!==3 || gains[k*16 +: 16]!==16'd39321)
                $fatal(1,"Releasing C4 changed held voice %0d",k);
        #600000;check_held(7'h7e);check_voice_outputs(7'h7e);
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        if(dut.downloaded_playing || dut.song_guide_keys!=0) $fatal(1,"STOP did not stop the guide");
        check_held(7'h7e);check_voice_outputs(7'h7e);
        pads=0;wait(dut.touch_keys[6:0]==0);wait(dut.touch_active==0);
        #200000;first=monitor.pcm_count;#400000;check_silence(first);
        if(monitor.pair_count<600) $fatal(1,"Insufficient external I2S coverage");
        $display("PASS [top live]: four/seven concurrent independent DDS/ADSR voices, independent release, STOP preserves held live notes, final silence; %0d stereo pairs in %0d ns",monitor.pair_count,$time);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #100000000;$fatal(1,"Live-only top timeout: replies=%0d expected=%0d keys=%h guide=%h",reply_count,next_reply,dut.touch_keys,dut.song_guide_keys);end
endmodule
