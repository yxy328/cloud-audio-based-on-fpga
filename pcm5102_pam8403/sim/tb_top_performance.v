`timescale 1ns/1ps
// Real 50MHz, production 1ms IR qualification, external UART/I2S/HUB pins.
module tb_top_performance;
    reg clk=0; always #10 clk=~clk;
    reg [7:0] beams=255,pads=0;
    reg rx=1;
    wire tx,bck,lrck,din,lat;
    tri1 scl,sda;
    integer events=0,frames_seen=0,latches=0,k,first,nonzero;
    time edge_time;
    reg [31:0] seen_pitches=0,pitch;
    integer test_index;
    top #(.ENABLE_EVENT_TAKE(1),.EVENT_KEYS_ENABLE(0),.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),
        .TOUCH_DEBOUNCE_MS(1),.ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .TOUCH_ADSR_RELEASE_SAMPLES(32),.FSR_ENABLE(0)) dut (
        .flash_miso(1'b1),.touch_sdo(1'b1),.audio_rec_cts_n(1'b0),.clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(pads),.ir_beam(beams),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
        .scl(scl),.sda(sda),.hub_ST(lat)
    );
    defparam dut.u_gesture.AUDIO_NOTE_FRAMES=400;
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767)) monitor (
        .bck(bck),.lrck(lrck),.din(din),.resetn(dut.resetn));
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
            if(line!=={"OK",8'd13,8'd10}) $fatal(1,"Performance acknowledgement %h",line);
        end
    endtask
    task command;
        input [511:0] message;input integer length;integer b;
        begin fork receive_ok; begin for(b=length-1;b>=0;b=b-1)send_byte(message[b*8 +: 8]);end join end
    endtask
    genvar v;
    generate for(v=0;v<7;v=v+1)begin: phase_check
        reg [31:0] expected;
        always @(posedge clk)if(dut.resetn && dut.u_touch_synth.state==7 && dut.u_touch_synth.index==v)begin
            expected=dut.u_touch_synth.phase+dut.u_touch_synth.frame_steps[v*32 +:32];
            #1;
            if(dut.u_touch_synth.phase!==expected)$fatal(1,"Live bend reset DDS phase %0d",v);
        end
    end endgenerate
    reg [63:0] expected_product;
    initial begin
        wait(dut.resetn);frames(20);
        command("PITCH,14596,18390,4096,19573\n",29);
        frames(4);
        if(dut.bend_min!=14596 || dut.bend_max!=18390 || dut.bend_slew!=4096 || dut.tuning_ratio!=19573)$fatal(1,"Top pitch parameter wiring");
        pads=1;wait(dut.touch_keys[0]);frames(8);
        command("BEND,1,18390\n",13);
        frames(170);
        expected_product=64'd23012828*18390;expected_product=expected_product>>14;
        if(dut.touch_phase_increments[31:0]>expected_product+3 || dut.touch_phase_increments[31:0]+3<expected_product)$fatal(1,"Touch pitch changed outside sensor-only tuning scope");
        command("VIB,10,48327,948,9766\n",22);
        command("VIBRATO,1\n",10);
        frames(100);
        if(dut.u_gesture.u_audio.u_synth.vibrato_inc!=703687 || dut.u_gesture.u_audio.u_synth.vibrato_depth!=948 ||
            dut.u_gesture.u_audio.u_synth.vibrato_wait==0 || dut.u_gesture.u_audio.u_synth.depth!=0)$fatal(1,"Top vibrato parameter/onset wiring");
        command("EFFECT2,3\n",10);
        command("EFFECT,1,8\n",11);
        frames(18);
        if(dut.echo_tap!=3 || dut.u_effects.echo_tap!=3 || dut.u_effects.filled==0)$fatal(1,"Top echo runtime wiring/capture cadence");
        if(dut.u_gesture.u_audio.u_synth.frame_tuning!=19573)$fatal(1,"Sensor tuning not connected");
        if(monitor.pcm_count<100 || !latches)$fatal(1,"I2S or panel stopped");
        pads=0;wait(dut.touch_keys[0]==0);frames(40);
        $display("PASS unified top performance: framed UART -> pitch/glide/vibrato registers -> live DDS/I2S, shared sensor onset, shared sensor tuning, four-tap echo wiring, preserved held phase and panel timing");$finish;
    end
    initial begin #120000000;$fatal(1,"Top performance timeout");end
endmodule
