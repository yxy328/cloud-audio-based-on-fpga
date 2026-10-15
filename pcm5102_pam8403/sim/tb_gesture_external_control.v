`timescale 1ns/1ps
module tb_gesture_external_control;
    reg clk=0, resetn=0, ready=0, valid=0, evaluated=1;
    reg s1=0, s2=0, control_vibrato=0, control_bank=0;
    reg [2:0] control_timbre=0, start_dir=1, end_dir=2;
    reg [4:0] divider=0;
    wire frame_ce=(divider==19);
    always #10 clk=~clk;
    always @(posedge clk) divider <= frame_ce ? 0 : divider+1'b1;
    wire signed [15:0] sample, legacy_sample;
    wire bank, vibrato_enabled;
    wire [2:0] timbre;
    gesture_audio #(
        .EXTERNAL_CONTROL(1), .SHARED_AUDIO_CLOCK(1),
        .NOTE_FRAMES(400), .PIANO_FRAMES(410), .FLUTE_FRAMES(420),
        .UKULELE_FRAMES(430), .DRUM_FRAMES(440),
        .KEY_DEBOUNCE_CYCLES(2), .LONG_PRESS_CYCLES(4)
    ) dut (
        .clk(clk), .resetn(resetn), .sensor_ready(ready),
        .gesture_valid(valid), .dir_evaluated(evaluated),
        .start_dir(start_dir), .end_dir(end_dir), .key_s1(s1), .key_s2(s2),
        .control_timbre(control_timbre), .control_vibrato(control_vibrato),
        .control_bank(control_bank), .shared_frame_ce(frame_ce),
        .note_bank(bank), .vibrato_enabled(vibrato_enabled),
        .timbre_selected(timbre), .audio_sample(sample)
    );
    // Default-control audio must remain bit-identical to the imported voice.
    gesture_audio #(
        .SHARED_AUDIO_CLOCK(1), .NOTE_FRAMES(400),
        .KEY_DEBOUNCE_CYCLES(2), .LONG_PRESS_CYCLES(4)
    ) legacy (
        .clk(clk), .resetn(resetn), .sensor_ready(ready),
        .gesture_valid(valid), .dir_evaluated(evaluated),
        .start_dir(start_dir), .end_dir(end_dir), .key_s1(1'b0), .key_s2(1'b0),
        .control_timbre(3'bzzz), .control_vibrato(1'bz), .control_bank(1'bz),
        .shared_frame_ce(frame_ce), .audio_sample(legacy_sample)
    );
    task frames;
        input integer count;
        integer i;
        begin
            for (i=0; i<count; i=i+1) begin
                @(posedge clk); while (!frame_ce) @(posedge clk);
                @(negedge clk);
            end
        end
    endtask
    task event_note;
        input [31:0] expected_inc;
        input [16:0] expected_frames;
        begin
            @(negedge clk); valid=1;
            @(negedge clk); valid=0;
            if (dut.note_inc !== expected_inc || dut.remaining !== expected_frames ||
                dut.note_timbre !== control_timbre)
                $fatal(1,"External gesture pitch/timbre/duration mismatch");
        end
    endtask
    integer i, j, nonzero;
    reg compare_defaults=1;
    always @(negedge clk) begin
        if (resetn && compare_defaults && sample !== legacy_sample)
            $fatal(1,"Default external controls changed PCM");
    end
    initial begin
        repeat (4) @(negedge clk); resetn=1; ready=1;
        event_note(32'd23012828,400);
        frames(80);
        // Button activity must not override externally supplied state.
        s1=1; s2=1; frames(10); s1=0; s2=0; frames(10);
        if (bank || vibrato_enabled || timbre !== 0)
            $fatal(1,"Physical buttons changed external control state");
        compare_defaults=0;
        control_bank=1; control_timbre=3;
        #1;
        if (!bank || timbre !== 3 || dut.note_inc !== 32'd23012828 || dut.note_timbre !== 0)
            $fatal(1,"External controls retuned/revoiced the already sounding note");
        event_note(32'd34480283,430);
        control_vibrato=1; frames(260);
        if (!vibrato_enabled || dut.u_vibrato.depth !== 256)
            $fatal(1,"External vibrato did not ramp on");
        control_vibrato=0; frames(260);
        if (dut.u_vibrato.depth !== 0) $fatal(1,"External vibrato did not ramp off");
        // All five imported instruments remain audible with external selection.
        control_bank=0;
        for (i=0; i<5; i=i+1) begin
            control_timbre=i;
            event_note(32'd23012828,400+i*10);
            nonzero=0;
            for (j=0; j<300; j=j+1) begin
                frames(1); if (sample != 0) nonzero=nonzero+1;
            end
            if (nonzero < 30) $fatal(1,"External timbre %0d is silent",i);
        end
        frames(800);
        if (sample !== 0 || dut.gain !== 0 || dut.remaining !== 0)
            $fatal(1,"External gesture audio failed to return to silence");
        $display("PASS: external gesture control, unchanged default PCM, ignored buttons, latched bank/timbre, five voices, vibrato and final silence");
        $finish;
    end
    initial begin #2000000; $fatal(1,"External gesture control timeout"); end
endmodule
