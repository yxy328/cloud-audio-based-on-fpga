`timescale 1ns/1ps
// IR and gesture events share 32 independent oscillator/envelope contexts.
// A two-producer queue preserves an IR and gesture event on the same clock.
module sensor_poly_audio #(
    parameter [16:0] NOTE_FRAMES=14648, PIANO_FRAMES=58594,
    FLUTE_FRAMES=24414, UKULELE_FRAMES=34180, DRUM_FRAMES=19531,
    parameter integer VOLUME_SHIFT=6, SHARED_ARITH=0
)(
    input wire clk, resetn, frame_ce, sensor_ready,
    input wire gesture_valid, dir_evaluated,
    input wire [2:0] start_dir, end_dir,
    input wire ir_note_valid,
    input wire [2:0] ir_note_index,
    input wire [2:0] control_timbre,
    input wire control_vibrato, control_bank, test32,
    input wire [31:0] vibrato_inc,
    input wire [9:0] vibrato_depth,
    input wire [15:0] vibrato_delay,
    input wire vibrato_update,
    input wire [15:0] tuning_ratio,
    input wire [129:0] adsr_config,
    output wire signed [15:0] audio_sample,
    output wire [31:0] voice_active,
    output wire [5:0] voice_count,
    output wire overrun,
    output wire shared_mul_request,shared_sine_request,
    output wire signed [32:0] shared_mul_a,
    output wire signed [17:0] shared_mul_b,
    output wire [31:0] shared_sine_phase,
    input wire signed [50:0] shared_product,
    input wire signed [15:0] shared_sine
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
    // A simultaneous IR/gesture pair shares one atomic ADSR/timbre snapshot.
    (* syn_ramstyle="block_ram" *) reg [132:0] configs[0:3];
    reg [1:0] config_wr;
    reg [1:0] config_tags[0:3];
    reg [31:0] pitches[0:3];
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
            wr<=0; rd<=0; config_wr<=0; queued<=0; queue_overrun<=0; test_pending<=0;
        end else begin
            if (send_test) test_pending<=0;
            if (test32) test_pending<=1;
            if ((ir_note_valid && !take_ir) || (gesture_event && !take_gesture) ||
                (test32 && test_pending && !send_test)) queue_overrun<=1;
            if(pushes!=0)begin
                config_wr<=config_wr+1'b1;
            end
            if(take_ir)begin pitches[wr]<=ir_inc;config_tags[wr]<=config_wr;end
            if(take_gesture)begin pitches[second_wr]<=gesture_inc;config_tags[second_wr]<=config_wr;end
            wr<=wr+pushes;
            if (pop) rd<=rd+1'b1;
            queued<=queued+pushes-pop;
        end
    end
    // Prefetch the following head, including tags written by either producer
    // on this edge. Explicit same-address forwarding preserves the original
    // queue's zero extra pop latency for simultaneous IR/gesture events.
    wire [1:0] prefetch_rd=pop ? rd+2'd1 : rd;
    wire [1:0] prefetch_tag=(take_ir && wr==prefetch_rd) ||
        (take_gesture && second_wr==prefetch_rd) ? config_wr : config_tags[prefetch_rd];
    wire config_collision=pushes!=0 && prefetch_tag==config_wr;
    reg [132:0] config_q,config_written;
    reg config_forward;
    always @(posedge clk)begin
        if(resetn && pushes!=0)begin
            configs[config_wr]<={adsr_config,control_timbre};
            config_written<={adsr_config,control_timbre};
        end
        if(!config_collision)config_q<=configs[prefetch_tag];
        config_forward<=config_collision;
    end
    wire [164:0] next_event={config_forward ? config_written : config_q,pitches[rd]};
    tdm_synth #(.VOICES(32),.EXTENDED_TIMBRES(1),.RUNTIME_ADSR(1),.VOLUME_SHIFT(VOLUME_SHIFT),.SHARED_ARITH(SHARED_ARITH),
        .PRESET_FRAMES(1),.NOTE_FRAMES(NOTE_FRAMES),.PIANO_FRAMES(PIANO_FRAMES),
        .FLUTE_FRAMES(FLUTE_FRAMES),.UKULELE_FRAMES(UKULELE_FRAMES),.DRUM_FRAMES(DRUM_FRAMES)) u_synth (
        .clk(clk),.resetn(resetn),.sample_ce(frame_ce),
        .event_valid(pop),.event_inc(next_event[31:0]),
        .event_adsr(next_event[164:35]),.event_timbre(next_event[34:32]),.event_frames(frames_for_timbre(next_event[34:32])),
        .chord_valid(1'b0),.test_valid(send_test),.vibrato_enabled(control_vibrato),
        .vibrato_inc(vibrato_inc),.vibrato_depth(vibrato_depth),.vibrato_delay(vibrato_delay),.vibrato_update(vibrato_update),.tuning_ratio(tuning_ratio),
        .voice_active(voice_active),.voice_count(voice_count),.sample(audio_sample),
        .event_ready(ready),.overrun(engine_overrun),.busy(),
        .shared_mul_request(shared_mul_request),.shared_sine_request(shared_sine_request),
        .shared_mul_a(shared_mul_a),.shared_mul_b(shared_mul_b),.shared_sine_phase(shared_sine_phase),
        .shared_product(shared_product),.shared_sine(shared_sine)
    );
    assign overrun=queue_overrun || engine_overrun;
endmodule
