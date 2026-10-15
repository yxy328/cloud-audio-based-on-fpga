`timescale 1ns/1ps
// Atomic, double-buffered unsigned-byte transport of signed 8-bit mono PCM.
// PCM source: 8000 Hz. Output frames: 50 MHz / 1024 = 48828.125 Hz.
// BEGIN(count,sum16), DATA(address,byte,{...,last,first}), END, PLAY, STOP.
// DATA lines contain aligned blocks of 16 bytes; the final block may be short.
module pcm_clip_player #(
    // Power of two, 16..32768; bank addressing relies on this alignment.
    parameter integer MAX_SAMPLES = 32768
) (
    input wire clk, resetn,
    input wire sample_ce,
    input wire request,
    input wire [2:0] operation,
    input wire [15:0] arg0, arg1, arg2,
    input wire edit_allowed,
    input wire toggle_play, restart,
    output reg done,
    // 0=OK, 1=BUSY, 2=RANGE, 3=STATE, 4=MISSING, 5=CHECKSUM.
    output reg [2:0] error,
    output reg valid,
    output reg playing,
    output reg signed [15:0] sample
);
    localparam integer ADDRESS_BITS = $clog2(MAX_SAMPLES);
    localparam integer BLOCKS = MAX_SAMPLES / 16;
    localparam integer BLOCK_ADDRESS_BITS = (BLOCKS>1) ? $clog2(BLOCKS) : 1;
    localparam IDLE=0, CHECK_FETCH=1, CHECK_WAIT=2, CHECK_SUM=3,
        PLAY_FETCH=4, PLAY_WAIT=5, PLAY_LOAD=6, RUN=7, CLEAR_BLOCKS=8;
    reg [3:0] state;
    reg [7:0] pcm [0:2*MAX_SAMPLES-1];
    reg [7:0] ram_q;
    reg active_bank, staging, block_open;
    // One synchronous RAM port replaces a 2048-bit vector with dynamic writes.
    // BEGIN clears one bit per clock and acknowledges only after completion.
    reg block_written [0:BLOCKS-1];
    reg block_q;
    reg [BLOCK_ADDRESS_BITS-1:0] clear_index;
    reg [15:0] staged_count, active_count, expected_sum, checksum;
    reg [15:0] check_index, play_index, next_address;
    reg [25:0] phase;
    wire [26:0] phase_next = {1'b0,phase} + 27'd8192000;
    wire checking = state==CHECK_FETCH || state==CHECK_WAIT || state==CHECK_SUM;
    wire [ADDRESS_BITS:0] read_address = checking ?
        {!active_bank,check_index[ADDRESS_BITS-1:0]} :
        {active_bank,play_index[ADDRESS_BITS-1:0]};
    wire last_in_block = (arg0[3:0]==4'd15) || (arg0==staged_count-1'b1);
    wire data_sequence_ok = arg2[0] ? (arg0[3:0]==0) :
        (block_open && arg0==next_address);
    wire data_write = resetn && request && operation==2 && state==IDLE &&
        staging && edit_allowed && !playing && arg0<staged_count &&
        arg1<256 && arg2<4 && data_sequence_ok && (arg2[1]==last_in_block);
    wire [ADDRESS_BITS:0] write_address = {!active_bank,arg0[ADDRESS_BITS-1:0]};
    wire [15:0] sum_next = checksum + {8'd0,ram_q};
    wire block_data_start = resetn && request && operation==2 && state==IDLE &&
        staging && edit_allowed && !playing && arg0<staged_count &&
        arg1<256 && arg2<4 && arg2[0] && arg0[3:0]==0;
    wire block_data_end = data_write && arg2[1];
    wire block_write = resetn && (state==CLEAR_BLOCKS || block_data_start || block_data_end);
    wire [BLOCK_ADDRESS_BITS-1:0] block_write_address =
        state==CLEAR_BLOCKS ? clear_index : arg0 >> 4;
    wire [BLOCK_ADDRESS_BITS-1:0] block_read_address = check_index >> 4;
    wire block_write_value = (state==CLEAR_BLOCKS) ? 1'b0 : block_data_end;

    // No RAM reset: synchronous read and one write port infer block RAM.
    always @(posedge clk) begin
        if(data_write) pcm[write_address] <= arg1[7:0];
        ram_q <= pcm[read_address];
    end
    always @(posedge clk) begin
        if(block_write) block_written[block_write_address] <= block_write_value;
        block_q <= block_written[block_read_address];
    end

    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; active_bank<=0; staging<=0; block_open<=0;
            clear_index<=0; staged_count<=0; active_count<=0;
            expected_sum<=0; checksum<=0; check_index<=0; play_index<=0;
            next_address<=0; phase<=0; done<=0; error<=0;
            valid<=0; playing<=0; sample<=0;
        end else begin
            done<=0;
            // RAM verification and playback progress independently of rejected
            // UART commands, so a BUSY response cannot stretch an audio frame.
            case(state)
                CLEAR_BLOCKS: begin
                    if(clear_index==BLOCKS-1) begin
                        state<=IDLE; staging<=1; done<=1; error<=0;
                    end else clear_index<=clear_index+1'b1;
                end
                CHECK_FETCH: state<=CHECK_WAIT;
                CHECK_WAIT: state<=CHECK_SUM;
                CHECK_SUM: begin
                    if(!block_q) begin
                        done<=1; error<=4; state<=IDLE;
                    end else if(check_index==staged_count-1'b1) begin
                        done<=1; state<=IDLE;
                        if(sum_next!=expected_sum) error<=5;
                        else begin
                            error<=0; active_bank<=!active_bank;
                            active_count<=staged_count; valid<=1; staging<=0;
                        end
                    end else begin
                        checksum<=sum_next; check_index<=check_index+1'b1;
                        state<=CHECK_FETCH;
                    end
                end
                PLAY_FETCH: state<=PLAY_WAIT;
                PLAY_WAIT: state<=PLAY_LOAD;
                PLAY_LOAD: begin sample<={ram_q,8'd0}; state<=RUN; end
                RUN: if(sample_ce) begin
                    if(phase_next>=27'd50000000) begin
                        phase<=phase_next-27'd50000000;
                        if(play_index==active_count-1'b1) begin
                            playing<=0; sample<=0; state<=IDLE;
                        end else begin
                            play_index<=play_index+1'b1; state<=PLAY_FETCH;
                        end
                    end else phase<=phase_next[25:0];
                end
                default: begin end
            endcase

            if(request && operation==5) begin
                state<=IDLE; playing<=0; sample<=0; phase<=0;
                // An interrupted bitmap clear cannot expose stale valid bits.
                if(state==CLEAR_BLOCKS) staging<=0;
                done<=1; error<=0;
            end else if((request && operation==4) ||
                        (!request && valid && (toggle_play || restart))) begin
                if(!request && toggle_play && playing && !restart) begin
                    state<=IDLE; playing<=0; sample<=0; phase<=0;
                end else if(!valid) begin
                    if(request) begin done<=1; error<=3; end
                end
                else if(state!=IDLE && state!=RUN && state!=PLAY_FETCH &&
                        state!=PLAY_WAIT && state!=PLAY_LOAD) begin
                    // A physical key during verification/clear must not mask
                    // that transaction's final completion pulse.
                    if(request) begin done<=1; error<=1; end
                end else begin
                    play_index<=0; phase<=0; sample<=0; playing<=1;
                    state<=PLAY_FETCH; done<=request; error<=0;
                end
            end else if(request) begin
                done<=1;
                if(state!=IDLE || playing || !edit_allowed) error<=1;
                else case(operation)
                    1: begin
                        if(arg0==0 || arg0>MAX_SAMPLES) error<=2;
                        else begin
                            staging<=0; block_open<=0; clear_index<=0;
                            staged_count<=arg0; expected_sum<=arg1; error<=0;
                            state<=CLEAR_BLOCKS; done<=0;
                        end
                    end
                    2: begin
                        if(!staging) error<=3;
                        else if(arg0>=staged_count || arg1>255 || arg2>3) begin
                            block_open<=0; error<=2;
                        end else begin
                            // A retried first byte invalidates its entire block
                            // until every byte, including the tail, arrives.
                            if(!data_sequence_ok) begin
                                block_open<=0; error<=3;
                            end else if(arg2[1]!=last_in_block) begin
                                block_open<=0; error<=2;
                            end else begin
                                error<=0; next_address<=arg0+1'b1;
                                block_open<=!arg2[1];
                            end
                        end
                    end
                    3: begin
                        if(!staging) error<=3;
                        else if(block_open) error<=4;
                        else begin
                            done<=0; checksum<=0; check_index<=0;
                            state<=CHECK_FETCH;
                        end
                    end
                    default: error<=3;
                endcase
            end
        end
    end
endmodule
