`timescale 1ns/1ps
// Two independent RAM banks: only a successful END changes the active bank.
// Commands: 1=BEGIN, 2=NOTE, 3=END, 4=PLAY, 5=STOP.
module downloadable_song #(
    parameter integer CLK_HZ=50_000_000
) (
    input wire clk, resetn,
    input wire request,
    input wire [2:0] operation,
    input wire [15:0] arg0, arg1, arg2,
    input wire edit_allowed,
    input wire [55:0] note_map,
    input wire toggle_play, restart,
    output reg done,
    // 0=OK, 1=BUSY, 2=RANGE, 3=STATE, 4=MISSING, 5=MAP
    output reg [2:0] error,
    output reg valid,
    output reg playing,
    output wire gate,
    output reg [7:0] current_note,
    output reg [6:0] guide_keys
);
    localparam IDLE=0, CHECK_FETCH=1, CHECK_WAIT=2, CHECK=3,
        PLAY_FETCH=4, PLAY_WAIT=5, PLAY_LOAD=6, RUN=7;
    localparam integer MS_TICKS=(CLK_HZ/1000 < 1) ? 1 : CLK_HZ/1000;
    reg [3:0] state;
    reg [23:0] score [0:255]; // {MIDI, duration_ms}, synchronous read
    reg [23:0] fetched;
    reg active_bank, staging, check_play;
    reg [127:0] written;
    reg [7:0] staged_count, active_count, index;
    reg [55:0] checked_map;
    reg [31:0] ms_count;
    reg [15:0] remaining_ms;
    reg [6:0] note_matches;
    wire available=state==IDLE || state==RUN;
    integer k;
    always @* begin
        note_matches=0;
        for(k=0;k<7;k=k+1)
            if(checked_map[k*8 +: 8]==fetched[23:16]) note_matches[k]=1;
    end
    // One millisecond release before the next note retriggers repeated pitches.
    // A 1ms record remains audible for its full duration.
    assign gate=playing && state==RUN && (remaining_ms>1 || fetched[15:0]==1);
    always @(posedge clk) begin
        if(state==CHECK_FETCH || state==PLAY_FETCH)
            fetched<=score[{(state==CHECK_FETCH && !check_play) ? !active_bank : active_bank,index[6:0]}];
    end
    task finish;
        input [2:0] result;
        begin done<=1; error<=result; state<=IDLE; end
    endtask
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; active_bank<=0; staging<=0; written<=0;
            staged_count<=0; active_count<=0; index<=0; checked_map<=0;
            check_play<=0; done<=0; error<=0; valid<=0; playing<=0;
            current_note<=60; guide_keys<=0; ms_count<=0; remaining_ms<=0;
        end else begin
            done<=0;
            if(request && operation==5) begin
                playing<=0; guide_keys<=0; ms_count<=0; finish(0);
            end else if(request && operation==1) begin
                if(!available || !edit_allowed || playing) begin done<=1; error<=1; end
                else if(arg0==0 || arg0>128) begin done<=1; error<=2; end
                else begin
                    staging<=1; written<=0; staged_count<=arg0[7:0];
                    done<=1; error<=0;
                end
            end else if(request && operation==2) begin
                done<=1;
                if(!available || !edit_allowed || playing) error<=1;
                else if(!staging) error<=3;
                else if(arg0>=staged_count || arg1<60 || arg1>72 || arg2==0 || arg2>60000) error<=2;
                else begin
                    score[{!active_bank,arg0[6:0]}]<={arg1[7:0],arg2};
                    written[arg0[6:0]]<=1; error<=0;
                end
            end else if(request && operation==3) begin
                if(!available || !edit_allowed || playing) begin done<=1; error<=1; end
                else if(!staging) begin done<=1; error<=3; end
                else begin
                    index<=0; checked_map<=note_map; check_play<=0; state<=CHECK_FETCH;
                end
            end else if((request && operation==4) || (valid && (restart || toggle_play))) begin
                if(toggle_play && playing && !restart && !request) begin
                    playing<=0; guide_keys<=0; state<=IDLE;
                end else if(!valid) begin done<=request; error<=3; end
                else if(available) begin
                    playing<=0; guide_keys<=0; index<=0; checked_map<=note_map;
                    check_play<=1; state<=CHECK_FETCH;
                end else if(request) begin done<=1; error<=1; end
            end else if(request) begin done<=1; error<=2;
            end else begin
                case(state)
                    CHECK_FETCH: state<=CHECK_WAIT;
                    CHECK_WAIT: state<=CHECK;
                    CHECK: begin
                        if(!check_play && !written[index[6:0]]) finish(4);
                        else if(fetched[15:0]==0 || fetched[15:0]>60000) finish(2);
                        else if(note_matches==0) finish(5);
                        else if(index== (check_play ? active_count : staged_count)-1) begin
                            if(check_play) begin
                                index<=0; playing<=1; ms_count<=0; state<=PLAY_FETCH;
                                done<=1; error<=0;
                            end else begin
                                active_bank<=!active_bank; active_count<=staged_count;
                                valid<=1; staging<=0; finish(0);
                            end
                        end else begin index<=index+1'b1; state<=CHECK_FETCH; end
                    end
                    PLAY_FETCH: state<=PLAY_WAIT;
                    PLAY_WAIT: state<=PLAY_LOAD;
                    PLAY_LOAD: begin
                        current_note<=fetched[23:16]; remaining_ms<=fetched[15:0];
                        guide_keys<=note_matches; ms_count<=0; state<=RUN;
                    end
                    RUN: begin
                        if(ms_count==MS_TICKS-1) begin
                            ms_count<=0;
                            if(remaining_ms==1) begin
                                guide_keys<=0;
                                if(index==active_count-1) begin playing<=0; state<=IDLE; end
                                else begin index<=index+1'b1; state<=PLAY_FETCH; end
                            end else remaining_ms<=remaining_ms-1'b1;
                        end else ms_count<=ms_count+1'b1;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
