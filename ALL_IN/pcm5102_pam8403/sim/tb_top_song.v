`timescale 1ns/1ps
// Full top/I2S path and all 42 events, with short musical/ADSR durations.
// 50MHz and external BCK/LRCK periods remain the production values.
module tb_top_song;
    reg clk=0;
    always #10 clk=~clk;
    reg s1=0;
    wire bck,lrck,din;
    top #(.KEY_CONFIRM_CYCLES(1000), .ADSR_ATTACK_SAMPLES(8),
        .ADSR_DECAY_SAMPLES(32), .ADSR_RELEASE_SAMPLES(64),
        .SONG_BEAT_SAMPLES(256), .SONG_GAP_SAMPLES(64),
        .SONG_INTRO_SAMPLES(32), .SONG_TAIL_SAMPLES(256)) dut(
        .clk(clk),.key_s1(s1),.key_s2(1'b0),.touch_out(8'h00),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din));
    i2s_pcm_monitor monitor(.bck(bck),.lrck(lrck),.din(din));
    integer events=0,k,nonzero=0;
    reg lead_previous=0;
    always @(posedge clk) begin
        #2;
        if(dut.voice_gates[0] && !lead_previous) begin
            if(dut.u_control.note_index!=events) $fatal(1,"Lost/reordered note at top interface");
            events=events+1;
        end
        lead_previous=dut.voice_gates[0];
    end
    initial begin
        #100000;s1=1;#100000;s1=0;
        wait(dut.u_control.playing);wait(!dut.u_control.playing);
        #3000000;
        if(events!=42 || monitor.pair_count<12000) $fatal(1,"Missing whole score at I2S top");
        for(k=0;k<monitor.pcm_count;k=k+1) if(monitor.pcm[k]!=0) nonzero=nonzero+1;
        for(k=monitor.pcm_count-100;k<monitor.pcm_count;k=k+1)
            if(monitor.pcm[k]!=0) $fatal(1,"Song ended without final I2S silence");
        if(nonzero<10000) $fatal(1,"Full score failed to produce I2S PCM");
        $display("PASS [top full score, short durations]: %0d events, %0d stereo pairs, %0d nonzero left samples; automatic end and final silence",events,monitor.pair_count,nonzero);
        $fclose(monitor.capture_file);$finish;
    end
    initial begin #1000000000;$fatal(1,"Full-score top test timeout");end
endmodule
