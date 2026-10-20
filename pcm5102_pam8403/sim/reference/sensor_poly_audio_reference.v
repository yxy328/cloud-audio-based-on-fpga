`timescale 1ns/1ps
// IR and gesture events share 32 independent oscillator/envelope contexts.
// A two-producer queue preserves an IR and gesture event on the same clock.
module sensor_poly_audio_reference #(
    parameter [16:0] NOTE_FRAMES=14648, PIANO_FRAMES=58594,
    FLUTE_FRAMES=24414, UKULELE_FRAMES=34180, DRUM_FRAMES=19531,
    parameter integer VOLUME_SHIFT=6
)(
    input wire clk, resetn, frame_ce, sensor_ready,
    input wire gesture_valid, dir_evaluated,
    input wire [2:0] start_dir, end_dir,
    input wire ir_note_valid,
    input wire [2:0] ir_note_index,
    input wire [2:0] control_timbre,
    input wire control_vibrato, control_bank, test32,
    input wire [129:0] adsr_config,
    output wire signed [15:0] audio_sample,
    output wire [31:0] voice_active,
    output wire [5:0] voice_count,
    output wire overrun
);
    reg [31:0] gesture_inc, ir_inc;
    function [16:0] frames_for_timbre;
        input [2:0] timbre;
        begin case(timbre)
            1,5:frames_for_timbre=PIANO_FRAMES;
            2,7:frames_for_timbre=FLUTE_FRAMES;
            3,6:frames_for_timbre=UKULELE_FRAMES;
            4:frames_for_timbre=DRUM_FRAMES;
            default:frames_for_timbre=NOTE_FRAMES;
        endcase end
    endfunction
    always @(*) begin
        case ({start_dir,end_dir})
            {3'd1,3'd2}:gesture_inc=control_bank ? 34480283 : 23012828;
            {3'd3,3'd4}:gesture_inc=control_bank ? 38702809 : 25831026;
            {3'd2,3'd1}:gesture_inc=control_bank ? 43442435 : 28994347;
            {3'd4,3'd3}:gesture_inc=control_bank ? 46025656 : 30718440;
            default:gesture_inc=0;
        endcase
        case (ir_note_index)
            0:ir_inc=23012828; 1:ir_inc=25831026;
            2:ir_inc=28994347; 3:ir_inc=30718440;
            4:ir_inc=34480283; 5:ir_inc=38702809;
            6:ir_inc=43442435; 7:ir_inc=46025656;
        endcase
    end
    wire gesture_event=sensor_ready && gesture_valid && dir_evaluated && gesture_inc!=0;
    // Four staging entries plus 64 engine FIFO entries.
    reg [164:0] events [0:3];
    reg [1:0] wr,rd;
    reg [2:0] queued;
    reg queue_overrun,test_pending;
    wire ready,engine_overrun;
    wire send_test=test_pending && ready;
    wire pop=queued!=0 && ready && !test_pending;
    wire [3:0] free_slots=4'd4-{1'b0,queued}+pop;
    wire take_ir=ir_note_valid && free_slots!=0;
    wire take_gesture=gesture_event && free_slots>{3'd0,take_ir};
    wire [1:0] pushes={1'b0,take_ir}+{1'b0,take_gesture};
    wire [1:0] second_wr=wr+take_ir;
    always @(posedge clk) begin
        if (!resetn) begin
            wr<=0; rd<=0; queued<=0; queue_overrun<=0; test_pending<=0;
        end else begin
            if (send_test) test_pending<=0;
            if (test32) test_pending<=1;
            if ((ir_note_valid && !take_ir) || (gesture_event && !take_gesture) ||
                (test32 && test_pending && !send_test)) queue_overrun<=1;
            if (take_ir) events[wr]<={adsr_config,control_timbre,ir_inc};
            if (take_gesture) events[second_wr]<={adsr_config,control_timbre,gesture_inc};
            wr<=wr+pushes;
            if (pop) rd<=rd+1'b1;
            queued<=queued+pushes-pop;
        end
    end
    wire [164:0] next_event=events[rd];
    tdm_synth #(.VOICES(32),.EXTENDED_TIMBRES(1),.RUNTIME_ADSR(1),.VOLUME_SHIFT(VOLUME_SHIFT),
        .PRESET_FRAMES(1),.NOTE_FRAMES(NOTE_FRAMES),.PIANO_FRAMES(PIANO_FRAMES),
        .FLUTE_FRAMES(FLUTE_FRAMES),.UKULELE_FRAMES(UKULELE_FRAMES),.DRUM_FRAMES(DRUM_FRAMES)) u_synth (
        .clk(clk),.resetn(resetn),.sample_ce(frame_ce),
        .event_valid(pop),.event_inc(next_event[31:0]),
        .event_adsr(next_event[164:35]),.event_timbre(next_event[34:32]),.event_frames(frames_for_timbre(next_event[34:32])),
        .chord_valid(1'b0),.test_valid(send_test),.vibrato_enabled(control_vibrato),
        .voice_active(voice_active),.voice_count(voice_count),.sample(audio_sample),
        .event_ready(ready),.overrun(engine_overrun),.busy()
    );
    assign overrun=queue_overrun || engine_overrun;
endmodule
