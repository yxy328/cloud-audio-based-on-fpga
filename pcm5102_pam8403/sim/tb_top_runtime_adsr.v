`timescale 1ns/1ps
// Real 50MHz, production 1ms IR qualification, external UART/I2S/HUB pins.
module tb_top_runtime_adsr;
    reg clk=0; always #10 clk=~clk;
    reg [7:0] beams=255,pads=0;
    reg rx=1;
    wire tx,bck,lrck,din,lat,touch_scl,touch_sdo;
    tri1 scl,sda;
    integer events=0,frames_seen=0,latches=0,k,first,nonzero;
    time edge_time;
    reg [31:0] seen_pitches=0,pitch;
    integer test_index;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),
        .TOUCH_DEBOUNCE_MS(1),.ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .TOUCH_ADSR_RELEASE_SAMPLES(32),.FSR_ENABLE(0)) dut (
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.touch_scl(touch_scl),.touch_sdo(touch_sdo),.ir_beam(beams),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
        .scl(scl),.sda(sda),.hub_ST(lat)
    );
    // Current production is fixed serial16; retain pads as the stimulus
    // for the first eight physical sensor channels, with all ADSR checks.
    ttp229_model chip(.rst_n(dut.resetn),.scl(touch_scl),.connected(1'b1),
        .dv(1'b0),.stuck_low(1'b0),.keys({8'd0,pads}),.sdo(touch_sdo));
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
    task command;
        input [511:0] message;input integer length;integer b;
        begin fork receive_ok; begin for(b=length-1;b>=0;b=b-1)send_byte(message[b*8 +: 8]);end join end
    endtask
    initial begin
        wait(dut.resetn);wait(dut.touch_ready);frames(10);
        command("ADSR,TOUCH,1,1,50,1\n",20);
        pads=1;wait(dut.touch_keys[0]);frames(120);
        if(dut.u_touch_synth.gains[15:0]!=32767) $fatal(1,"Touch UART envelope did not reach 50 percent");
        command("ADSR,TOUCH,0,0,25,1\n",20);
        if(dut.u_touch_synth.gains[15:0]!=32767) $fatal(1,"Held touch changed profile");
        pads=3;wait(dut.touch_keys[1]);frames(8);
        if(dut.u_touch_synth.gains[15:0]!=32767 || dut.u_touch_synth.gains[31:16]!=16383)
            $fatal(1,"Two independently snapshotted touch envelopes");
        pads=0;wait(dut.touch_keys==0);frames(80);if(monitor.last_pcm) $fatal(1,"Touch R did not become silent");
        command("ADSR,SENSOR,1,1,50,1\n",21);
        beams=0;#1100000;beams=1;wait(dut.sensor_voice_count==1);frames(150);
        if(((dut.u_gesture.u_audio.u_synth.peek_context(0)>>245)&511)!=128) $fatal(1,"IR UART ADSR did not reach S50");
        command("ADSR,SENSOR,0,0,25,1\n",21);
        beams=3;wait(dut.sensor_voice_count==2);frames(60);
        if(((dut.u_gesture.u_audio.u_synth.peek_context(0)>>245)&511)!=128 ||
           ((dut.u_gesture.u_audio.u_synth.peek_context(1)>>245)&511)!=64) $fatal(1,"IR active-note snapshot/new-note config");
        command("ADSR_RESET,SENSOR\n",18);
        if(dut.sensor_adsr!==0) $fatal(1,"Sensor legacy restore failed");
        wait(dut.sensor_voice_count==0);frames(16);if(monitor.last_pcm) $fatal(1,"IR release did not silence external I2S");
        command("ADSR_RESET,TOUCH\n",17);
        if(dut.touch_adsr!=={16'd4,16'd4,16'd39321,16'd32}) $fatal(1,"Touch reset defaults lost top parameters");
        if(dut.gesture_ready || latches<1000 || monitor.pair_count<500) $fatal(1,"I2S/LED/absent APDS coverage");
        $display("PASS top runtime ADSR: UART to independent touch/IR profiles, held snapshot, new-note gain, reset, external I2S silence and 64x64 scanning; pairs=%0d",monitor.pair_count);$finish;
    end
    initial begin #50000000;$fatal(1,"Top ADSR timeout");end
endmodule