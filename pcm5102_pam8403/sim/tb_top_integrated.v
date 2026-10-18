`timescale 1ns/1ps
// Combined production-top regression. UART and note lifetimes are accelerated;
// the 50 MHz clock, ADC conversion, HUB75 scan and I2S retain real timing.
// Sensor event injection begins after APDS classification; I2C hardware and
// optical recognition still require the physical APDS-9960 for board testing.
module tb_top_integrated;
    localparam BIT_TICKS=100;
    reg clk=0; always #10 clk=~clk;
    reg rx=1, s1=0, s2=0;
    reg [7:0] pads=0;
    wire tx,bck,lrck,din,touch_scl;
    tri1 sensor_scl,sensor_sda;
    wire r1,g1,b1,r2,g2,b2,ha,hb,hc,hd,he,hck,lat,oe;
    top #(.HC05_BAUD(500000),.GUIDE_LEAD_MS(60),.KEY_CONFIRM_CYCLES(100),
        .TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),.TOUCH_MODE_DEBOUNCE_MS(1),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .ADSR_RELEASE_SAMPLES(32),.TOUCH_ADSR_RELEASE_SAMPLES(32),
        .FSR_SAMPLE_HZ(2000),.FSR_SLEW_STEP(65535),.FSR_PITCH_SLEW_STEP(65535),
        .GUITAR_STRING_LENGTH(8)) dut (
        .clk(clk),.key_s1(s1),.key_s2(s2),.ir_beam(8'hff),.touch_out(pads),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),
        .i2s_din(din),.touch_scl(touch_scl),.scl(sensor_scl),.sda(sensor_sda),
        .hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(ha),.hub_B(hb),.hub_C(hc),.hub_D(hd),.hub_E(he),
        .hub_CK(hck),.hub_ST(lat),.hub_OE(oe));
    // Shorten only note duration/string decay; keep the imported voice engines,
    // gain pipelines and their 256-frame attack/release operating unchanged.
    defparam dut.u_gesture.AUDIO_NOTE_FRAMES=400;
    defparam dut.u_gesture.AUDIO_PIANO_FRAMES=400;
    defparam dut.u_gesture.AUDIO_FLUTE_FRAMES=400;
    defparam dut.u_gesture.AUDIO_UKULELE_FRAMES=400;
    defparam dut.u_gesture.AUDIO_DRUM_FRAMES=400;
    defparam dut.u_string.LOSS_SHIFT=2;

    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24576)) monitor (
        .bck(bck),.lrck(lrck),.din(din));
    integer panel_columns=0,panel_latches=0,cyan_rows=0;
    reg [31:0] panel_rows=0;
    reg cyan_in_row=0;
    always @(posedge hck) if(dut.resetn) begin
        if(panel_columns>=64) $fatal(1,"Panel shifted more than 64 columns");
        if(panel_columns>=6 && panel_columns<11 && !r1 && g1 && b1) cyan_in_row=1;
        panel_columns=panel_columns+1;
    end
    always @(posedge lat) if(dut.resetn) begin
        if(panel_columns!=64 || oe!==1) $fatal(1,"Panel width/latch/blank invalid");
        panel_columns=0; panel_latches=panel_latches+1;
        panel_rows[{he,hd,hc,hb,ha}]=1;
        if(cyan_in_row && {he,hd,hc,hb,ha}<22 &&
           dut.downloaded_playing && dut.song_guide_keys==0) cyan_rows=cyan_rows+1;
        cyan_in_row=0;
    end
    wire [127:0] gains=dut.u_touch_synth.gains[127:0];
    wire [23:0] states=dut.u_touch_synth.states[23:0];
    always @(negedge clk) if(dut.resetn) begin
        if(touch_scl!==1) $fatal(1,"Direct-mode TTP229 SCL not HIGH");
        if(dut.voice_gates!==0 || dut.song_active!==0)
            $fatal(1,"Guide enabled autonomous score audio");
        if(dut.u_output_mix.clipped || dut.u_touch_synth.clipped ||
           dut.u_extra_mix.clipped) $fatal(1,"Integrated voices clipped");
        if(dut.touch_note_gates[7]!==0) $fatal(1,"Mode key became an audio key");
    end

    reg [511:0] replies[0:127],incoming=0;
    reg [7:0] decoded;
    integer reply_count=0,next_reply=0,rx_bit;
    initial forever begin
        @(negedge tx); repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"UART start bit invalid");
        for(rx_bit=0;rx_bit<8;rx_bit=rx_bit+1) begin
            repeat(BIT_TICKS) @(posedge clk); decoded[rx_bit]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"UART stop bit invalid");
        incoming={incoming[503:0],decoded};
        if(decoded==10) begin
            if(reply_count>=128) $fatal(1,"Reply capture overflow");
            replies[reply_count]=incoming; reply_count=reply_count+1; incoming=0;
        end
    end
    task transact;
        input [511:0] message;
        input integer length;
        input [511:0] expected;
        integer j,b;
        begin
            for(j=length-1;j>=0;j=j-1) begin
                @(negedge clk); rx=0; repeat(BIT_TICKS) @(negedge clk);
                for(b=0;b<8;b=b+1) begin
                    rx=message[j*8+b]; repeat(BIT_TICKS) @(negedge clk);
                end
                rx=1; repeat(BIT_TICKS) @(negedge clk);
            end
            wait(reply_count>next_reply);
            if(replies[next_reply]!==expected)
                $fatal(1,"Reply %0d expected '%0s', got '%0s'",next_reply,expected,replies[next_reply]);
            next_reply=next_reply+1;
        end
    endtask
    task frames;
        input integer count;
        integer n;
        begin
            for(n=0;n<count;n=n+1) begin @(posedge dut.frame_ce); @(negedge clk); end
        end
    endtask
    task check_silence;
        input integer first_sample;
        integer n;
        begin
            for(n=first_sample;n<monitor.pcm_count;n=n+1)
                if(monitor.pcm[n]!=0) $fatal(1,"Unexpected I2S audio at sample %0d: %0d",n,monitor.pcm[n]);
        end
    endtask
    task peak_since;
        input integer first_sample;
        output integer peak;
        integer n,v;
        begin
            peak=0;
            for(n=first_sample;n<monitor.pcm_count;n=n+1) begin
                v=monitor.pcm[n]; if(v<0) v=-v; if(v>peak) peak=v;
            end
        end
    endtask
    task check_sound;
        input integer first_sample;
        input integer minimum_peak;
        integer peak;
        begin
            peak_since(first_sample,peak);
            if(peak<minimum_peak) $fatal(1,"Missing external I2S sound: peak %0d < %0d",peak,minimum_peak);
        end
    endtask
    task held;
        input [6:0] keys;
        integer n;
        begin
            if(dut.touch_active!=={1'b0,keys}) $fatal(1,"Held touch voices changed: %h",dut.touch_active);
            for(n=0;n<7;n=n+1) if(keys[n]) begin
                if(states[n*3 +: 3]!==3 || gains[n*16 +: 16]!==39321)
                    $fatal(1,"Held voice %0d lost independent ADSR sustain",n);
            end
        end
    endtask
    task pressure;
        input [9:0] value;
        begin
            dut.u_fsr_adc.adc_inst.sim_value={3'd0,value,1'b0};
            wait(dut.fsr_adc_sample==value); frames(12);
            if(dut.fsr_pitch_mode) begin
                if(dut.fsr_gain!==65535 || dut.fsr_pitch_ratio!==dut.fsr_target_pitch_ratio)
                    $fatal(1,"Pitch expression did not settle");
            end else if(dut.fsr_gain!==dut.fsr_target_gain || dut.fsr_pitch_ratio!==65535)
                $fatal(1,"Volume expression did not settle");
        end
    endtask
    task gesture;
        input [2:0] from_dir,to_dir;
        input [31:0] expected_increment;
        input [2:0] expected_timbre;
        begin
            @(negedge clk);
            force dut.u_gesture.start_dir=from_dir;
            force dut.u_gesture.end_dir=to_dir;
            force dut.u_gesture.gesture_valid=1'b1;
            @(negedge clk); force dut.u_gesture.gesture_valid=1'b0;
            frames(40);
            if(((dut.u_gesture.u_audio.u_synth.peek_context(0)>>274)&32'hffffffff)!==expected_increment ||
               ((dut.u_gesture.u_audio.u_synth.peek_context(0)>>271)&7)!==expected_timbre)
                $fatal(1,"Gesture lost bank/timbre in independent TDM context");
        end
    endtask
    task gesture_silence;
        integer first_sample;
        begin
            wait(dut.sensor_voice_count==0);
            frames(12); first_sample=monitor.pcm_count;
            frames(32); check_silence(first_sample);
        end
    endtask
    task press_s1;
        begin s1=1; #10000; s1=0; #10000; end
    endtask
    task press_s2;
        begin s2=1; #10000; s2=0; #10000; end
    endtask

    integer first,light_peak,heavy_peak,i,old_latches;
    reg [55:0] tone_command;
    initial begin
        // Inject only the classified sensor event, preserving production audio.
        force dut.u_gesture.init_done=1'b1;
        force dut.u_gesture.gesture_valid=1'b0;
        force dut.u_gesture.dir_evaluated=1'b1;
        force dut.u_gesture.start_dir=3'd1;
        force dut.u_gesture.end_dir=3'd2;
        wait(dut.touch_ready); #10000;
        press_s1; press_s2;
        if(dut.song_playing || dut.u_string.pending || dut.u_string.fill_remaining ||
           dut.gesture_bank || dut.gesture_vibrato || dut.gesture_timbre!==0)
            $fatal(1,"Physical score buttons changed sensor/guitar controls");
        transact("PLAY\n",5,{"ERR,STATE",8'd13,8'd10});
        transact("SONG_BEGIN,2\n",13,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,0,60,20\n",18,{"OK",8'd13,8'd10});
        transact("SONG_NOTE,1,64,40\n",18,{"OK",8'd13,8'd10});
        transact("SONG_END\n",9,{"OK",8'd13,8'd10});
        transact("PLAY\n",5,{"OK",8'd13,8'd10});
        if(!dut.downloaded_valid || !dut.downloaded_playing || dut.song_guide_keys!==0)
            $fatal(1,"Downloaded score lost silent pre-roll");
        wait(dut.song_guide_keys==7'h01);
        if(cyan_rows==0 || panel_rows!==32'hffffffff || panel_latches<64)
            $fatal(1,"Downloaded score missing from external 64x64 panel scan");
        check_silence(0);
        press_s1;
        if(dut.downloaded_playing) $fatal(1,"S1 no longer stops downloaded score");
        press_s1;
        wait(dut.downloaded_playing);
        press_s2;
        wait(dut.downloaded_playing);
        if(dut.song_guide_keys!==0 || dut.u_string.pending || dut.u_string.fill_remaining)
            $fatal(1,"S2 restart lost pre-roll or triggered guitar");

        pads=8'h7f; wait(dut.touch_keys==8'h7f); frames(20); held(7'h7f);
        first=monitor.pcm_count; frames(60); check_sound(first,500);
        // New controls stay available while live notes and the score are busy.
        transact("TONE,4\n",7,{"OK",8'd13,8'd10});
        transact("BANK,1\n",7,{"OK",8'd13,8'd10});
        transact("VIBRATO,1\n",10,{"OK",8'd13,8'd10});
        if(dut.gesture_timbre!==4 || !dut.gesture_bank || !dut.gesture_vibrato)
            $fatal(1,"UART sensor controls failed while seven keys were held");
        transact("TONE,8\n",7,{"ERR,RANGE",8'd13,8'd10});
        transact("TONE,9\n",7,{"ERR,RANGE",8'd13,8'd10});
        transact("BANK,2\n",7,{"ERR,RANGE",8'd13,8'd10});
        transact("VIBRATO,2\n",10,{"ERR,RANGE",8'd13,8'd10});
        transact("TONE,X\n",7,{"ERR,CMD",8'd13,8'd10});
        transact("TONE,04\n",8,{"ERR,CMD",8'd13,8'd10});
        transact("BANK,-1\n",8,{"ERR,CMD",8'd13,8'd10});
        transact("BANK,\n",6,{"ERR,CMD",8'd13,8'd10});
        transact("VIBRATO,X\n",10,{"ERR,CMD",8'd13,8'd10});
        transact("VIBRATO,1,\n",11,{"ERR,CMD",8'd13,8'd10});
        transact("GUITAR,\n",8,{"ERR,CMD",8'd13,8'd10});
        if(dut.gesture_timbre!==4 || !dut.gesture_bank || !dut.gesture_vibrato ||
           dut.u_string.pending || dut.u_string.fill_remaining)
            $fatal(1,"Invalid command changed sensor state or plucked guitar");
        transact("STOP\n",5,{"OK",8'd13,8'd10});
        if(dut.downloaded_playing || dut.song_guide_keys!=0) $fatal(1,"STOP lost score semantics");
        held(7'h7f); first=monitor.pcm_count; frames(60); check_sound(first,500);
        pads=0; wait(dut.touch_keys==0 && dut.touch_active==0); frames(12);
        first=monitor.pcm_count; frames(32); check_silence(first);
        $display("PASS [integrated controls]: UART range/format guards, downloaded silent guide, external 64x64 scan, S1/S2 score controls, seven keys survive STOP and new controls");

        // Real ADC handshake remains connected to both live expression modes.
        pads=1; wait(dut.touch_keys==1); frames(20); pressure(0);
        first=monitor.pcm_count; frames(300); peak_since(first,light_peak);
        pressure(1023);
        first=monitor.pcm_count; frames(300); peak_since(first,heavy_peak);
        if(light_peak<1100 || heavy_peak<270 || heavy_peak*100/light_peak<23 ||
           heavy_peak*100/light_peak>27) $fatal(1,"Integrated FSR volume endpoints: %0d/%0d",light_peak,heavy_peak);
        pads=8'h81; wait(dut.touch_keys==8'h81); wait(dut.fsr_pitch_mode); frames(12);
        if(dut.fsr_gain!==65535 || dut.fsr_pitch_ratio!==32768 ||
           dut.touch_phase_increments[31:0]!==32'd11506414)
            $fatal(1,"Integrated key 8/pressure octave failed");
        pads=1; wait(dut.touch_keys==1); pads=8'h81;
        wait(dut.touch_keys==8'h81); wait(!dut.fsr_pitch_mode); pressure(0);
        pads=0; wait(dut.touch_keys==0 && dut.touch_active==0); frames(12);
        $display("PASS [integrated FSR]: ADC volume %0d/%0d, control key 8 and pressure octave preserved",light_peak,heavy_peak);

        transact("VIBRATO,0\n",10,{"OK",8'd13,8'd10});
        transact("BANK,0\n",7,{"OK",8'd13,8'd10});
        for(i=0;i<5;i=i+1) begin
            tone_command="TONE,0\n"; tone_command[15:8]=48+i;
            transact(tone_command,7,{"OK",8'd13,8'd10});
            if(dut.gesture_timbre!==i) $fatal(1,"TONE %0d did not reach gesture voice",i);
            if(i==2) transact("BANK,1\n",7,{"OK",8'd13,8'd10});
            if(i==4) transact("BANK,0\n",7,{"OK",8'd13,8'd10});
            first=monitor.pcm_count;
            case(i)
                0: gesture(1,2,32'd23012828,0);
                1: gesture(3,4,32'd25831026,1);
                2: gesture(2,1,32'd43442435,2);
                3: gesture(4,3,32'd46025656,3);
                4: gesture(1,2,32'd23012828,4);
            endcase
            frames(300); check_sound(first,100); gesture_silence;
        end
        transact("TONE,0\n",7,{"OK",8'd13,8'd10});
        transact("VIBRATO,1\n",10,{"OK",8'd13,8'd10});
        gesture(1,2,32'd23012828,0); frames(300);
        if(dut.u_gesture.u_audio.u_synth.depth!==256 ||
           dut.u_gesture.u_audio.u_synth.lfo_scaled===0)
            $fatal(1,"UART vibrato did not change gesture oscillator pitch");
        transact("BANK,1\n",7,{"OK",8'd13,8'd10});
        transact("TONE,3\n",7,{"OK",8'd13,8'd10});
        if(((dut.u_gesture.u_audio.u_synth.peek_context(0)>>274)&32'hffffffff)!==23012828 || ((dut.u_gesture.u_audio.u_synth.peek_context(0)>>271)&7)!==0)
            $fatal(1,"New controls retuned/revoiced a sounding gesture");
        transact("VIBRATO,0\n",10,{"OK",8'd13,8'd10}); frames(260);
        if(dut.u_gesture.u_audio.u_synth.depth!==0) $fatal(1,"UART vibrato failed to ramp off");
        gesture_silence;
        $display("PASS [integrated gestures]: all four directions, both banks, five audible timbres, latched note/timbre, vibrato on/off and release to external I2S zero");

        first=monitor.pcm_count;
        transact("GUITAR\n",7,{"OK",8'd13,8'd10}); frames(80); check_sound(first,500);
        frames(1000); first=monitor.pcm_count; frames(64); check_silence(first);
        // Exercise all three live sources concurrently through the final mix.
        pads=8'h7f; wait(dut.touch_keys==8'h7f); frames(20);
        gesture(1,2,32'd34480283,3);
        transact("GUITAR\n",7,{"OK",8'd13,8'd10});
        first=monitor.pcm_count; frames(300); held(7'h7f); check_sound(first,500);
        transact("STOP\n",5,{"OK",8'd13,8'd10}); held(7'h7f);
        pads=0; wait(dut.touch_keys==0 && dut.touch_active==0);
        frames(1000); first=monitor.pcm_count; old_latches=panel_latches;
        frames(64); check_silence(first);
        if(panel_latches<=old_latches || monitor.pair_count<4000 || reply_count!=next_reply)
            $fatal(1,"Insufficient panel/I2S/UART integration coverage");
        $display("PASS [top integrated]: guitar command/external sound/decay, seven keys + gesture + guitar without clipping, final silence; %0d UART replies, %0d stereo pairs, %0d panel rows",reply_count,monitor.pair_count,panel_latches);
        $fclose(monitor.capture_file); $finish;
    end
    initial begin
        #400000000;
        $fatal(1,"Integrated timeout: replies=%0d/%0d touch=%h score=%h gesture=%0d guitar=%0d",reply_count,next_reply,dut.touch_keys,dut.song_guide_keys,dut.sensor_voice_count,dut.guitar_sample);
    end
endmodule
