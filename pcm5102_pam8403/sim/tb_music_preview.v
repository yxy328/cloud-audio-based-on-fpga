`timescale 1ns/1ps
// Shares the PRODUCTION score and top-level parameters; only sample_ce is accelerated.
module tb_music_preview;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, start=0;
    reg [4:0] count=0;
    always @(posedge clk) begin
        if(!resetn || count==19) count<=0;
        else count<=count+1'b1;
    end
    wire sample_ce=count==19;
    // Unclocked parameter reference, not an audio source.
    top config_defaults(.clk(1'b0),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'h00),
                        
                        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(),.i2s_lrck(),.i2s_din());
    wire [3:0] gates, active;
    wire [127:0] increments;
    wire playing, clipped;
    wire [5:0] note_index;
    wire signed [15:0] pcm;
    twinkle_sequencer u_score(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),
              .toggle_play(start),.restart(1'b0),.playing(playing),
              .note_index(note_index),.gates(gates),.phase_increments(increments));
    poly_synth #(
        .VOLUME_SHIFT(4), .ATTACK_SAMPLES(98), .DECAY_SAMPLES(3906),
        .SUSTAIN_LEVEL(16'd39321), .RELEASE_SAMPLES(4883)
    ) u_music(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),.gates(gates),
              .phase_increments(increments),.sample(pcm),.voice_samples(),
              .envelope_gains(),.envelope_states(),.active(active),.clipped(clipped));
    reg [8*256-1:0] csv_path;
    integer capture_file,capture_arg,samples=0,note_events=0;
    reg lead_previous=0;
    always @(posedge clk) begin
        if(resetn && sample_ce) begin
            #1;
            if((^pcm)===1'bx || clipped || pcm< -8192 || pcm>8188)
                $fatal(1,"Invalid preview PCM/sign/headroom");
            $fdisplay(capture_file,"%0d,%0d",samples,pcm);
            samples=samples+1;
            if(gates[0] && !lead_previous) begin
                note_events=note_events+1;
                $display("Production score note %0d/42, phase_inc=%0d",note_events,increments[31:0]);
            end
            lead_previous=gates[0];
        end
    end
    initial begin
        // Verilog-2001 forbids hierarchical parameter expressions at elaboration.
        // Refuse to render if any constant differs from the actual production top.
        if(u_music.VOLUME_SHIFT!=config_defaults.VOLUME_SHIFT ||
           u_music.ATTACK_SAMPLES!=config_defaults.ADSR_ATTACK_SAMPLES ||
           u_music.DECAY_SAMPLES!=config_defaults.ADSR_DECAY_SAMPLES ||
           u_music.SUSTAIN_LEVEL!=config_defaults.ADSR_SUSTAIN_LEVEL ||
           u_music.RELEASE_SAMPLES!=config_defaults.ADSR_RELEASE_SAMPLES ||
           u_score.BEAT_SAMPLES!=config_defaults.SONG_BEAT_SAMPLES ||
           u_score.GAP_SAMPLES!=config_defaults.SONG_GAP_SAMPLES ||
           u_score.INTRO_SAMPLES!=config_defaults.SONG_INTRO_SAMPLES ||
           u_score.TAIL_SAMPLES!=config_defaults.SONG_TAIL_SAMPLES)
            $fatal(1,"Preview parameters differ from production top");
        csv_path="sim/build/music_preview_pcm.csv";
        capture_arg=$value$plusargs("music_csv=%s",csv_path);
        capture_file=$fopen(csv_path,"w");
        if(!capture_file) $fatal(1,"Cannot open preview PCM file");
        $fdisplay(capture_file,"sample_index,pcm");
        repeat(3) @(negedge clk);resetn=1;
        repeat(488) @(posedge sample_ce);
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        wait(playing);wait(!playing);
        repeat(488) @(posedge sample_ce);
        @(negedge clk);
        if(pcm!=0 || active!=0 || note_events!=42)
            $fatal(1,"Preview missing full score or final silence");
        $fclose(capture_file);
        $display("PASS [music preview]: %0d HDL samples; same production score/parameters; 42 melody events, three accompaniment voices, exact final silence",samples);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Preview simulation timeout");end
endmodule
