`timescale 1ns/1ps
module tb_sensor_eight_timbres;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,ir=0;
    reg [9:0] divider=0;
    always @(posedge clk)divider<=divider+1'b1;
    wire ce=divider==0;
    reg [2:0] tone=0;
    wire signed [15:0] pcm;
    wire overrun;wire [31:0] active;
    integer frame=0,t,i,j,nonzero;
    reg [31:0] fingerprints[0:7];
    sensor_poly_audio #(.NOTE_FRAMES(64),.PIANO_FRAMES(64),.FLUTE_FRAMES(64),
        .UKULELE_FRAMES(64),.DRUM_FRAMES(64)) dut(.tuning_ratio(16'd16384),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),
        .clk(clk),.resetn(rst),.frame_ce(ce),.sensor_ready(1'b0),
        .gesture_valid(1'b0),.dir_evaluated(1'b0),.start_dir(3'd0),.end_dir(3'd0),
        .ir_note_valid(ir),.ir_note_index(3'd0),.control_timbre(tone),
        .control_vibrato(1'b0),.control_bank(1'b0),.test32(1'b0),
        .adsr_config({1'b1,16'd1,16'd1,16'd1,9'd256,24'hffffff,24'hffffff,24'hffffff}),
        .audio_sample(pcm),.voice_active(active),.voice_count(),.overrun(overrun));
    always @(negedge clk)if(ce)frame=frame+1;
    task frames;input integer n;integer finish;begin finish=frame+n;wait(frame>=finish);@(negedge clk);end endtask
    initial begin
        for(t=0;t<8;t=t+1)begin
            rst=0;frames(2);tone=t;rst=1;frames(3);
            @(negedge clk);ir=1;@(negedge clk);ir=0;frames(48);
            if(active==0)$fatal(1,"No allocated voice for tone %0d",t);
            fingerprints[t]=0;nonzero=0;
            for(i=0;i<48;i=i+1)begin
                frames(1);if(pcm!=0)nonzero=nonzero+1;
                fingerprints[t]=(fingerprints[t]<<5)^($signed(pcm)+i);
                if(overrun)$fatal(1,"Tone %0d frame/FIFO overrun",t);
            end
            if(nonzero<20)$fatal(1,"Tone %0d silent nonzero=%0d ctx=%h",t,nonzero,dut.u_synth.peek_context(0));
            for(j=0;j<t;j=j+1)if(fingerprints[t]===fingerprints[j])$fatal(1,"Tones %0d/%0d identical",t,j);
            frames(48);if(active || pcm)$fatal(1,"Tone %0d release",t);
        end
        $display("PASS eight sensor timbres: IR event path, eight distinct nonzero PCM waveforms, independent allocation, release silence, frame deadline");$finish;
    end
endmodule
