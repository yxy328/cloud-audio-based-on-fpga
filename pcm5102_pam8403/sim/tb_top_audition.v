`timescale 1ns/1ps
// Explicit UART audition through the production DDS/ADSR and external I2S.
// UART is accelerated, while the 50MHz clock and all I2S timings are unchanged.
module tb_top_audition;
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
    wire [127:0] gains=dut.u_touch_synth.gains[127:0];
    wire [23:0] states=dut.u_touch_synth.states[23:0];
    wire [127:0] voices=dut.u_touch_synth.voice_samples[127:0];
    reg [511:0] replies[0:63],incoming=0;
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
    integer chord_start,repeated_offs=0;
    reg previous_audition_gate=0;
    always @(posedge dut.frame_ce) begin
        if(dut.downloaded_audition && previous_audition_gate && !dut.downloaded_gate)
            repeated_offs=repeated_offs+1;
        previous_audition_gate=dut.downloaded_audition && dut.downloaded_gate;
    end
    task natural_mapping;begin
        transact("MAP,2,62\n",9,{"OK,MAP,2,62",8'd13,8'd10});
        transact("MAP,3,64\n",9,{"OK,MAP,3,64",8'd13,8'd10});
        transact("MAP,4,65\n",9,{"OK,MAP,4,65",8'd13,8'd10});
        transact("MAP,5,67\n",9,{"OK,MAP,5,67",8'd13,8'd10});
        transact("MAP,6,69\n",9,{"OK,MAP,6,69",8'd13,8'd10});
        transact("MAP,7,71\n",9,{"OK,MAP,7,71",8'd13,8'd10});
    end endtask
    initial begin
        wait(dut.touch_ready);#10000;
        transact("AUDITION\n",9,{"ERR,STATE",8'd13,8'd10});
        if(dut.downloaded_audition) $fatal(1,"Empty audition armed audio");
        // Same chord twice, explicit rest, a melody note, then all seven keys.
        natural_mapping;
        transact("SONG_BEGIN,5\n",13,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,0,145,5\n",19,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,1,145,5\n",19,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,2,0,3\n",17,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,3,69,5\n",17,{"OK",8'd13,8'd10});
        transact("SONG_CHORD,4,2741,5\n",20,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("AUDITION\n",9,{"OK",8'd13,8'd10});
        if(!dut.downloaded_audition || pads!=0) $fatal(1,"Audition was not explicitly armed");
        first=monitor.pcm_count;
        #20000000;
        check_silence(first); // 60ms pre-roll must not leak music.
        wait(dut.song_guide_keys==7'h15 && dut.downloaded_gate);
        repeat(16) @(posedge dut.frame_ce);
        check_held(7'h15);check_voice_outputs(7'h15);
        chord_start=monitor.pcm_count;
        wait(dut.song_guide_keys==0);
        #1500000;
        first=monitor.pcm_count;#500000;check_silence(first);
        wait(dut.song_guide_keys==7'h20);
        repeat(16) @(posedge dut.frame_ce);
        check_held(7'h20);check_voice_outputs(7'h20);
        wait(dut.song_guide_keys==7'h7f);
        repeat(16) @(posedge dut.frame_ce);
        check_held(7'h7f);check_voice_outputs(7'h7f);
        wait(!dut.downloaded_playing);#2000000;
        if(dut.downloaded_audition || dut.touch_active!=0 || repeated_offs<3)
            $fatal(1,"Audition did not end/disarm or repeated notes lacked note-off");
        first=monitor.pcm_count;#500000;check_silence(first);
        // STOP removes score gates but a physically held live note survives.
        transact("AUDITION\n",9,{"OK",8'd13,8'd10});
        wait(dut.audition_keys==7'h15);
        pads=8'h02;wait(dut.touch_keys[6:0]==7'h02);
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        #2000000;check_held(7'h02);check_voice_outputs(7'h02);
        pads=0;wait(dut.touch_active==0);
        // Mapping validation still protects audition.
        transact("MAP,1,62\n",9,{"OK,MAP,1,62",8'd13,8'd10});
        transact("AUDITION\n",9,{"ERR,MAP",8'd13,8'd10});
        if(dut.downloaded_audition) $fatal(1,"Invalid mapping armed audition");
        transact("MAP_RESET\n",10,{"OK,MAP_RESET",8'd13,8'd10});
        $display("PASS [top audition]: UART opt-in, silent pre-roll, three/seven independent voices at external I2S, repeated note articulation/rest/end, STOP preserves held live notes, mapping rejection");
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #500000000;$fatal(1,"Audition timeout replies=%0d keys=%h guide=%h",reply_count,dut.touch_keys,dut.song_guide_keys);end
endmodule
