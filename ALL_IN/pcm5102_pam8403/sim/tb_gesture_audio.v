`timescale 1ns/1ps
// Accelerated frame enable: checks event handling, not physical I2S timing.
module tb_gesture_audio;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, ready=0, valid=0, evaluated=0, s1=0, s2=0;
    reg [2:0] start_dir=0, end_dir=0;
    reg [4:0] divider=0;
    wire frame_ce=(divider==19);
    always @(posedge clk) divider <= frame_ce ? 0 : divider+1'b1;
    wire signed [15:0] sample;
    wire bank, vibrato_enabled;
    wire [2:0] timbre;
    gesture_audio #(.SHARED_AUDIO_CLOCK(1),.NOTE_FRAMES(32), .KEY_DEBOUNCE_CYCLES(4),
                    .LONG_PRESS_CYCLES(30)) dut (
        .clk(clk), .resetn(resetn), .sensor_ready(ready),
        .gesture_valid(valid), .dir_evaluated(evaluated),
        .start_dir(start_dir), .end_dir(end_dir), .key_s1(s1), .key_s2(s2),
        .note_bank(bank), .vibrato_enabled(vibrato_enabled),
        .timbre_selected(timbre), .shared_frame_ce(frame_ce), .audio_sample(sample)
    );
    task event_note;
        input [2:0] origin, destination;
        input [31:0] expected;
        begin
            @(negedge clk); start_dir=origin; end_dir=destination; valid=1;
            @(negedge clk); valid=0;
            if (dut.note_inc !== expected || dut.remaining !== 32)
                $fatal(1,"Gesture mapping/duration mismatch %0d -> %0d",origin,destination);
        end
    endtask
    reg [31:0] old_inc;
    initial begin
        #100; @(negedge clk); resetn=1;
        evaluated=1;
        start_dir=1; end_dir=2; valid=1;
        #100; valid=0;
        if (dut.remaining !== 0) $fatal(1,"Unready sensor triggered a note");
        ready=1;
        event_note(1,2,32'd23012828);
        event_note(3,4,32'd25831026);
        event_note(2,1,32'd28994347);
        event_note(4,3,32'd30718440);
        old_inc=dut.note_inc;
        @(negedge clk); start_dir=1; end_dir=1; valid=1;
        @(negedge clk); valid=0;
        if (dut.note_inc !== old_inc) $fatal(1,"Invalid direction changed pitch");
        evaluated=0; start_dir=1; end_dir=2;
        @(negedge clk); valid=1;
        @(negedge clk); valid=0;
        if (dut.note_inc !== old_inc) $fatal(1,"Raw FIFO update triggered note");
        evaluated=1; s1=1; #200;
        if (!bank || dut.note_inc !== old_inc) $fatal(1,"Bank change retuned held note");
        event_note(1,2,32'd34480283);
        event_note(3,4,32'd38702809);
        event_note(2,1,32'd43442435);
        event_note(4,3,32'd46025656);
        s2=1; #300; s2=0; #200;
        if (timbre !== 1 || vibrato_enabled) $fatal(1,"S2 short press failed");
        s2=1; #1200;
        if (!vibrato_enabled) $fatal(1,"S2 long hold failed");
        #1200;
        if (!vibrato_enabled) $fatal(1,"Long hold toggled repeatedly");
        s2=0; #200;
        if (timbre !== 1) $fatal(1,"Long release also changed timbre");
        #100000;
        if (dut.remaining !== 0 || dut.gain !== 0 || sample !== 0)
            $fatal(1,"Gesture voice did not return to silence");
        $display("PASS: eight gesture mappings, ready/direction guards, retrigger, latched pitch, S2 timbre/vibrato, final silence");
        $finish;
    end
    initial begin #200000; $fatal(1,"Gesture test timeout"); end
endmodule

