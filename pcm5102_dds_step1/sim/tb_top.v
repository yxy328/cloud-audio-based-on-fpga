`timescale 1ns/1ps
// End-to-end test reads only exported I2S pins, at production debounce/gain.
module tb_top;
    reg clk=0;
    always #10 clk=~clk;
    reg key_s1=0, key_s2=0;
    wire i2s_bck, i2s_lrck, i2s_din;
    top dut(.clk(clk),.key_s1(key_s1),.key_s2(key_s2),
            .i2s_bck(i2s_bck),.i2s_lrck(i2s_lrck),.i2s_din(i2s_din));
    reg started=0, last_lrck=1;
    integer slot_bit=0, word=0, left_word=0;
    integer pcm[0:8191];
    integer pcm_count=0, pair_count=0, checks=0, capture_file;
    integer last_pcm=0;
    integer i, first_count;
    time last_bck_rise=0, last_bck_fall=0, last_frame=0;
    time key_time, observed_latency;
    always @(negedge i2s_bck) last_bck_fall=$time;
    always @(i2s_din or i2s_lrck) begin
        if ($time > 2000) begin
            #1;
            if (i2s_bck !== 1'b0 || ($time - 1) != last_bck_fall)
                $fatal(1,"DIN/LRCK changed away from BCK falling edge");
        end
    end
    always @(negedge i2s_lrck) begin
        if (last_frame != 0 && ($time - last_frame) != 20480)
            $fatal(1,"Incorrect LRCK period");
        last_frame=$time;
    end
    always @(posedge i2s_bck) begin
        if (last_bck_rise != 0 && ($time-last_bck_rise) != 320)
            $fatal(1,"Incorrect BCK period");
        last_bck_rise=$time;
        #1;
        if ((^{i2s_lrck,i2s_din}) === 1'bx) $fatal(1,"Unknown I2S output");
        if (!started && !i2s_lrck) begin
            started=1; last_lrck=0; slot_bit=0; word=0;
        end else if (started) begin
            if (i2s_lrck != last_lrck) begin
                if (slot_bit != 31) $fatal(1,"Slot length is not 32 bits");
                last_lrck=i2s_lrck; slot_bit=0; word=0;
            end else slot_bit=slot_bit+1;
        end
        if (started) begin
            if (slot_bit == 0 || slot_bit >= 17) begin
                if (i2s_din !== 1'b0) $fatal(1,"I2S delay/padding not zero");
            end else begin
                word = ((word << 1) | i2s_din) & 16'hffff;
                if (slot_bit == 16) begin
                    if (word >= 32768) word=word-65536;
                    if (word < -2048 || word > 2047) $fatal(1,"Gain/sign overflow");
                    if (!i2s_lrck) begin
                        left_word=word;
                        pcm[pcm_count]=word;
                        last_pcm=word;
                        $fdisplay(capture_file,"%0d,%0d",$time,word);
                        pcm_count=pcm_count+1;
                    end else begin
                        if (word != left_word) $fatal(1,"Stereo frame channels differ");
                        pair_count=pair_count+1;
                    end
                end
            end
        end
    end
    task require_silence;
        input integer from_sample;
        integer k;
        begin
            for (k=from_sample;k<pcm_count;k=k+1)
                if (pcm[k] != 0) $fatal(1,"Expected silence, got PCM %0d",pcm[k]);
        end
    endtask
    task measure_tone;
        input real target_hz;
        integer k, start_sample, crossings, min_value, max_value;
        real first_crossing, last_crossing, crossing, hz;
        begin
            start_sample=pcm_count;
            #10000000;
            crossings=0; min_value=0; max_value=0;
            first_crossing=0; last_crossing=0;
            for (k=start_sample+1;k<pcm_count;k=k+1) begin
                if (pcm[k]<min_value) min_value=pcm[k];
                if (pcm[k]>max_value) max_value=pcm[k];
                if (pcm[k-1]<=0 && pcm[k]>0) begin
                    crossing=(k-1)+(-1.0*pcm[k-1])/(pcm[k]-pcm[k-1]);
                    if (crossings==0) first_crossing=crossing;
                    last_crossing=crossing;
                    crossings=crossings+1;
                end
            end
            if (crossings<3 || min_value > -1800 || max_value < 1800)
                $fatal(1,"Missing sustained tone/amplitude");
            hz=48828.125*(crossings-1)/(last_crossing-first_crossing);
            if (hz < target_hz-0.5 || hz > target_hz+0.5)
                $fatal(1,"Pitch mismatch: expected %f Hz decoded %f Hz",target_hz,hz);
            checks=checks+1;
            $display("PASS [I2S pitch]: expected=%0.6fHz decoded=%0.6fHz crossings=%0d",target_hz,hz,crossings);
        end
    endtask
    task next_note;
        begin
            key_s2=0;
            #1300137;
            key_s2=1;
            #1300193;
        end
    endtask
    initial begin
        capture_file=$fopen("sim/build/decoded_pcm.csv","w");
        if (!capture_file) $fatal(1,"Cannot open PCM capture");
        $fdisplay(capture_file,"time_ns,pcm");
        #200007;
        // S1 glitches shorter than confirmation must stay silent.
        key_s1=1; #30000; key_s1=0; #1600000;
        require_silence(0);
        key_time=$time; key_s1=1;
        wait(pcm_count>0 && last_pcm != 0);
        observed_latency=$time-key_time;
        if (observed_latency > 1100000)
            $fatal(1,"Gate-to-PCM latency >1.1ms: %0t",observed_latency);
        $display("PASS [latency]: S1 input to first decoded nonzero PCM=%0d ns",observed_latency);
        #200000;
        measure_tone(440.0);
        // Bounce on S2 must not change pitch.
        key_s2=1; #30000; key_s2=0; #40000;
        key_s2=1; #500000; key_s2=0; #1300000;
        measure_tone(440.0);
        next_note; measure_tone(523.2511306011972);
        // The entire measurement held S2: this must be just one event.
        next_note; measure_tone(659.2551138257398);
        next_note; measure_tone(880.0);
        next_note; measure_tone(440.0);
        key_time=$time; key_s1=0;
        #1100000;
        first_count=pcm_count;
        #1600000;
        require_silence(first_count);
        // Changing pitch while muted cannot produce a note by itself.
        next_note;
        #1000000;
        require_silence(first_count);
        if (checks != 6 || pair_count<2000) $fatal(1,"Insufficient coverage");
        $fclose(capture_file);
        $display("PASS [top]: %0d stereo pairs; six pitch windows; production 1ms confirmation; gate mute; bounced/held S2; wrap-around; BCK/LRCK/DIN format",pair_count);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"Test timed out");
    end
endmodule
