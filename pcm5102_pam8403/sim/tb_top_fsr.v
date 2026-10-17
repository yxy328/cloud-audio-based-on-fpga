`timescale 1ns/1ps
// Real fabric/ADC/I2S timing; shortened touch/ADSR only. The ADC model accepts
// analog voltage codes; its conversion handshake is processed by real RTL.
module tb_top_fsr;
    reg clk=0;always #10 clk=~clk;
    reg [7:0] pads=0;
    reg s1=0;
    wire bck,lrck,din;
    top #(.ENABLE_DEMO_SCORE(1),.KEY_CONFIRM_CYCLES(1000),.TOUCH_STARTUP_US(3000),
        .TOUCH_DEBOUNCE_MS(2),.TOUCH_MODE_DEBOUNCE_MS(2),
        .TOUCH_ADSR_RELEASE_SAMPLES(32),.ADSR_ATTACK_SAMPLES(4),
        .ADSR_DECAY_SAMPLES(4),.ADSR_RELEASE_SAMPLES(32)) dut(
        .clk(clk),.key_s1(s1),.key_s2(1'b0),.ir_beam(8'hff),.touch_out(pads),
        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl());
    i2s_pcm_monitor #(.PCM_MIN(-24576),.PCM_MAX(24564)) monitor(.bck(bck),.lrck(lrck),.din(din));
    integer first,k;
    real light_amp,medium_amp,heavy_amp,returned_amp;
    task measure_c4;
        output real result;
        integer start_sample,n;
        real co,si,w,ws,angle;
        begin
            start_sample=monitor.pcm_count;
            wait(monitor.pcm_count>=start_sample+2048);#1;
            co=0;si=0;ws=0;
            for(n=0;n<2048;n=n+1) begin
                w=0.5-0.5*$cos(6.283185307179586*n/2047.0);
                angle=6.283185307179586*261.6255653005986*n/48828.125;
                co=co+w*monitor.pcm[start_sample+n]*$cos(angle);
                si=si+w*monitor.pcm[start_sample+n]*$sin(angle);ws=ws+w;
            end
            result=2*$sqrt(co*co+si*si)/ws;
        end
    endtask
    task settle_pressure;
        input [9:0] value;
        begin
            dut.u_fsr_adc.adc_inst.sim_value={3'd0,value,1'b0};#25000000;
            if(dut.fsr_adc_sample!==value || dut.fsr_gain!==dut.fsr_target_gain)
                $fatal(1,"Pressure sample/slew did not settle");
        end
    endtask
    always @(negedge clk) begin
        if(dut.resetn && (dut.u_output_mix.clipped || dut.pressure_enabled.u_touch_mix.clipped))
            $fatal(1,"Default pressure mix clipped");
    end
    initial begin
        #7000000;
        if(!dut.u_touch_input.ready || dut.fsr_gain!==65535) $fatal(1,"FSR startup/full gain failed");
        settle_pressure(1023);
        for(k=0;k<monitor.pcm_count;k=k+1)
            if(monitor.pcm[k]!=0) $fatal(1,"Pressure alone triggered a note");
        settle_pressure(0);
        pads=1;wait(dut.touch_keys==1);#2000000;
        measure_c4(light_amp);
        settle_pressure(316);measure_c4(medium_amp);
        settle_pressure(1023);measure_c4(heavy_amp);
        settle_pressure(0);measure_c4(returned_amp);
        if(light_amp<1190 || light_amp>1260 || heavy_amp<295 || heavy_amp>320 ||
           medium_amp/light_amp<0.61 || medium_amp/light_amp>0.64 ||
           heavy_amp/light_amp<0.24 || heavy_amp/light_amp>0.26 ||
           $abs(returned_amp-light_amp)>3)
            $fatal(1,"I2S force amplitudes incorrect: %f/%f/%f/%f",light_amp,medium_amp,heavy_amp,returned_amp);
        $display("PASS [FSR C4 I2S]: light=%0.2f middle=%0.2f heavy=%0.2f released=%0.2f; note held throughout",light_amp,medium_amp,heavy_amp,returned_amp);
        pads=0;wait(dut.touch_keys==0);#2000000;
        first=monitor.pcm_count;settle_pressure(0);
        for(k=first;k<monitor.pcm_count;k=k+1)
            if(monitor.pcm[k]!=0) $fatal(1,"Pressure alone/released note was not silent");
        pads=8'h7f;wait(dut.touch_keys==8'h7f);#2000000;
        s1=1;#100000;s1=0;#45000000;
        if(dut.touch_keys!==8'h7f || dut.voice_gates!==4'hf || !dut.u_control.playing)
            $fatal(1,"FSR maximum with all 11 voices failed");
        pads=0;wait(dut.touch_keys==0);#2000000;
        settle_pressure(0);
        if(!dut.u_control.playing || dut.touch_mix0!==0 || dut.song_sample===0)
            $fatal(1,"Song did not remain independent of released touch/pressure");
        $display("PASS [top FSR]: on-chip ADC model/capture to continuous I2S dynamics, light loud/heavy quiet, no pressure-only trigger, independent release, 11 voices/no clipping, song independence; %0d stereo pairs",monitor.pair_count);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #600000000;$fatal(1,"FSR top test timeout");end
endmodule
