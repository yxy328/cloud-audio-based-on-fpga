`timescale 1ns/1ps
// Measure independent engines on the same real 50 MHz / 1024-clock frame.
// UART and TTP229 pins drive the workload; no RTL signal is forced.
module tb_score_bend_frame_take;
    localparam BIT_TICKS=100;
    reg clk=0; always #10 clk=~clk;
    reg rx=1;
    reg [15:0] keys=0;
    wire tx,tscl,sdo;
    tri1 scl,sda,ads_scl,ads_sda;
    reg [15:0] slider_code=32767;
    ads1115_model slider(.clk(clk),.scl(ads_scl),.sda(ads_sda),.present(1'b1),.code(slider_code));
    top #(.ENABLE_EVENT_TAKE(1),.EVENT_KEYS_ENABLE(0),.FSR_ENABLE(1),.SLIDER_STARTUP_MS(1),.SLIDER_POLL_MS(1),
        .TOUCH_SERIAL_HALF_CYCLES(50),.TOUCH_SERIAL_GAP_CYCLES(2500),.TOUCH_SERIAL_QUIET_CYCLES(100),.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.GUIDE_LEAD_MS(60),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),
        .TOUCH_ADSR_RELEASE_SAMPLES(16)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),
        .touch_sdo(sdo),.touch_scl(tscl),.ir_beam(8'hff),
        .hc05_rx(rx),.hc05_tx(tx),.audio_rec_cts_n(1'b1),
        .flash_miso(1'b1),.scl(scl),.sda(sda),.slider_scl(ads_scl),.slider_sda(ads_sda));
    ttp229_model #(.TIMEOUT_NS(40000)) chip(.rst_n(dut.resetn),.scl(tscl),.connected(1'b1),
        .dv(1'b0),.stuck_low(1'b0),.keys(keys),.sdo(sdo));

    reg [255:0] incoming=0,replies[0:63];
    reg [7:0] decoded;
    integer reply_count=0,next_reply=0,rx_bit;
    initial forever begin
        @(negedge tx); repeat(BIT_TICKS/2) @(posedge clk);
        for(rx_bit=0;rx_bit<8;rx_bit=rx_bit+1)begin
            repeat(BIT_TICKS) @(posedge clk); decoded[rx_bit]=tx;
        end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1'b1)$fatal(1,"UART stop bit");
        incoming={incoming[247:0],decoded};
        if(decoded==10)begin
            replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;
        end
    end
    task command;
        input [511:0] message;
        input integer length;
        integer c,b;
        begin
            for(c=length-1;c>=0;c=c-1)begin
                @(negedge clk);rx=0;repeat(BIT_TICKS)@(negedge clk);
                for(b=0;b<8;b=b+1)begin rx=message[c*8+b];repeat(BIT_TICKS)@(negedge clk);end
                rx=1;repeat(BIT_TICKS)@(negedge clk);
            end
            wait(reply_count>next_reply);
            if(replies[next_reply]!=={"OK",8'd13,8'd10})
                $fatal(1,"Command '%0s': '%0s'",message,replies[next_reply]);
            next_reply=next_reply+1;
        end
    endtask

    integer cycle=0,frame_count=0,complete_frames=0,frame_start=0,frame_length=0,offset=0;
    integer touch_used=0,pitch_used=0,fx_used=0,sensor_used=0;
    integer union_used=0,sum_used=0,overlap_used=0;
    integer max_touch=0,max_pitch=0,max_fx=0,max_sensor=0,max_union=0,max_sum=0,max_overlap=0;
    integer touch_done=-1,pitch_done=-1,fx_done=-1;
    integer max_touch_latency=0,max_pitch_latency=0,max_fx_latency=0;
    integer fx_done_count=0,overflow_frames=0,clip_frames=0,stress_frames=0,stress_onsets=0;
    integer four_bend_frames=0,transition_count=0,k,csv;
    integer touch_divides=0,max_touch_divides=0;
    reg armed=0,touch_busy,pitch_busy,fx_busy,sensor_busy,stress=0;
    reg [15:0] gates_at_start=0;
    reg [2:0] effect_at_start=0;
    reg score_at_start=0;

    task close_frame;
        begin
            if(frame_length!=1024)$fatal(1,"Frame length %0d",frame_length);
            complete_frames=complete_frames+1;
            if(touch_done<0 || pitch_done<0 || fx_done_count!=1)
                $fatal(1,"Missed deadline touch=%0d pitch=%0d fx_results=%0d",touch_done,pitch_done,fx_done_count);
            if(touch_used>1024 || pitch_used>1024 || fx_used>1024 || sensor_used>1024)
                overflow_frames=overflow_frames+1;
            if(touch_used>max_touch)max_touch=touch_used;
            if(pitch_used>max_pitch)max_pitch=pitch_used;
            if(fx_used>max_fx)max_fx=fx_used;
            if(sensor_used>max_sensor)max_sensor=sensor_used;
            if(union_used>max_union)max_union=union_used;
            if(sum_used>max_sum)max_sum=sum_used;
            if(overlap_used>max_overlap)max_overlap=overlap_used;
            if(touch_divides>max_touch_divides)max_touch_divides=touch_divides;
            if(touch_done+1>max_touch_latency)max_touch_latency=touch_done+1;
            if(pitch_done+1>max_pitch_latency)max_pitch_latency=pitch_done+1;
            if(fx_done+1>max_fx_latency)max_fx_latency=fx_done+1;
            if(stress)begin
                stress_frames=stress_frames+1;
                if(touch_divides==256)stress_onsets=stress_onsets+1;
            end
            $fdisplay(csv,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                frame_count,frame_length,touch_used,pitch_used,fx_used,sensor_used,
                sum_used,union_used,overlap_used,1024-fx_used,touch_done+1,pitch_done+1,fx_done+1,
                gates_at_start,effect_at_start,score_at_start,stress,touch_divides);
        end
    endtask

    // Busy counts INCLUDE the accepting edge at offset zero, and the edge
    // committing the result. All observations precede the RTL NBA updates.
    always @(posedge clk)begin
        cycle=cycle+1;
        if(dut.resetn && dut.u_touch_synth.state!=0 &&
            dut.u_fsr_pitch_scaler.individual.u_bend.state!=0 && dut.u_gesture.u_audio.u_synth.state!=0)begin
            if(dut.frame_ce)begin
                if(armed)begin frame_length=cycle-frame_start;close_frame;end
                armed=1;frame_start=cycle;frame_count=frame_count+1;
                touch_used=0;pitch_used=0;fx_used=0;sensor_used=0;
                union_used=0;sum_used=0;overlap_used=0;touch_divides=0;
                touch_done=-1;pitch_done=-1;fx_done=-1;fx_done_count=0;
                gates_at_start=dut.touch_note_gates;effect_at_start=dut.fx_applied_mask;
                score_at_start=dut.downloaded_playing;
                transition_count=0;
                for(k=0;k<7;k=k+1)
                    if(dut.u_fsr_pitch_scaler.individual.u_bend.targets[k] !==
                        dut.u_fsr_pitch_scaler.individual.u_bend.currents[k])transition_count=transition_count+1;
                stress=(gates_at_start==16'hffff && effect_at_start==7 && score_at_start && transition_count>=4);
                if(transition_count>=4)four_bend_frames=four_bend_frames+1;
                if(dut.u_touch_synth.state!=1 || dut.u_fsr_pitch_scaler.individual.u_bend.state!=1 || dut.u_effects.state!=0)
                    $fatal(1,"Engine still busy at frame boundary");
            end
            if(armed)begin
                offset=cycle-frame_start;
                touch_busy=(dut.u_touch_synth.state!=1) || dut.frame_ce;
                pitch_busy=(dut.u_fsr_pitch_scaler.individual.u_bend.state!=1) || dut.frame_ce;
                fx_busy=(dut.u_effects.state!=0) || dut.frame_ce;
                sensor_busy=dut.u_gesture.u_audio.u_synth.busy || dut.frame_ce;
                touch_used=touch_used+touch_busy;pitch_used=pitch_used+pitch_busy;
                fx_used=fx_used+fx_busy;sensor_used=sensor_used+sensor_busy;
                union_used=union_used+(touch_busy || pitch_busy || fx_busy);
                sum_used=sum_used+touch_busy+pitch_busy+fx_busy;
                overlap_used=overlap_used+((touch_busy+pitch_busy+fx_busy)>1);
                if(dut.u_touch_synth.state==4)touch_divides=touch_divides+1;
                if(dut.u_touch_synth.state==11 && dut.u_touch_synth.publish_part==2)touch_done=offset;
                if(dut.u_fsr_pitch_scaler.individual.u_bend.state==7 && dut.u_fsr_pitch_scaler.individual.u_bend.index==6)pitch_done=offset;
                if(dut.u_effects.state==dut.u_effects.R_MIX)begin fx_done=offset;fx_done_count=fx_done_count+1;end
                if(dut.u_touch_synth.overrun || dut.sensor_overrun || dut.u_effects.overrun)$fatal(1,"RTL overrun");
                if(dut.u_touch_synth.clipped || dut.u_output_mix.clipped)clip_frames=clip_frames+1;
            end
        end else armed=0; // Mode changes legitimately reinitialize the touch context RAM.
    end
    task frames;
        input integer count;
        integer stop_frame;
        begin stop_frame=frame_count+count;wait(frame_count>=stop_frame);@(negedge clk);end
    endtask

    integer replay_a=0,replay_b=0,kill_clears=0,replay_curved=0;
    localparam [63:0] EXPECTED_STEP=(64'd23012828*64'd20000)>>14;
    reg [11:0] expected_mix;
    reg kill_d=0;
    always @(posedge clk)kill_d<=dut.perf_kill;
    always @(negedge clk)if(dut.resetn && kill_d)begin
        if(dut.u_effects.cf!==0 || dut.u_effects.df!==0 || dut.u_effects.age!==0 || dut.u_effects.state!==0)$fatal(1,"Kill did not synchronously invalidate histories");
        kill_clears=kill_clears+1;
    end
    always @(posedge clk)if(dut.resetn && dut.frame_ce && dut.perf_replay)begin
        if(dut.perf_state[31:0]===EXPECTED_STEP[31:0])replay_curved=replay_curved+1;
        if(!dut.perf_state[511] || dut.fx_applied_mix!==expected_mix)$fatal(1,"TAKE version/mix mismatch");
        if(dut.fx_applied_mask==7 && dut.fx_applied_settings==8'h52)replay_a=replay_a+1;
        else if(dut.fx_applied_mask==5 && dut.fx_applied_settings==8'hef)replay_b=replay_b+1;
        else $fatal(1,"Torn/unrecorded FX state mask=%d settings=%h",dut.fx_applied_mask,dut.fx_applied_settings);
    end
    initial begin
        csv=$fopen("sim/build/score_bend_frame_take.csv","w");
        if(!csv)$fatal(1,"CSV open failed");
        $fdisplay(csv,"frame,period,touch,pitch,fx,sensor,sum,union,overlap,fx_idle,touch_latency,pitch_latency,fx_latency,gates,effect,score,stress,divide_cycles");
        wait(dut.touch_ready);frames(3);
        dut.u_fsr_adc.adc_inst.sim_value=14'd1200;
        command("PITCH,,,256\n",12);
        command("BEND,1,32768\n",13);command("BEND,2,32768\n",13);
        command("BEND,3,32768\n",13);command("BEND,4,32768\n",13);
        command("TOUCH,16\n",9);wait(dut.touch_ready);frames(4);
        command("ANALOG,1\n",9);wait(dut.analog_available);
        command("SONG_BEGIN,1\n",13);
        command("SONG_CHORD,0,21,1000,20000\n",27);
        command("SONG_END\n",9);command("PLAY\n",5);
        // Skip only the 60 ms visual pre-roll, as the long-score regression
        // does at event boundaries. All measured audio frames run normally.
        wait(dut.u_keymap.u_download.state==5);
        @(negedge clk);dut.u_keymap.u_download.elapsed_ms=60;
        wait(dut.downloaded_gate);
        command("EFFECT,3,7,239,2148\n",20);
        keys=16'hffff;wait(dut.touch_keys==16'hffff);frames(32);
        frames(32);
        frames(32);
        // Rearticulate all sixteen voices while four bends still slew.
        keys=0;wait(dut.touch_keys==0);frames(24);
        keys=16'hffff;wait(dut.touch_keys==16'hffff);frames(32);
        frames(16);
        if(stress_frames<30 || stress_onsets<2 || four_bend_frames<100 || max_touch_divides!=256)
            $fatal(1,"Missing worst-case coverage stress=%0d onsets=%0d bends=%0d divides=%0d",stress_frames,stress_onsets,four_bend_frames,max_touch_divides);
        if(overflow_frames || max_fx_latency!=49 || max_pitch_latency!=43 || max_overlap==0)
            $fatal(1,"Frame accounting failed");
        $display("FRAME_BUDGET frames=%0d touch=%0d pitch=%0d fx=%0d sensor=%0d sum=%0d union=%0d overlap=%0d fx_idle=%0d union_idle=%0d",
            complete_frames,max_touch,max_pitch,max_fx,max_sensor,max_sum,max_union,max_overlap,1024-max_fx,1024-max_union);
        $display("FRAME_DEADLINES touch_latency=%0d pitch_latency=%0d fx_latency=%0d stress_frames=%0d stress_onsets=%0d divide_cycles=%0d overflow_frames=%0d clipped_cycles=%0d",
            max_touch_latency,max_pitch_latency,max_fx_latency,stress_frames,stress_onsets,max_touch_divides,overflow_frames,clip_frames);
        $display("PASS frame budget: real UART/TTP229, 16 voices, four slewing bends, playing score, C+D+R and pressure/ADS1115, independent deadlines and overlap");
        keys=0;wait(dut.touch_keys==0);frames(24);
        command("STOP\n",5);frames(8);
        if(!dut.analog_available || dut.u_fsr_adc.adc_inst.conversions<2)$fatal(1,"Missing dual ADC activity");
        command("BEND_RESET\n",11);command("PITCH,,,65535\n",14);frames(64);
        command("ANALOG,4\n",9);frames(8);
        command("EFFECT,3,7,82,1092\n",19);
        frames(8);expected_mix=dut.fx_live_mix;
        command("TAKE_REC\n",9);frames(80);
        command("AUDITION\n",9);wait(dut.u_keymap.u_download.state==5);
        @(negedge clk);dut.u_keymap.u_download.elapsed_ms=60;
        wait(dut.downloaded_gate);frames(64);
        if(dut.touch_phase_increments[31:0]!==EXPECTED_STEP[31:0])$fatal(1,"Score target not applied through existing bend pipeline got=%d expected=%d",dut.touch_phase_increments[31:0],EXPECTED_STEP);
        if(dut.u_touch_synth.low_steps[31:0]!==EXPECTED_STEP[31:0])$fatal(1,"Audition pitch mismatch");
        keys=16'h0885;wait(dut.touch_keys==16'h0885);frames(40);
        command("EFFECT,3,5,239,582\n",19);frames(100);
        keys=0;wait(dut.touch_keys==0);frames(32);
        command("STOP\n",5);frames(64);command("TAKE_STOP\n",10);wait(!dut.perf_recording);frames(8);
        if(!dut.perf_available || dut.perf_full)$fatal(1,"TAKE not captured count=%0d",dut.perf_count);
        command("EFFECT,3,2,0,0\n",15);
        slider_code=0;wait(dut.fx_live_mix==0);frames(8);
        command("TAKE_PLAY\n",10);wait(dut.perf_playing);wait(!dut.perf_playing);frames(16);
        if(replay_curved<20)$fatal(1,"Missing recorded bent pitch replay frames=%d",replay_curved);
        if(replay_a<20 || replay_b<20)$fatal(1,"Missing replay snapshots A=%0d B=%0d",replay_a,replay_b);
        if(dut.touch_active || dut.audio_sample!==0 || dut.u_effects.rev_hold!==0 || dut.u_effects.delay_hold!==0 || kill_clears==0)$fatal(1,"TAKE end did not clear effect tails");
        $display("PASS FX3 actual UART/TTP/dual ADC/TAKE playback: states A=%0d B=%0d events=%0d, stored wet overrides changed live slider",replay_a,replay_b,dut.perf_count);
        $display("PASS score bend target, independent real frame deadlines, and applied bent increments replayed by unchanged TAKE: %0d frames",replay_curved);
        $fclose(csv);$finish;
    end
    initial begin #200000000;$fatal(1,"Frame budget timeout frame=%0d replies=%0d keys=%h",frame_count,reply_count,dut.touch_keys);end
endmodule
