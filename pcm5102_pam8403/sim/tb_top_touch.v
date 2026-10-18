`timescale 1ns/1ps
// Real 50MHz/I2S periods; shortened startup, confirmation and ADSR only.
module tb_top_touch;
    reg clk=0;
    always #10 clk=~clk;
    reg [7:0] pads=8'hff;
    reg s1=0,s2=0;
    wire bck,lrck,din;
    top #(.ENABLE_DEMO_SCORE(1),
        .FSR_ENABLE(0),
        .KEY_CONFIRM_CYCLES(1000), .TOUCH_STARTUP_US(3000),
        .TOUCH_DEBOUNCE_MS(2), .TOUCH_MODE_DEBOUNCE_MS(2),
        .TOUCH_ADSR_RELEASE_SAMPLES(32), .ADSR_ATTACK_SAMPLES(4),
        .ADSR_DECAY_SAMPLES(4), .ADSR_RELEASE_SAMPLES(32)
    ) dut (
        .clk(clk), .key_s1(s1), .key_s2(s2), .ir_beam(8'hff),.touch_out(pads), 
        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck), .i2s_lrck(lrck), .i2s_din(din)
    );
    i2s_pcm_monitor #(.PCM_MIN(-24576), .PCM_MAX(24564)) monitor (
        .bck(bck), .lrck(lrck), .din(din)
    );
    integer k,i,first,peak;
    real hz[0:6];
    real amp;
    time press_time;
    task silence;
        input integer start_sample;
        integer n;
        begin
            for(n=start_sample;n<monitor.pcm_count;n=n+1)
                if(monitor.pcm[n]!=0) $fatal(1,"Touch idle/startup/bounce produced sound");
        end
    endtask
    task spectrum;
        input real frequency;
        input integer start_sample;
        output real result;
        integer n;
        real co,si,w,ws,angle;
        begin
            co=0;si=0;ws=0;
            // 8192 samples resolve the closest notes (E4/F4, ~19.6Hz apart).
            for(n=0;n<8192;n=n+1) begin
                w=0.5-0.5*$cos(6.283185307179586*n/8191.0);
                angle=6.283185307179586*frequency*n/48828.125;
                co=co+w*monitor.pcm[start_sample+n]*$cos(angle);
                si=si+w*monitor.pcm[start_sample+n]*$sin(angle);ws=ws+w;
            end
            result=2*$sqrt(co*co+si*si)/ws;
        end
    endtask
    always @(negedge clk) begin
        if(dut.resetn && dut.u_output_mix.clipped)
            $fatal(1,"Default 11-voice mix clipped");
    end
    initial begin
        hz[0]=261.6255653005986;hz[1]=293.6647679174076;
        hz[2]=329.6275569128699;hz[3]=349.2282314330039;
        hz[4]=391.9954359817493;hz[5]=440.0;
        hz[6]=493.8833012561241;
        #2900000;
        if(dut.u_touch_input.ready || dut.touch_keys!=0)
            $fatal(1,"Accepted startup-held keys before calibration wait");
        silence(0);
        @(negedge clk);pads=0;
        #4100000;
        if(!dut.u_touch_input.ready || dut.touch_keys!=0) $fatal(1,"Touch ready/idle failed");
        // Pulse shorter than even the accelerated two 1ms confirmation samples.
        pads=8'h81;#300000;pads=0;#3000000;
        if(dut.touch_keys!=0) $fatal(1,"Touch bounce accepted");
        silence(0);
        for(k=0;k<7;k=k+1) begin
            press_time=$time;first=monitor.pcm_count;
            @(negedge clk);pads=8'h01<<k;
            wait(dut.touch_keys==pads);
            wait(monitor.last_pcm!=0);
            if($time-press_time>2300000) $fatal(1,"Touch confirmation-to-PCM budget failed");
            #1000000;
            if(k<4) begin
                if(dut.touch_active[3:0]!==(4'b0001<<k) ||
                   dut.touch_active[7:4]!==0) $fatal(1,"Wrong independent low touch voice");
            end else begin
                if(dut.touch_active[7:4]!==(4'b0001<<(k-4)) ||
                   dut.touch_active[3:0]!==0) $fatal(1,"Wrong independent high touch voice");
            end
            // Each production note increment agrees with equal temperament.
            if($abs(dut.touch_base_increments[k*32 +: 32]-hz[k]*4294967296.0/48828.125)>0.51)
                $fatal(1,"Touch pitch mapping disagrees with equal temperament");
            pads=0;wait(dut.touch_keys==0);
            #1500000;first=monitor.pcm_count;#200000;silence(first);
        end
        pads=8'h7f;wait(dut.touch_keys==8'h7f);#1000000;
        first=monitor.pcm_count;wait(monitor.pcm_count>=first+8192);#1;
        for(k=0;k<7;k=k+1) begin
            spectrum(hz[k],first,amp);
            if(amp<1150 || amp>1320) $fatal(1,"Missing/incorrect touch tone %0d: %f",k+1,amp);
            $display("PASS [touch tone %0d]: %0.3f Hz, amplitude=%0.2f",k+1,hz[k],amp);
        end
        // Release C4 only; the other six notes must remain independently held.
        pads=8'h7e;wait(dut.touch_keys==8'h7e);#1500000;
        first=monitor.pcm_count;wait(monitor.pcm_count>=first+8192);#1;
        spectrum(hz[0],first,amp);
        if(amp>25) $fatal(1,"Released C4 did not fade independently: %f",amp);
        for(k=1;k<7;k=k+1) begin
            spectrum(hz[k],first,amp);
            if(amp<1150 || amp>1320) $fatal(1,"Releasing C4 changed another voice");
        end
        pads=8'h7f;wait(dut.touch_keys==8'h7f);#1000000;
        s1=1;#100000;s1=0;#45000000;
        if(!dut.u_control.playing || dut.voice_gates!=4'hf || dut.touch_keys!=8'h7f)
            $fatal(1,"Song and all seven touch voices failed to coexist");
        peak=0;
        for(i=monitor.pcm_count-1000;i<monitor.pcm_count;i=i+1) begin
            k=monitor.pcm[i];if(k<0) k=-k;if(k>peak) peak=k;
        end
        if(peak<5000) $fatal(1,"Combined song/touch output missing");
        s1=1;#100000;s1=0;#2000000;
        if(dut.u_control.playing || dut.touch_keys!=8'h7f || monitor.last_pcm==0)
            $fatal(1,"Stopping song stopped live touch notes");
        pads=0;wait(dut.touch_keys==0);#2000000;
        first=monitor.pcm_count;#1000000;silence(first);
        $display("PASS [top touch]: all 7 note keys, startup, bounce, release/retrigger, 7-tone I2S spectrum, independent note-off, 11-voice song coexistence, final silence; %0d stereo pairs",monitor.pair_count);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #500000000;$fatal(1,"Touch top test timeout");end
endmodule
