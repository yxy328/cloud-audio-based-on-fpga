`timescale 1ns/1ps
// Real 50 MHz clocks, 500000-baud UART, and independently decoded I2S pins.
// Upload signed 8-bit/8000 Hz PCM, check every resampled output frame, then
// exercise physical playback controls with builtin, score, and PCM available.
module tb_top_pcm;
    localparam BIT_TICKS=100;
    reg clk=0;
    always #10 clk=~clk;
    reg rx=1, s1=0, s2=0;
    wire tx,bck,lrck,din;
    reg [255:0] replies[0:63], incoming=0;
    reg [7:0] decoded;
    reg [7:0] source[0:31];
    integer reply_count=0, expected_count=0, bit_index;
    integer capture_start, first_pcm, cursor, sample_index, repeats, phase;
    integer expected_sample, i, overlap_cycles=0;
    top #(.HC05_BAUD(500000),.KEY_CONFIRM_CYCLES(100),.TOUCH_STARTUP_US(100),
        .TOUCH_MODE_DEBOUNCE_MS(1),.FSR_ENABLE(0),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.ADSR_RELEASE_SAMPLES(16),
        .TOUCH_ADSR_RELEASE_SAMPLES(16),.SONG_BEAT_SAMPLES(64),
        .SONG_GAP_SAMPLES(16),.SONG_INTRO_SAMPLES(16),.SONG_TAIL_SAMPLES(32)) dut(
        .clk(clk),.key_s1(s1),.key_s2(s2),.touch_out(8'h00),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),
        .i2s_din(din),.touch_scl());
    // This monitor checks the physical BCK/LRCK periods, I2S padding and
    // left/right equality in addition to storing the external left samples.
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767)) monitor(
        .bck(bck),.lrck(lrck),.din(din));

    initial forever begin
        @(negedge tx); repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"PCM top TX start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            repeat(BIT_TICKS) @(posedge clk); decoded[bit_index]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"PCM top TX stop bit");
        incoming={incoming[247:0],decoded};
        if(decoded==10) begin
            replies[reply_count]=incoming; reply_count=reply_count+1; incoming=0;
        end
    end
    task transact;
        input [511:0] message;
        input integer length;
        input [255:0] expected;
        integer j,b;
        begin
            for(j=length-1;j>=0;j=j-1) begin
                @(negedge clk); rx=0; repeat(BIT_TICKS) @(negedge clk);
                for(b=0;b<8;b=b+1) begin
                    rx=message[j*8+b]; repeat(BIT_TICKS) @(negedge clk);
                end
                rx=1; repeat(BIT_TICKS) @(negedge clk);
            end
            wait(reply_count>expected_count);
            if(replies[expected_count]!==expected)
                $fatal(1,"PCM top reply expected '%0s', got '%0s'",expected,replies[expected_count]);
            expected_count=expected_count+1;
            @(negedge clk);
        end
    endtask
    task press_s1;
        begin
            @(negedge clk); s1=1; repeat(300) @(negedge clk);
            s1=0; repeat(300) @(negedge clk);
        end
    endtask
    task press_s2;
        begin
            @(negedge clk); s2=1; repeat(300) @(negedge clk);
            s2=0; repeat(300) @(negedge clk);
        end
    endtask
    task silence;
        integer start_frame,j;
        begin
            wait(!dut.song_playing && dut.song_active==0);
            start_frame=monitor.pcm_count;
            wait(monitor.pcm_count>=start_frame+40); #1;
            for(j=monitor.pcm_count-16;j<monitor.pcm_count;j=j+1)
                if(monitor.pcm[j]!=0) $fatal(1,"Final I2S output was not silent");
        end
    endtask
    task pcm_selected;
        begin
            if(!dut.pcm_playing || dut.downloaded_playing || dut.builtin_playing)
                $fatal(1,"Physical key did not exclusively select PCM");
        end
    endtask
    // Command/physical-control stop pulses pass through one registered
    // handshake. A transient of <=3 clocks is allowed; sustained overlap fails.
    always @(posedge clk) begin
        #1;
        if((dut.pcm_playing && (dut.builtin_playing || dut.downloaded_playing)) ||
           (dut.builtin_playing && dut.downloaded_playing)) begin
            overlap_cycles=overlap_cycles+1;
            if(overlap_cycles>3) $fatal(1,"Playback sources remained active together");
        end else overlap_cycles=0;
    end

    initial begin
        source[0]=8'h80; source[1]=8'h90; source[2]=8'ha0; source[3]=8'hb0;
        source[4]=8'hc0; source[5]=8'hd0; source[6]=8'he0; source[7]=8'hf0;
        source[8]=8'h10; source[9]=8'h20; source[10]=8'h30; source[11]=8'h40;
        source[12]=8'h50; source[13]=8'h60; source[14]=8'h70; source[15]=8'h7f;
        source[16]=8'h81; source[17]=8'h91; source[18]=8'ha1; source[19]=8'hb1;
        source[20]=8'hc1; source[21]=8'hd1; source[22]=8'he1; source[23]=8'hf1;
        source[24]=8'h11; source[25]=8'h21; source[26]=8'h31; source[27]=8'h41;
        source[28]=8'h51; source[29]=8'h61; source[30]=8'h71; source[31]=8'h7e;
        wait(dut.touch_ready);
        // The original builtin source still responds to both physical keys.
        press_s1;
        if(!dut.builtin_playing) $fatal(1,"S1 did not start builtin song");
        wait(dut.u_control.note_index!=0);
        press_s2;
        if(!dut.builtin_playing || dut.u_control.note_index!=0)
            $fatal(1,"S2 did not restart builtin song");
        press_s1; silence;

        transact({"PCM_BEGIN,32,4108",8'd10},18,{"OK",8'd13,8'd10});
        transact({"PCM_DATA,0,8090A0B0C0D0E0F0102030405060707F",8'd10},44,{"OK",8'd13,8'd10});
        transact({"PCM_DATA,16,8191A1B1C1D1E1F1112131415161717E",8'd10},45,{"OK",8'd13,8'd10});
        transact({"PCM_END",8'd10},8,{"OK",8'd13,8'd10});
        if(!dut.pcm_valid || dut.pcm_playing) $fatal(1,"PCM commit failed");
        capture_start=monitor.pcm_count;
        transact({"PCM_PLAY",8'd10},9,{"OK",8'd13,8'd10});

        // Locate the first serialized source sample, then compare each and
        // every output frame against an independent rational-rate reference.
        first_pcm=capture_start;
        while(monitor.pcm[first_pcm]!=-32768) begin
            if(first_pcm>=monitor.pcm_count) wait(monitor.pcm_count>first_pcm);
            if(monitor.pcm[first_pcm]!=-32768) first_pcm=first_pcm+1;
        end
        cursor=first_pcm; phase=0;
        for(sample_index=0;sample_index<32;sample_index=sample_index+1) begin
            repeats=0;
            while(phase<50000000) begin phase=phase+8192000; repeats=repeats+1; end
            phase=phase-50000000;
            expected_sample=(source[sample_index]<128) ? source[sample_index]*256 :
                (source[sample_index]-256)*256;
            wait(monitor.pcm_count>=cursor+repeats); #1;
            for(i=0;i<repeats;i=i+1)
                if(monitor.pcm[cursor+i]!==expected_sample)
                    $fatal(1,"PCM sample %0d frame %0d expected %0d got %0d",sample_index,i,expected_sample,monitor.pcm[cursor+i]);
            cursor=cursor+repeats;
        end
        wait(monitor.pcm_count>=cursor+16); #1;
        for(i=cursor;i<cursor+16;i=i+1)
            if(monitor.pcm[i]!=0) $fatal(1,"PCM continued after its last sample");
        if(dut.pcm_playing || cursor-first_pcm!=196)
            $fatal(1,"Wrong PCM playback duration: %0d frames",cursor-first_pcm);

        // Text PLAY selects builtin before a score exists; S1/S2 must then
        // stop it and select the already committed PCM clip.
        transact({"PLAY",8'd10},5,{"OK",8'd13,8'd10});
        if(!dut.builtin_playing) $fatal(1,"PLAY did not start builtin source");
        press_s1; pcm_selected;
        press_s1; silence;
        transact({"PLAY",8'd10},5,{"OK",8'd13,8'd10});
        press_s2; pcm_selected;
        transact({"STOP",8'd10},5,{"OK",8'd13,8'd10}); silence;

        // Both downloaded formats remain valid. PLAY explicitly selects the
        // score, whereas physical S1/S2 select PCM and stop that score.
        transact({"SONG_BEGIN,2",8'd10},13,{"OK",8'd13,8'd10});
        transact({"SONG_NOTE,0,60,20",8'd10},18,{"OK",8'd13,8'd10});
        transact({"SONG_NOTE,1,67,20",8'd10},18,{"OK",8'd13,8'd10});
        transact({"SONG_END",8'd10},9,{"OK",8'd13,8'd10});
        transact({"PLAY",8'd10},5,{"OK",8'd13,8'd10});
        if(!dut.downloaded_playing || dut.pcm_playing || dut.builtin_playing)
            $fatal(1,"PLAY did not exclusively select downloaded score");
        press_s1; pcm_selected;
        press_s2; pcm_selected;
        if(dut.u_keymap.u_pcm.play_index!=0) $fatal(1,"S2 did not restart PCM at index zero");
        press_s1; silence;
        transact({"PLAY",8'd10},5,{"OK",8'd13,8'd10});
        press_s2; pcm_selected;
        transact({"STOP",8'd10},5,{"OK",8'd13,8'd10}); silence;
        $display("PASS [top PCM]: real UART upload/commit/play; 32 exact signed amplitudes over 196 I2S frames, stereo, timing, final silence; builtin/score/PCM S1/S2 mutual exclusion");
        $fclose(monitor.capture_file); $finish;
    end
    initial begin #100000000;$fatal(1,"Top PCM timeout"); end
endmodule
