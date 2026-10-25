`timescale 1ns/1ps
// Baseline evidence for the proposed shared engine. Both DUTs are unchanged.
// Each measured window is exactly 1024 clocks, including its accepting edge.
// Stimulus may preload queues BETWEEN windows; this is not a continuous
// top-level I2S/UART test and does not validate an unimplemented merged core.
module tb_engine_merge_baseline;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,ce=0,event_valid=0,test_valid=0;
    reg [31:0] event_inc=1000;
    reg [15:0] gates=0;
    reg [4:0] poly_limit=16;
    wire sensor_busy,sensor_overrun,touch_overrun;
    wire [31:0] sensor_active;
    wire [5:0] sensor_count;
    wire [15:0] touch_active;
    wire [4:0] touch_count;
    integer i,j,frame_id=0,max_sensor=0,max_touch=0,divide_frames=0;
    integer sensor_cycles,touch_cycles,events,commands,prime,divides;

    tdm_synth #(.VOICES(32),.EXTENDED_TIMBRES(1),.RUNTIME_ADSR(1),
        .PRESET_FRAMES(1),.VOLUME_SHIFT(6)) sensor(
        .clk(clk),.resetn(resetn),.sample_ce(ce),
        .event_valid(event_valid),.chord_valid(1'b0),.test_valid(test_valid),
        .vibrato_enabled(1'b0),.vibrato_inc(32'd0),.vibrato_depth(10'd0),
        .vibrato_delay(16'd0),.vibrato_update(1'b0),.tuning_ratio(16'd16384),
        .event_inc(event_inc),.event_timbre(3'd0),.event_frames(17'd1000),
        .event_adsr(130'd0),.voice_active(sensor_active),.voice_count(sensor_count),
        .sample(),.overrun(sensor_overrun),.busy(sensor_busy),.event_ready());

    touch_tdm_synth #(.EXTENDED_CONTROL(1)) touch(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.gates(gates),
        .physical_gates(gates),.pedal_mode(2'd0),.poly_limit(poly_limit),
        .low_steps({7{32'd23012828}}),
        .adsr_config({16'd4,16'd4,16'd39321,16'd8}),.pitch_ratio(16'd65535),
        .sample(),.active(touch_active),.voice_count(touch_count),
        .clipped(),.overrun(touch_overrun));

    task frame;
        input integer scenario;
        integer tick;
        begin
            if(sensor.state!=sensor.IDLE || touch.state!=touch.IDLE)
                $fatal(1,"Frame started with a busy engine");
            sensor_cycles=0;touch_cycles=0;events=0;commands=0;prime=0;divides=0;
            ce=1;
            for(tick=0;tick<1024;tick=tick+1)begin
                @(posedge clk);
                // Sample before nonblocking assignments, including accept/publish.
                if(ce || sensor.state!=sensor.IDLE)sensor_cycles=sensor_cycles+1;
                if(ce || touch.state!=touch.IDLE)touch_cycles=touch_cycles+1;
                if(sensor.state==sensor.EVENT_COMMIT)events=events+1;
                if(sensor.state==sensor.COMMAND_FETCH)commands=commands+1;
                if(sensor.state==sensor.VOICE_PRIME)prime=prime+1;
                if(touch.state==touch.DIVIDE)divides=divides+1;
                @(negedge clk);ce=0;
            end
            if(sensor.state!=sensor.IDLE || touch.state!=touch.IDLE)
                $fatal(1,"Engine missed the 1024-clock deadline");
            if(sensor_overrun || touch_overrun)$fatal(1,"Unexpected overrun");
            if(sensor_cycles!=16*32+11*events+2*commands+23 || prime!=17)
                $fatal(1,"Sensor budget formula changed: %0d E=%0d C=%0d prime=%0d",
                    sensor_cycles,events,commands,prime);
            if(touch_cycles!=756+divides || divides%16!=0 || divides>256)
                $fatal(1,"Touch budget formula changed: %0d divides=%0d",touch_cycles,divides);
            if(sensor_cycles>max_sensor)max_sensor=sensor_cycles;
            if(touch_cycles>max_touch)max_touch=touch_cycles;
            if(divides==256)divide_frames=divide_frames+1;
            $display("FRAME id=%0d scenario=%0d sensor=%0d E=%0d C=%0d prime=%0d touch=%0d divide_cycles=%0d sensor_count=%0d touch_count=%0d",
                frame_id,scenario,sensor_cycles,events,commands,prime,touch_cycles,divides,sensor_count,touch_count);
            frame_id=frame_id+1;
        end
    endtask

    initial begin
        repeat(5)@(negedge clk);resetn=1;
        wait(!sensor_busy && touch.state==touch.IDLE);@(negedge clk);
        for(i=0;i<256;i=i+1)
            if(sensor.sine_table[i] !== touch.u_sine.memory[4*i])
                $fatal(1,"Sine ROM decimation mismatch at %0d",i);
        frame(0);
        if(sensor_cycles!=535 || touch_cycles!=756)$fatal(1,"Idle baseline");

        test_valid=1;@(negedge clk);test_valid=0;gates=16'hffff;
        frame(1);
        if(sensor_cycles!=889 || events!=32 || commands!=1 || sensor_count!=32 ||
           touch_cycles!=1012 || divides!=256 || touch_active!=16'hffff)
            $fatal(1,"TEST32 plus all-key attack baseline");
        for(i=0;i<32;i=i+1)
            if(((sensor.peek_context(i)>>326)&32'hffffffff)!==((37+7*i)<<20))
                $fatal(1,"TEST32 pitch/count mismatch at slot %0d",i);

        for(i=0;i<32;i=i+1)begin
            event_valid=1;event_inc=1000+i;@(negedge clk);
        end
        event_valid=0;frame(2);
        if(sensor_cycles!=951 || events!=32 || commands!=32 || sensor_count!=32 ||
           touch_active!=16'hffff)$fatal(1,"Independent-event burst baseline");
        for(i=0;i<32;i=i+1)
            if(((sensor.peek_context(i)>>326)&32'hffffffff)!==1000+i)
                $fatal(1,"Full-pool oldest replacement failed at %0d",i);

        repeat(10)frame(3);
        for(j=0;j<16;j=j+1)
            if(touch.contexts[j*16+3]!=39321 || touch.contexts[j*16+2][2:0]!=3)
                $fatal(1,"Touch sustain baseline at key %0d",j);
        poly_limit=1;
        repeat(4)begin
            frame(4);
            if(touch_active!=16'hffff || touch_count!=16 || touch.victim_valid)
                $fatal(1,"Physical keys must remain protected at poly_limit=1");
        end

        poly_limit=16;gates=0;frame(5);
        if(divides!=256 || touch_cycles!=1012)$fatal(1,"All-key release budget");
        repeat(10)frame(6);
        if(touch_active!=0 || touch_count!=0)$fatal(1,"Touch release not complete");
        if(max_sensor!=951 || max_touch!=1012 || divide_frames<3)
            $fatal(1,"Required pressure scenarios were not reached");
        $display("PASS engine-merge BASELINE: frames=%0d sensor_max=%0d touch_max=%0d all16_divide_frames=%0d; ROM256 equality, TEST32 unique pitches, oldest replacement, physical protection; no merged RTL tested",
            frame_id,max_sensor,max_touch,divide_frames);
        $finish;
    end
    initial begin #2000000;$fatal(1,"Engine merge baseline timeout");end
endmodule
