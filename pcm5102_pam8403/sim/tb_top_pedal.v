`timescale 1ns/1ps
module tb_top_pedal;
`ifdef AUDIO_QUICK_SIM
    localparam TAIL_MS=80;
`else
    localparam TAIL_MS=1200;
`endif
    localparam BIT_TICKS=100, TAIL_SAMPLES=(50000*TAIL_MS+512)/1024, DAMPER_SAMPLES=488;
    reg clk=0;always #10 clk=~clk;
    reg rx=1;reg [15:0] keys=0;
    wire tx,bck,lrck,din,tscl,sdo;
    tri1 scl,sda;
    integer reply_count=0,expected_count=0,bit_index,frame=0,n,start_sample;
    integer tail_start,elapsed,work=0,max_work=0,first_stolen=-1;
    reg [255:0] replies[0:127];reg [255:0] incoming=0;reg [7:0] decoded;
    reg forbid_attack=0,track_steal=0;
    reg [31:0] phase_before;
    real early_amp,late_amp,co,si,angle;
    top #(.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.PEDAL_TAIL_MS(TAIL_MS),
        .TOUCH_SERIAL_HALF_CYCLES(50),.TOUCH_SERIAL_GAP_CYCLES(2500),.TOUCH_SERIAL_QUIET_CYCLES(100),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.FSR_ENABLE(0)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.touch_sdo(sdo),.touch_scl(tscl),
        .ir_beam(8'hff),.hc05_rx(rx),.hc05_tx(tx),.audio_rec_cts_n(1'b1),.flash_miso(1'b1),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.scl(scl),.sda(sda));
    // Accelerate pad scans without changing the 1024-clock audio deadline.
    ttp229_model #(.TIMEOUT_NS(40000)) chip(.rst_n(dut.resetn),.scl(tscl),.connected(1'b1),.dv(1'b0),.stuck_low(1'b0),.keys(keys),.sdo(sdo));
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767)) monitor(
        .bck(bck),.lrck(lrck),.din(din),.resetn(dut.resetn));
    always @(negedge clk)if(dut.resetn)begin
        if(dut.u_touch_synth.overrun || dut.u_touch_synth.clipped || dut.u_output_mix.clipped)
            $fatal(1,"Pedal deadline/clipping at frame %0d",frame);
        if(dut.frame_ce)begin frame=frame+1;work=0;end
        else if(dut.u_touch_synth.state!=0 && dut.u_touch_synth.state!=1)begin
            work=work+1;if(work>max_work)max_work=work;
        end
        if(forbid_attack && dut.u_touch_synth.contexts[2][2:0]==1)$fatal(1,"Pedal re-press retriggered attack");
        if(track_steal && first_stolen<0 && dut.u_touch_synth.state==10 && dut.u_touch_synth.field==0 && dut.u_touch_synth.stage==6)
            first_stolen=dut.u_touch_synth.index;
    end
    task frames;input integer count;integer finish;begin finish=frame+count;wait(frame>=finish);@(negedge clk);end endtask
    initial forever begin
        @(negedge tx);repeat(BIT_TICKS/2)@(posedge clk);
        if(tx!==0)$fatal(1,"UART start");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin repeat(BIT_TICKS)@(posedge clk);decoded[bit_index]=tx;end
        repeat(BIT_TICKS)@(posedge clk);if(tx!==1)$fatal(1,"UART stop");
        incoming={incoming[247:0],decoded};
        if(decoded==10)begin replies[reply_count]=incoming;reply_count=reply_count+1;incoming=0;end
    end
    task byte_out;input [7:0] value;integer b;begin
        @(negedge clk);rx=0;repeat(BIT_TICKS)@(negedge clk);
        for(b=0;b<8;b=b+1)begin rx=value[b];repeat(BIT_TICKS)@(negedge clk);end
        rx=1;repeat(BIT_TICKS)@(negedge clk);
    end endtask
    task transact;input [511:0] message;input integer length;input [255:0] expected;integer b;begin
        for(b=length-1;b>=0;b=b-1)byte_out(message[b*8+:8]);
        wait(reply_count>expected_count);
        if(replies[expected_count]!==expected)$fatal(1,"Reply '%0s': expected '%0s' got '%0s'",message,expected,replies[expected_count]);
        expected_count=expected_count+1;
    end endtask
    task press;input [15:0] mask;begin keys=mask;wait(dut.touch_keys==mask);frames(12);end endtask
    task amplitude;input real hz;output real value;begin
        start_sample=monitor.pcm_count;wait(monitor.pcm_count>=start_sample+512);co=0;si=0;
        for(n=0;n<512;n=n+1)begin
            angle=6.283185307179586*hz*n/48828.125;
            co=co+monitor.pcm[start_sample+n]*$cos(angle);si=si+monitor.pcm[start_sample+n]*$sin(angle);
        end
        value=2*$sqrt(co*co+si*si)/512;
    end endtask
    initial begin
        wait(dut.touch_ready);frames(2);
        transact("TOUCH,16\n",9,{"OK",8'd13,8'd10});wait(dut.touch_ready);frames(4);
        transact("HOLD,?\n",7,{"HOLD,0",8'd13,8'd10});
        transact("POLY,?\n",7,{"POLY,16",8'd13,8'd10});
        transact("CTRL?\n",6,{"CTRL,1,0,4,0,0,16,0",8'd13,8'd10});
        transact("CTRL2?\n",7,{"CTRL2,1,0,4,0,0,16,0,16,00",8'd13,8'd10});
        transact("HOLD,3\n",7,{"ERR,RANGE",8'd13,8'd10});
        transact("POLY,3\n",7,{"ERR,RANGE",8'd13,8'd10});
        transact("POLY,4\n",7,{"OK",8'd13,8'd10});
        transact("POLY,8\n",7,{"OK",8'd13,8'd10});
        transact("POLY,?\n",7,{"POLY,08",8'd13,8'd10});
        transact("POLY,16\n",8,{"OK",8'd13,8'd10});
        transact("HOLD,2\n",7,{"OK",8'd13,8'd10});press(1);
        keys=0;wait(dut.touch_keys==0);wait(dut.u_touch_synth.contexts[2][2:0]==5);tail_start=frame;
        frames(2);phase_before=dut.u_touch_synth.phases[31:0];frames(1);
        if(dut.u_touch_synth.phases[31:0]-phase_before!=dut.touch_phase_increments[31:0])$fatal(1,"Tail reset DDS phase");
        amplitude(261.625565,early_amp);
        elapsed=frame-tail_start;frames(TAIL_SAMPLES/2-elapsed);amplitude(261.625565,late_amp);
        if(early_amp<700 || late_amp>=early_amp/4 || late_amp<5)$fatal(1,"Finite tail amplitudes %f / %f",early_amp,late_amp);
        elapsed=frame-tail_start;frames(TAIL_SAMPLES-10-elapsed);
        if(!dut.touch_active[0])$fatal(1,"Tail ended before configured duration");
        frames(20);if(dut.touch_active || monitor.last_pcm)$fatal(1,"Tail did not reach exact silence");
        $display("PASS %0dms linked tail, phase continuity and I2S amplitude decay",TAIL_MS);
        press(3);press(2);
        if(dut.u_touch_synth.contexts[2][2:0]!=5)$fatal(1,"Missing pedal tail");
        transact("HOLD,0\n",7,{"OK",8'd13,8'd10});forbid_attack=1;
        transact("HOLD,2\n",7,{"OK",8'd13,8'd10});frames(DAMPER_SAMPLES+8);forbid_attack=0;
        if(dut.touch_active!=2 || dut.u_touch_synth.contexts[19]!=39321)$fatal(1,"Damper affected physically held note");
        amplitude(277.182631,early_amp);if(early_amp<1000)$fatal(1,"Held note missing after damper");
        keys=0;wait(dut.touch_keys==0);frames(3);
        transact("PANIC\n",6,{"OK",8'd13,8'd10});frames(8);
        if(dut.touch_hold || dut.touch_active || monitor.last_pcm)$fatal(1,"Panic left pedal state");
        transact("HOLD,2\n",7,{"OK",8'd13,8'd10});press(7);press(3);press(1);
        track_steal=1;transact("POLY,2\n",7,{"OK",8'd13,8'd10});frames(DAMPER_SAMPLES+30);track_steal=0;
        if(first_stolen!=2 || dut.touch_active!=3 || dut.touch_voice_count!=2)
            $fatal(1,"Oldest tail victim=%0d active=%h count=%0d",first_stolen,dut.touch_active,dut.touch_voice_count);
        transact("POLY,?\n",7,{"POLY,02",8'd13,8'd10});
        transact("HOLD,?\n",7,{"HOLD,2",8'd13,8'd10});
        transact("CTRL?\n",6,{"CTRL,1,0,4,1,0,16,0",8'd13,8'd10});
        transact("CTRL2?\n",7,{"CTRL2,1,0,4,2,0,16,0,02,02",8'd13,8'd10});
        press(7);transact("POLY,1\n",7,{"OK",8'd13,8'd10});frames(DAMPER_SAMPLES+20);
        if(dut.touch_active!=7 || dut.touch_voice_count!=3)$fatal(1,"POLY stole physically held key");
        transact("TOUCH,8\n",8,{"ERR,BUSY",8'd13,8'd10});
        transact("SERIAL,1\n",9,{"ERR,BUSY",8'd13,8'd10});
        transact("REC_START\n",10,{"ERR,BUSY",8'd13,8'd10});
        keys=0;wait(dut.touch_keys==0);frames(4);
        transact("PANIC\n",6,{"OK",8'd13,8'd10});frames(8);
        transact("POLY,16\n",8,{"OK",8'd13,8'd10});
        transact("HOLD,2\n",7,{"OK",8'd13,8'd10});press(16'hffff);frames(96);
        if(dut.touch_voice_count!=16 || dut.touch_active!=16'hffff)$fatal(1,"Sixteen-key attack lost voices");
        if(max_work<1000 || max_work>=1024)$fatal(1,"Worst frame not exercised: %0d clocks",max_work);
        transact("CTRL2?\n",7,{"CTRL2,1,0,4,2,0,16,0,16,16",8'd13,8'd10});
        transact("PANIC\n",6,{"OK",8'd13,8'd10});frames(16);
        if(dut.touch_active || monitor.last_pcm)$fatal(1,"Panic retriggered blocked physical keys");
        keys=0;wait(dut.touch_keys==0);frames(4);
        transact("HOLD,2\n",7,{"OK",8'd13,8'd10});press(1);press(0);
        force dut.perf_kill=1;repeat(3)@(negedge clk);release dut.perf_kill;frames(8);
        if(dut.touch_hold || dut.touch_active)$fatal(1,"perf_kill left pedal tails");
        transact("HOLD,2\n",7,{"OK",8'd13,8'd10});press(1);press(0);
        force dut.touch_mode16=0;repeat(3)@(negedge clk);release dut.touch_mode16;frames(8);
        if(dut.touch_hold || dut.touch_active)$fatal(1,"Mode transition left pedal tails");
        $display("PASS pedal: UART, damper/re-press, oldest stealing, physical priority, 16 voices unclipped, clears; max work=%0d",max_work);$finish;
    end
    initial begin #2300000000;$fatal(1,"Pedal timeout frame=%0d replies=%0d",frame,reply_count);end
endmodule
