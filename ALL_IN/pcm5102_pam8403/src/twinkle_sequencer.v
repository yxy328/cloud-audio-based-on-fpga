`timescale 1ns/1ps
// Hardware audition score: 42 live-generated notes, never recorded PCM.
// This preset score is a demo, not the competition's live performance input.
// All musical time advances ONLY on the same frame_ce as the synth engine.
module twinkle_sequencer #(
    parameter BEAT_SAMPLES = 19531, // ~400ms at Fs=48828.125
    parameter GAP_SAMPLES = 4883,  // ~100ms articulation
    parameter INTRO_SAMPLES = 1953,
    parameter TAIL_SAMPLES = 17100
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire toggle_play,
    input wire restart,
    output wire playing,
    output reg [5:0] note_index,
    output wire [3:0] gates,
    output wire [127:0] phase_increments
);
    localparam [2:0] IDLE=0, INTRO=1, NOTE=2, GAP=3, TAIL=4;
    localparam SHORT_TICKS = (BEAT_SAMPLES > GAP_SAMPLES) ? BEAT_SAMPLES-GAP_SAMPLES : 1;
    localparam LONG_TICKS = (2*BEAT_SAMPLES > GAP_SAMPLES) ? 2*BEAT_SAMPLES-GAP_SAMPLES : 1;
    localparam GAP_TICKS = (GAP_SAMPLES > 0) ? GAP_SAMPLES : 1;
    localparam INTRO_TICKS = (INTRO_SAMPLES > 0) ? INTRO_SAMPLES : 1;
    localparam TAIL_TICKS = (TAIL_SAMPLES > 0) ? TAIL_SAMPLES : 1;
    localparam MAX1 = (LONG_TICKS > GAP_TICKS) ? LONG_TICKS : GAP_TICKS;
    localparam MAX2 = (INTRO_TICKS > TAIL_TICKS) ? INTRO_TICKS : TAIL_TICKS;
    localparam MAX_TICKS = (MAX1 > MAX2) ? MAX1 : MAX2;
    localparam COUNT_WIDTH = (MAX_TICKS < 2) ? 1 : $clog2(MAX_TICKS);
    reg [2:0] state;
    reg [COUNT_WIDTH-1:0] ticks;
    wire long_note = note_index==6 || note_index==13 || note_index==20 ||
                     note_index==27 || note_index==34 || note_index==41;
    assign playing = state != IDLE;
    assign gates = (state==NOTE) ? 4'b1111 :
                   (state==INTRO || state==GAP) ? 4'b1110 : 4'b0000;

    function [31:0] melody_increment;
        input [5:0] index;
        begin
            case(index)
                0,1,13,28,29,41: melody_increment=32'd46025656; // C5
                2,3,6,14,15,21,22,30,31,34: melody_increment=32'd68960566; // G5
                4,5,32,33: melody_increment=32'd77405619; // A5
                7,8,16,17,23,24,35,36: melody_increment=32'd61436880; // F5
                9,10,18,19,25,26,37,38: melody_increment=32'd57988693; // E5
                11,12,20,27,39,40: melody_increment=32'd51662052; // D5
                default: melody_increment=32'd46025656;
            endcase
        end
    endfunction
    function [95:0] accompaniment;
        input [5:0] index;
        begin
            case(index)
                4,5,32,33: accompaniment={32'd38702809,32'd28994347,32'd23012828}; // C4 E4 A4
                6,34: accompaniment={32'd34480283,32'd25831026,32'd21721217}; // B3 D4 G4
                7,8,16,17,23,24,35,36:
                    accompaniment={32'd46025656,32'd38702809,32'd30718440}; // F4 A4 C5
                11,12,14,15,20,21,22,27,39,40:
                    accompaniment={32'd25831026,32'd21721217,32'd17240142}; // G3 B3 D4
                default: accompaniment={32'd34480283,32'd28994347,32'd23012828}; // C4 E4 G4
            endcase
        end
    endfunction
    assign phase_increments = {accompaniment(note_index),melody_increment(note_index)};

    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE;
            ticks<=0;
            note_index<=0;
        end else if(restart || (toggle_play && !playing)) begin
            state<=INTRO;
            ticks<=0;
            note_index<=0;
        end else if(toggle_play) begin
            state<=IDLE;
            ticks<=0;
            // Keep the current pitch while the envelopes release.
        end else if(sample_ce) begin
            case(state)
                INTRO: begin
                    if(ticks==INTRO_TICKS-1) begin state<=NOTE;ticks<=0;end
                    else ticks<=ticks+1'b1;
                end
                NOTE: begin
                    if((long_note && ticks==LONG_TICKS-1) ||
                       (!long_note && ticks==SHORT_TICKS-1)) begin state<=GAP;ticks<=0;end
                    else ticks<=ticks+1'b1;
                end
                GAP: begin
                    if(ticks==GAP_TICKS-1) begin
                        ticks<=0;
                        if(note_index==41) state<=TAIL;
                        else begin note_index<=note_index+1'b1;state<=NOTE;end
                    end else ticks<=ticks+1'b1;
                end
                TAIL: begin
                    if(ticks==TAIL_TICKS-1) begin state<=IDLE;ticks<=0;end
                    else ticks<=ticks+1'b1;
                end
                default: ticks<=0;
            endcase
        end
    end
endmodule
