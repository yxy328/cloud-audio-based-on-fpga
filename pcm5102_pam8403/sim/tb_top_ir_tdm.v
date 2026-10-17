`timescale 1ns/1ps
// Real 50MHz, production 1ms IR qualification, external UART/I2S/HUB pins.
module tb_top_ir_tdm;
    reg clk=0; always #10 clk=~clk;
    reg [7:0] beams=255,pads=0;
    reg rx=1;
    wire tx,bck,lrck,din,lat;
    tri1 scl,sda;
    integer events=0,frames_seen=0,latches=0,k,first,nonzero;
    time edge_time;
    reg [31:0] seen_pitches=0,pitch;
    integer test_index;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),
        .TOUCH_DEBOUNCE_MS(1),.ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .TOUCH_ADSR_RELEASE_SAMPLES(32),.FSR_ENABLE(0)) dut (
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(pads),.ir_beam(beams),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
        .scl(scl),.sda(sda),.hub_ST(lat)
    );
    defparam dut.u_gesture.AUDIO_NOTE_FRAMES=400;
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767)) monitor (
        .bck(bck),.lrck(lrck),.din(din));
    always @(posedge lat) latches=latches+1;
    always @(negedge clk) if(dut.resetn) begin
        if(dut.ir_note_valid) events=events+1;
        if(dut.frame_ce) frames_seen=frames_seen+1;
        if(dut.sensor_overrun) $fatal(1,"Sensor FIFO or TDM deadline overrun");
    end
    task frames;
        input integer n;
        integer until_frame;
        begin until_frame=frames_seen+n; wait(frames_seen>=until_frame); @(negedge clk); end
    endtask
    task send_byte;
        input [7:0] c;
        integer b;
        begin
            rx=0;repeat(100) @(negedge clk);
            for(b=0;b<8;b=b+1) begin rx=c[b];repeat(100) @(negedge clk);end
            rx=1;repeat(100) @(negedge clk);
        end
    endtask
    task receive_ok;
        integer c,b;
        reg [7:0] data;
        reg [31:0] line;
        begin
            line=0;
            for(c=0;c<4;c=c+1) begin
                @(negedge tx);repeat(50) @(posedge clk);
                for(b=0;b<8;b=b+1) begin repeat(100) @(posedge clk);data[b]=tx;end
                repeat(100) @(posedge clk);
                if(tx!==1) $fatal(1,"UART stop bit");
                line={line[23:0],data};
            end
            if(line!=={"OK",8'd13,8'd10}) $fatal(1,"TEST32 acknowledgement %h",line);
        end
    endtask
    initial begin
        wait(dut.resetn);frames(80);
        if(events || dut.sensor_voice_count || monitor.last_pcm) $fatal(1,"Floating/blocked IR played at startup");
        if(dut.gesture_ready) $fatal(1,"Missing APDS unexpectedly ready");
        beams=0;#1100000;
        if(dut.ir_armed!==255 || events) $fatal(1,"IR stable-light arming");
        edge_time=$time;first=monitor.pcm_count;beams=255;
        wait(dut.ir_note_valid);@(negedge clk);
        // Deliberately coincide a classified gesture with the first IR event.
        force dut.u_gesture.init_done=1;
        force dut.u_gesture.dir_evaluated=1;
        force dut.u_gesture.start_dir=1;
        force dut.u_gesture.end_dir=2;
        force dut.u_gesture.gesture_valid=1;
        @(negedge clk);force dut.u_gesture.gesture_valid=0;
        wait(dut.sensor_voice_count==9);
        wait(monitor.last_pcm!=0);
        $display("IR digital edge to first external I2S PCM: %0d ns",$time-edge_time);
        if($time-edge_time>5000000) $fatal(1,"IR digital path exceeds 5ms");
        frames(100);
        if(events!=8 || dut.sensor_voice_count!=9) $fatal(1,"Held beam repeated / simultaneous event lost");
        pads=127;wait(dut.touch_keys[6:0]==127);frames(12);
        if(dut.touch_active[6:0]!==127) $fatal(1,"Seven touch voices lost while IR active");
        pads=0;wait(dut.touch_keys[6:0]==0);frames(45);
        // IR remains blocked: TEST32 now replaces existing voices once.
        fork
            receive_ok;
            begin send_byte("T");send_byte("E");send_byte("S");send_byte("T");send_byte("3");send_byte("2");send_byte(10);end
        join
        frames(400);
        if(dut.sensor_voice_count!=32 || dut.sensor_voice_active!==32'hffffffff)
            $fatal(1,"TEST32 did not activate 32 voices");
        for(k=0;k<32;k=k+1) begin
            pitch=(dut.u_gesture.u_audio.u_synth.peek_context(k)>>274)&32'hffffffff;
            test_index=((pitch>>20)-37)/7;
            if(test_index<0 || test_index>31 || pitch!==((37+7*test_index)<<20) || seen_pitches[test_index])
                $fatal(1,"TEST32 voice %0d missing independent frequency: %0d",k,pitch);
            seen_pitches[test_index]=1;
        end
        if(seen_pitches!==32'hffffffff) $fatal(1,"TEST32 frequency set incomplete");
        first=monitor.pcm_count;frames(4100);
        nonzero=0;
        for(k=first;k<monitor.pcm_count;k=k+1) begin
            if(monitor.pcm[k]!=0) nonzero=nonzero+1;
            if(monitor.pcm[k]==32767 || monitor.pcm[k]==-32768) $fatal(1,"TEST32 clipped");
        end
        if(nonzero<4000 || events!=8 || latches<1000) $fatal(1,"I2S/panel/event activity");
        $display("PASS top IR8+same-clock gesture, held/no-APDS/startup, seven touch voices, UART TEST32, 32 independent frequencies, external stereo I2S/panel; PCM=%0d",monitor.pcm_count);
        $finish;
    end
    initial begin #150000000;$fatal(1,"IR/TDM top timeout count=%0d events=%0d",dut.sensor_voice_count,events);end
endmodule
