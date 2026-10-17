`timescale 1ns/1ps
// Real 50MHz, production 1ms IR qualification, external UART/I2S/HUB pins.
module tb_top_voice_bend;
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
    task command;
        input [511:0] message;input integer length;integer b;
        begin fork receive_ok; begin for(b=length-1;b>=0;b=b-1)send_byte(message[b*8 +: 8]);end join end
    endtask
    genvar v;
    generate for(v=0;v<7;v=v+1)begin: phase_check
        reg [31:0] expected;
        always @(posedge clk)if(dut.resetn && dut.frame_ce)begin
            expected=dut.touch_voices[v/4].u_synth.voices[v%4].u_voice.u_dds.phase+dut.touch_phase_increments[v*32 +:32];
            #1;
            if(dut.touch_voices[v/4].u_synth.voices[v%4].u_voice.u_dds.phase!==expected)$fatal(1,"Live bend reset DDS phase %0d",v);
        end
    end endgenerate
    reg [223:0] base;
    reg [63:0] envelope0,envelope1;
    reg [47:0] expected_product;
    initial begin
        wait(dut.resetn);frames(10);
        pads=127;wait(dut.touch_keys[6:0]==127);frames(12);
        base=dut.touch_base_increments;
        envelope0=dut.touch_voices[0].u_synth.envelope_gains;
        envelope1=dut.touch_voices[1].u_synth.envelope_gains;
        command("BEND,2,17358\n",13);frames(70);
        for(k=0;k<7;k=k+1)begin
            expected_product=base[k*32+:32]*((k==1)?16'd17358:16'd16384);
            if(dut.touch_phase_increments[k*32+:32]!==expected_product[45:14])$fatal(1,"Top addressed bend changed wrong key %0d",k);
        end
        command("BEND,4,15464\n",13);frames(70);
        for(k=0;k<7;k=k+1)begin
            expected_product=base[k*32+:32]*((k==1)?16'd17358:((k==3)?16'd15464:16'd16384));
            if(dut.touch_phase_increments[k*32+:32]!==expected_product[45:14])$fatal(1,"Top second bend wrong key %0d",k);
        end
        if(dut.touch_voices[0].u_synth.envelope_gains!==envelope0 || dut.touch_voices[1].u_synth.envelope_gains!==envelope1)$fatal(1,"Bend altered held ADSR");
        if(monitor.pcm_count<100 || !latches)$fatal(1,"External I2S/LED stopped");
        nonzero=0;for(k=0;k<monitor.pcm_count;k=k+1)if(monitor.pcm[k])nonzero=nonzero+1;
        if(nonzero<100)$fatal(1,"Live chords not audible on I2S");
        command("BEND_RESET\n",11);frames(70);
        if(dut.touch_phase_increments[223:0]!==base)$fatal(1,"Reset failed to restore all held voices");
        pads=0;wait(dut.touch_keys[6:0]==0);frames(40);
        if(monitor.last_pcm)$fatal(1,"Release failed to silence I2S");
        $display("PASS top voice bend: seven held voices, addressed +100/-100cent targets via bit-level UART, intact DDS phases/ADSR/LED/I2S, acknowledged smooth reset, release silence");$finish;
    end
    initial begin #20000000;$fatal(1,"Top bend timeout");end
endmodule
