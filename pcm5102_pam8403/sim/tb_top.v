`timescale 1ns/1ps
// Production parameters and external pins only; also used with the PNR netlist.
module tb_top;
    reg clk=0;
    always #10 clk=~clk;
    reg key_s1=0,key_s2=0;
    wire bck,lrck,din,scl;
    top dut(.clk(clk),.key_s1(key_s1),.key_s2(key_s2),.touch_out(8'h00),.hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl(scl));
    // Electrical interface requirement, including reset/startup: never clock
    // or float the unused serial input while reading direct touch outputs.
    always @(negedge clk)
        if(scl!==1'b1) $fatal(1,"Direct touch SCL is not held HIGH");
    i2s_pcm_monitor monitor(.bck(bck),.lrck(lrck),.din(din));
    time key_time,latency;
    integer first,peak;
    real c4,e4,g4,c5;
    task check_silence;
        input integer from_sample;
        integer i;
        begin
            for(i=from_sample;i<monitor.pcm_count;i=i+1)
                if(monitor.pcm[i]!=0) $fatal(1,"Expected silence at PCM %0d",i);
        end
    endtask
    task check_sound;
        input integer duration_ns;
        integer start_sample,i,v;
        begin
            start_sample=monitor.pcm_count;peak=0;
            #(duration_ns);
            for(i=start_sample;i<monitor.pcm_count;i=i+1) begin
                v=monitor.pcm[i];if(v<0) v=-v;if(v>peak) peak=v;
            end
            if(peak<500) $fatal(1,"Missing playback/release: peak=%0d",peak);
        end
    endtask
    task amplitude;
        input real hz;
        input integer start_sample;
        output real result;
        integer i;
        real co,si,w,ws,angle;
        begin
            co=0;si=0;ws=0;
            for(i=0;i<2048;i=i+1) begin
                w=0.5-0.5*$cos(6.283185307179586*i/2047.0);
                angle=6.283185307179586*hz*i/48828.125;
                co=co+w*monitor.pcm[start_sample+i]*$cos(angle);
                si=si+w*monitor.pcm[start_sample+i]*$sin(angle);ws=ws+w;
            end
            result=2*$sqrt(co*co+si*si)/ws;
        end
    endtask
    initial begin
        #200007;
        key_s1=1;#30000;key_s1=0;#1600000;
        check_silence(0);
        key_time=$time;key_s1=1;
        wait(monitor.pcm_count>0 && monitor.last_pcm!=0);
        latency=$time-key_time;
        if(latency>1200000) $fatal(1,"Start-to-PCM exceeds 1.2ms");
`ifdef AUDIO_QUICK_SIM
        // Include the first melody after its ~40ms intro, with no parameter overrides.
        #45000000;
        key_s1=0;#1500000;
        key_s1=1;#1600000;check_sound(2000000);
        key_s1=0;#1400000;
        key_s2=1;#1400000;check_sound(5000000);
        key_s2=0;#1400000;
        key_s2=1;#1400000;check_sound(2000000);
        if(monitor.pair_count<3000) $fatal(1,"Insufficient quick I2S data");
        $display("PASS [top quick]: %0d stereo pairs, S1 latency=%0d ns; first melody, held S1, toggle stop/release, S2 start/restart, I2S format",monitor.pair_count,latency);
`else
        #130000000;
        first=monitor.pcm_count;wait(monitor.pcm_count>=first+2048);#1;
        amplitude(261.6255653005986,first,c4);amplitude(329.6275569128699,first,e4);
        amplitude(391.9954359817493,first,g4);amplitude(523.2511306011972,first,c5);
        if(c4<1100 || c4>1370 || e4<1100 || e4>1370 || g4<1100 || g4>1370 || c5<1100 || c5>1370)
            $fatal(1,"Missing melody/accompaniment: %f/%f/%f/%f",c4,e4,g4,c5);
        $display("PASS [four tones]: C4=%0.2f E4=%0.2f G4=%0.2f C5=%0.2f",c4,e4,g4,c5);
        // Releasing a latched S1 leaves playback running.
        key_s1=0;#1400000;check_sound(4000000);
        key_s1=1;#1400000;check_sound(10000000);
        #105000000;first=monitor.pcm_count;#3000000;check_silence(first);
        key_s1=0;#1400000;
        key_s2=1;#1400000;check_sound(15000000);
        key_s2=0;#1400000;key_s2=1;#1400000;check_sound(45000000);
        key_s1=1;#1400000;check_sound(10000000);
        #105000000;first=monitor.pcm_count;#3000000;check_silence(first);
        if(monitor.pair_count<20000) $fatal(1,"Insufficient default I2S coverage");
        $display("PASS [top]: %0d stereo pairs, S1 latency=%0d ns; production four-tone spectrum, bounce rejection, latched S1, stop-to-silence, held controls, idle/active S2 restart, I2S format",monitor.pair_count,latency);
`endif
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #1000000000;$fatal(1,"Top test timeout");end
endmodule
