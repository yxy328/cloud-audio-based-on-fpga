`timescale 1ns/1ps
// Atomic score download. Both playback cursors share one synchronous RAM port.
// 1=BEGIN, 2=NOTE (MIDI), 3=END, 4=PLAY, 5=STOP, 6=CHORD (13-bit mask).
module downloadable_song #(
    parameter integer CLK_HZ=50_000_000, CONTROL_KEYS=7,
    parameter integer ENABLE_LOOKAHEAD=0, TRUSTED_MAP=0,
    parameter integer LOOKAHEAD_MS=1500
) (
    input wire clk, resetn,
    input wire request,
    input wire [2:0] operation,
    input wire [15:0] arg0, arg1, arg2, arg3,
    input wire [15:0] score_min,score_max,
    output wire [15:0] score_ratio,
    input wire edit_allowed,
    input wire [CONTROL_KEYS*8-1:0] note_map,
    input wire toggle_play, restart,
    output reg done,
    // 0=OK, 1=BUSY, 2=RANGE, 3=STATE, 4=MISSING, 5=MAP
    output reg [2:0] error,
    output reg valid,
    output reg playing,
    output wire gate,
    output reg [7:0] current_note,
    output reg [CONTROL_KEYS-1:0] guide_keys,
    output wire ms_tick,
    output reg guide_reset,
    output reg event_start,event_end,
    output wire [15:0] event_duration,
    output wire spawn_long,
    output wire [1:0] event_type,
    output reg [1:0] spawn_type,
    output reg spawn_body,
    output reg note_spawn,
    output reg [CONTROL_KEYS-1:0] spawn_keys,
    output reg [15:0] spawn_delay_ms,
    input wire note_ready,
    output reg [12:0] current_mask,
    output wire busy
);
    localparam IDLE=0, CHECK_FETCH=1, CHECK_WAIT=2, CHECK=3,
        PRIME=4, RUN=5, MAP_SCAN=6, CLEAR_BANK=7;
    localparam integer MS_TICKS=(CLK_HZ/1000 < 1) ? 1 : CLK_HZ/1000;
    localparam integer PRE_ROLL_MS=ENABLE_LOOKAHEAD ? LOOKAHEAD_MS : 0;
    // 256 events of at most 60000ms plus pre-roll and lookahead carry.
    // 24 bits cover the entire legal timeline, including a stalled renderer.
    localparam integer REQUIRED_TIME_BITS=$clog2(64'd15360000+PRE_ROLL_MS+LOOKAHEAD_MS+64'd2);
    localparam integer TIME_BITS=REQUIRED_TIME_BITS>32 ? 32 : REQUIRED_TIME_BITS;
    (* syn_encoding="onehot" *) reg [2:0] state;
    // type: 0 TAP, 1 HOLD, 2 DRAG, 3 FLICK. Still fits the native wide RAMs.
    reg [46:0] score [0:511]; // {type, ratio, pitch mask, duration}; two 256-event banks
    reg [46:0] fetched;
    reg active_bank, staging, check_play;
    // BEGIN clears only the staging bank. Duration zero is the missing-record
    // sentinel, avoiding a 256-bit validity bitmap and its variable-bit muxes.
    // Arbitrary write order and duplicate overwrites remain supported.
    reg [8:0] staged_count, active_count;
    reg [7:0] index;
    localparam MAP_BITS=TRUSTED_MAP ? 4 : 8;
    reg [CONTROL_KEYS*MAP_BITS-1:0] checked_map;
    function [CONTROL_KEYS*MAP_BITS-1:0] pack_checked_map;
        input [CONTROL_KEYS*8-1:0] notes;
        integer key;
        begin
            for(key=0;key<CONTROL_KEYS;key=key+1)
                pack_checked_map[key*MAP_BITS+:MAP_BITS]=notes[key*8+:MAP_BITS];
        end
    endfunction
    localparam MS_BITS=MS_TICKS<2 ? 1 : $clog2(MS_TICKS);
    reg [MS_BITS-1:0] ms_count;
    reg [TIME_BITS-1:0] elapsed_ms;

    reg [46:0] cur_word, next_word, future_word;
    assign score_ratio=cur_word[44:29];
    assign event_duration=cur_word[15:0];
    assign event_type=cur_word[46:45];
    reg future_long;
    assign spawn_long=future_long;
    reg tail_active;
    reg [CONTROL_KEYS-1:0] tail_keys;
    // The future cursor already holds the end of the last emitted interval.
    // Feed its HOLD body through the existing circular raster at the top.
    // No per-note tail timers, division or extra display RAMs are needed.
    wire [2:0] requested_type=arg1[15:13];
    wire [1:0] stored_type=requested_type==0 ? (arg2>=500 ? 2'd1 : 2'd0) : requested_type-3'd1;
    reg cur_have, next_have, future_have, current_finished, future_finished;
    reg [7:0] cur_index, future_index;
    // Key/pitch decoding is registered with the word it came from so the two
    // decoder functions exist once instead of at every call site.
    reg [CONTROL_KEYS-1:0] cur_keys, next_keys, future_keys;
    reg [7:0] cur_pitch, next_pitch;
    reg [TIME_BITS-1:0] cur_start_ms, cur_end_ms, future_start_ms;
    reg read_enable, read_pending;
    reg [8:0] read_address;
    reg [1:0] read_target, pending_target;
    reg [12:0] covered_mask;
    wire available=state==IDLE || state==RUN || state==PRIME;
    wire [3:0] write_offset=arg1[3:0]-4'd12;
    wire bad_record=arg0>=staged_count || arg2==0 || arg2>60000 ||
        (operation==2 && (arg1<60 || arg1>72)) ||
        (operation==6 && (requested_type>4 || (CONTROL_KEYS!=12 && requested_type!=0) ||
        (requested_type!=0 && arg1[12:0]==0) ||
        (arg3!=0 && (arg3<8192 || arg3>32768))));
    wire clear_word=state==CLEAR_BANK;
    wire write_word=request && (operation==2 || operation==6) &&
        available && edit_allowed && !playing && staging && !bad_record;
    wire [8:0] write_address={!active_bank,clear_word ? index : arg0[7:0]};
    wire [46:0] write_data=clear_word ? 47'd0 : operation==2 ?
        {(arg2>=500 ? 2'd1 : 2'd0),16'd0,(13'b1 << write_offset),arg2} :
        {stored_type,arg3,arg1[12:0],arg2};
    assign busy=state!=IDLE;
    wire [TIME_BITS-1:0] next_elapsed_ms=elapsed_ms+1'b1;
    wire [TIME_BITS-1:0] event_elapsed_ms=(ms_tick && !current_finished) ? next_elapsed_ms : elapsed_ms;
    wire [TIME_BITS:0] future_due_full={1'b0,future_start_ms}+PRE_ROLL_MS;
    wire [TIME_BITS-1:0] future_due_ms=future_due_full[TIME_BITS-1:0];
    wire [TIME_BITS-1:0] future_delay_ms=future_due_ms-event_elapsed_ms;
    wire future_on_screen=future_due_ms<=event_elapsed_ms+LOOKAHEAD_MS;
    wire tail_visible=tail_active && !future_on_screen;
    integer k;

    function [7:0] first_pitch;
        input [12:0] mask;
        integer j;
        begin
            first_pitch=60;
            for(j=12;j>=0;j=j-1)
                if(mask[j]) first_pitch=60+j;
        end
    endfunction
    reg [$clog2(CONTROL_KEYS)-1:0] map_index;
    wire [3:0] map_low=checked_map[map_index*MAP_BITS+:4];
    wire [7:0] map_pitch;
    generate if(TRUSTED_MAP)begin: compact_map
        assign map_pitch={map_low>=12 ? 4'd3 : 4'd4,map_low};
    end else assign map_pitch=checked_map[map_index*MAP_BITS+:8];endgenerate
    // Range guards already constrain MIDI to 60..72. A four-bit offset
    // addresses only the thirteen mask bits, rather than all 45 score bits.
    wire [3:0] map_offset=map_pitch[3:0]-4'd12;
    wire [12:0] fetched_mask=fetched[28:16];
    // Build the coverage union once per END/PLAY, using one decoder.
    // Twelve extra fabric clocks do not touch the audio frame schedule.
    // Only one copy of each decoder exists: it is evaluated on the byte-wide
    // fetch result and stored beside the word it belongs to.
    reg [CONTROL_KEYS-1:0] fetched_keys;
    reg key_decode_busy,key_decode_done;
    wire [7:0] fetched_pitch=first_pitch(fetched[28:16]);
    // The free-running millisecond pulse is also used by the renderer. Playback
    // starts on its edge, so every duration and the pre-roll use the same clock.
    assign ms_tick=resetn && ms_count==MS_TICKS-1;
    // A 1ms note-off before each boundary rearticulates repeated pitches.
    // AUDITION in the top applies this gate to all mapped chord voices.
    assign gate=playing && state==RUN && current_mask!=0 &&
        (cur_end_ms-elapsed_ms>1 || cur_word[15:0]==1);

    // Prioritize the sounding cursor; future visual events can wait for ready.
    // A request and its response occupy two cycles, with no asynchronous reads.
    always @* begin
        read_enable=0; read_address=0; read_target=0;
        if(state==CHECK_FETCH) begin
            read_enable=1;
            read_address={(check_play ? active_bank : !active_bank),index};
        end else if((state==PRIME || state==RUN) && !read_pending && !key_decode_busy && !key_decode_done) begin
            if(!cur_have && !current_finished) begin
                read_enable=1; read_target=1;
                read_address={active_bank,cur_index};
            end else if(cur_have && !next_have && cur_index<active_count-1) begin
                read_enable=1; read_target=2;
                read_address={active_bank,cur_index+8'd1};
            end else if(ENABLE_LOOKAHEAD && !future_have && !future_finished) begin
                read_enable=1; read_target=3;
                read_address={active_bank,future_index};
            end
        end
    end
    always @(posedge clk)
        if(read_enable) fetched<=score[read_address];
    // One physical write port for both clearing and uploads; no RAM reset.
    always @(posedge clk)
        if(clear_word || write_word) score[write_address]<=write_data;

    task clear_playback;
        begin
            playing<=0; guide_keys<=0; current_mask<=0; guide_reset<=1;
            note_spawn<=0; cur_have<=0; next_have<=0; future_have<=0;
            read_pending<=0;key_decode_busy<=0;key_decode_done<=0;
            tail_active<=0;spawn_body<=0;
        end
    endtask
    task finish;
        input [2:0] result;
        begin done<=1; error<=result; state<=IDLE; end
    endtask
    task start_validation;
        begin
            clear_playback;
            index<=0; checked_map<=pack_checked_map(note_map); check_play<=1; covered_mask<=0;map_index<=0;state<=MAP_SCAN;
        end
    endtask

    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; active_bank<=0; staging<=0;
            staged_count<=0; active_count<=0; index<=0; checked_map<=0;
            covered_mask<=0;map_index<=0;check_play<=0; done<=0; error<=0; valid<=0; playing<=0;
            current_note<=60; current_mask<=0; guide_keys<=0;
            ms_count<=0; elapsed_ms<=0;
            cur_word<=0; next_word<=0; future_word<=0;
            cur_keys<=0; next_keys<=0; future_keys<=0;
            cur_pitch<=60; next_pitch<=60;
            cur_have<=0; next_have<=0; future_have<=0;
            current_finished<=0; future_finished<=1;
            cur_index<=0; future_index<=0;
            cur_start_ms<=0; cur_end_ms<=0; future_start_ms<=0;
            read_pending<=0; pending_target<=0;key_decode_busy<=0;key_decode_done<=0;fetched_keys<=0;
            guide_reset<=1; event_start<=0;event_end<=0;note_spawn<=0; spawn_keys<=0; spawn_delay_ms<=0;
            spawn_type<=0;spawn_body<=0;tail_active<=0;tail_keys<=0;
        end else begin
            done<=0; guide_reset<=0; note_spawn<=0;event_start<=0;event_end<=0;
            if(ms_tick) ms_count<=0;
            else ms_count<=ms_count+1'b1;
            read_pending<=read_enable;
            if(read_enable)pending_target<=read_target;

            key_decode_done<=0;
            if(read_pending && (state==PRIME || state==RUN))begin
                key_decode_busy<=1;map_index<=0;fetched_keys<=0;
            end
            if(key_decode_busy)begin
                if(map_pitch>=60 && map_pitch<=72)fetched_keys[map_index]<=fetched_mask[map_offset];
                if(map_index==CONTROL_KEYS-1)begin key_decode_busy<=0;key_decode_done<=1;end
                else map_index<=map_index+1'b1;
            end
            if(key_decode_done && (state==PRIME || state==RUN)) begin
                case(pending_target)
                    1: begin
                        cur_word<=fetched; cur_have<=1;
                        cur_end_ms<=cur_start_ms+fetched[15:0];
                        cur_keys<=fetched_keys; cur_pitch<=fetched_pitch;
                    end
                    2: begin
                        next_word<=fetched; next_have<=1;
                        next_keys<=fetched_keys; next_pitch<=fetched_pitch;
                    end
                    3: begin
                        future_word<=fetched; future_have<=1;
                        future_keys<=fetched_keys;
                    end
                    default: begin end
                endcase
            end
            case(state)
                CLEAR_BANK:begin
                    if(index==staged_count-1)begin staging<=1;finish(0);end
                    else index<=index+1'b1;
                end
                MAP_SCAN:begin
                    if(map_pitch>=60 && map_pitch<=72)covered_mask[map_offset]<=1'b1;
                    if(map_index==CONTROL_KEYS-1)state<=CHECK_FETCH;
                    else map_index<=map_index+1'b1;
                end
                CHECK_FETCH: state<=CHECK_WAIT;
                CHECK_WAIT: state<=CHECK;
                CHECK: begin
                    if(!check_play && fetched[15:0]==0) finish(4);
                    else if(fetched[15:0]==0 || fetched[15:0]>60000) finish(2);
                    else if(fetched[44:29]!=0 && (fetched[44:29]<score_min || fetched[44:29]>score_max)) finish(2);
                    else if((fetched[28:16] & ~covered_mask)!=0) finish(5);
                    else if(index==(check_play ? active_count : staged_count)-1) begin
                        if(check_play) begin
                            cur_index<=0; future_index<=0;
                            cur_have<=0; next_have<=0; future_have<=0;
                            current_finished<=0; future_finished<=!ENABLE_LOOKAHEAD;
                            cur_start_ms<=PRE_ROLL_MS; future_start_ms<=0;
                            elapsed_ms<=0; playing<=1; state<=PRIME;
                            tail_active<=0;
                            done<=ENABLE_LOOKAHEAD!=0; error<=0;
                        end else begin
                            active_bank<=!active_bank; active_count<=staged_count;
                            valid<=1; staging<=0; finish(0);
                        end
                    end else begin index<=index+1'b1; state<=CHECK_FETCH; end
                end
                PRIME: begin
                    if(cur_have && (next_have || active_count==1) &&
                        (future_have || !ENABLE_LOOKAHEAD) && ms_tick) begin
                        elapsed_ms<=0; state<=RUN;
                        if(PRE_ROLL_MS==0) begin
                            current_note<=cur_pitch;
                            current_mask<=cur_word[28:16];
                            guide_keys<=cur_keys;event_start<=1;
                        end
                        if(!ENABLE_LOOKAHEAD) begin done<=1; error<=0; end
                    end
                end
                RUN: begin
                    if(ENABLE_LOOKAHEAD && CONTROL_KEYS==12 && ms_tick && tail_visible && note_ready)begin
                        note_spawn<=1;spawn_keys<=tail_keys;spawn_delay_ms<=LOOKAHEAD_MS;
                        spawn_type<=1;spawn_body<=1;future_long<=1;
                    end
                    if(!tail_visible)tail_active<=0;
                    if(ENABLE_LOOKAHEAD && future_have && !future_finished &&
                        future_on_screen &&
                        (future_word[28:16]==0 || note_ready)) begin
                        if(future_word[28:16]!=0) begin
                            note_spawn<=1;
                            spawn_keys<=future_keys;future_long<=future_word[46:45]==1;
                            spawn_type<=future_word[46:45];spawn_body<=0;
                            if(future_due_ms>event_elapsed_ms)
                                spawn_delay_ms<=future_delay_ms[15:0];
                            else spawn_delay_ms<=0;
                        end
                        future_have<=0;
                        tail_active<=future_word[46:45]==1 && future_word[28:16]!=0;
                        tail_keys<=future_keys;
                        future_start_ms<=future_start_ms+future_word[15:0];
                        if(future_index==active_count-1) future_finished<=1;
                        else future_index<=future_index+1'b1;
                    end
                    if(ms_tick) begin
                        // Once audio has finished, every remaining visual
                        // event is already due. Freeze time while note_ready
                        // stalls instead of letting a bounded counter wrap.
                        if(!current_finished)elapsed_ms<=next_elapsed_ms;
                        if(!current_finished && cur_have) begin
                            if(next_elapsed_ms>=cur_end_ms) begin
                                if(cur_index==active_count-1) begin
                                    current_finished<=1;event_end<=1;guide_keys<=0; current_mask<=0;
                                end else if(next_have) begin
                                    cur_index<=cur_index+1'b1;
                                    cur_word<=next_word; next_have<=0;
                                    cur_keys<=next_keys; cur_pitch<=next_pitch;
                                    cur_start_ms<=cur_end_ms;
                                    cur_end_ms<=cur_end_ms+next_word[15:0];
                                    current_note<=next_pitch;
                                    current_mask<=next_word[28:16];
                                    guide_keys<=next_keys;event_start<=1;event_end<=1;
                                end
                            end else if(next_elapsed_ms>=cur_start_ms) begin
                                current_note<=cur_pitch;
                                current_mask<=cur_word[28:16];
                                guide_keys<=cur_keys;
                                if(elapsed_ms<cur_start_ms)event_start<=1;
                            end
                        end
                    end
                    if(current_finished && future_finished) begin
                        playing<=0; guide_keys<=0; current_mask<=0; state<=IDLE;
                    end
                end
                default: begin end
            endcase

            // Commands do not suspend the musical clock. Busy responses may be
            // returned while an earlier validation continues in the background.
            if(request) begin
                case(operation)
                    5: begin clear_playback; finish(0); end
                    1: begin
                        done<=1;
                        if(!available || !edit_allowed || playing) error<=1;
                        else if(arg0==0 || arg0>256) error<=2;
                        else begin
                            staging<=0; staged_count<=arg0[8:0]; index<=0;
                            state<=CLEAR_BANK; done<=0; error<=0;
                        end
                    end
                    2,6: begin
                        done<=1;
                        if(!available || !edit_allowed || playing) error<=1;
                        else if(!staging) error<=3;
                        else if(bad_record) error<=2;
                        else error<=0;
                    end
                    3: begin
                        if(!available || !edit_allowed || playing) begin done<=1; error<=1; end
                        else if(!staging) begin done<=1; error<=3; end
                        else begin
                            index<=0; checked_map<=pack_checked_map(note_map); check_play<=0; covered_mask<=0;map_index<=0;state<=MAP_SCAN;
                        end
                    end
                    4: begin
                        if(!valid) begin done<=1; error<=3; end
                        else if(!available) begin done<=1; error<=1; end
                        else start_validation;
                    end
                    default: begin done<=1; error<=2; end
                endcase
            end else if(valid && (restart || toggle_play)) begin
                if(toggle_play && playing && !restart) begin
                    clear_playback; state<=IDLE;
                end else if(available) start_validation;
            end
        end
    end
endmodule
