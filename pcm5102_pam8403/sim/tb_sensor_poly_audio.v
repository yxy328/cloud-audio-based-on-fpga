`timescale 1ns/1ps
module tb_sensor_poly_audio;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ready_sensor=0,gv=0,ir=0;
    reg [9:0] tick=0;
    always @(posedge clk) if(!resetn) tick<=0;else tick<=tick+1'b1;
    wire ce=tick==1023;
    wire [31:0] active;
    wire [5:0] count;
    wire signed [15:0] pcm;
    wire overrun;
    reg [2:0] tone=0,index=0;
    integer f=0;
    always @(negedge clk) if(ce) f=f+1;
    sensor_poly_audio #(.NOTE_FRAMES(400)) dut (.tuning_ratio(16'd16384),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),
        .clk(clk),.resetn(resetn),.frame_ce(ce),.sensor_ready(ready_sensor),
        .gesture_valid(gv),.dir_evaluated(1'b1),.start_dir(3'd1),.end_dir(3'd2),
        .ir_note_valid(ir),.ir_note_index(index),.control_timbre(tone),
        .control_vibrato(1'b0),.control_bank(1'b0),.test32(1'b0),.adsr_config(130'd0),
        .audio_sample(pcm),.voice_active(active),.voice_count(count),.overrun(overrun));
    task frames;
        input integer n;integer finish_frame;
        begin finish_frame=f+n;wait(f>=finish_frame);@(negedge clk);end
    endtask
    task pulse;
        begin @(negedge clk);ir=1;gv=1;@(negedge clk);ir=0;gv=0;end
    endtask
    task reset;
        begin resetn=0;repeat(4) @(negedge clk);resetn=1;repeat(80) @(negedge clk);end
    endtask
    initial begin
        reset;
        pulse;frames(80);
        if(count!=1 || pcm==0 || overrun) $fatal(1,"IR needs absent APDS or ignored not-ready gesture");
        ready_sensor=1;index=7;tone=1;pulse;
        // Incoming events latch tone at acceptance; later UI edits cannot retune them.
        tone=3;frames(45);
        if(count!=3 || overrun) $fatal(1,"Same-clock IR+gesture lost");
        if(((dut.u_synth.peek_context(1)>>271)&7)!=1 || ((dut.u_synth.peek_context(2)>>271)&7)!=1)
            $fatal(1,"Queued timbre did not latch");
        reset;
        force dut.ready=0;
        pulse;pulse;
        if(dut.queued!=4 || overrun) $fatal(1,"Four-entry producer staging capacity");
        pulse;
        if(!overrun || dut.queued!=4) $fatal(1,"Backpressure overflow not diagnosed");
        release dut.ready;
        frames(4);
        if(count!=4 || dut.queued!=0) $fatal(1,"Backpressured events lost or repeated");
        reset;frames(1);
        if(count || pcm || overrun) $fatal(1,"Reset did not clear queued events/diagnostics");
        $display("PASS sensor producer queue: IR audio without APDS, blocked gestures while not ready, same-clock events, latched tone, backpressure/capacity/overflow/reset");
        $finish;
    end
    initial begin #5000000;$fatal(1,"Sensor wrapper timeout");end
endmodule
