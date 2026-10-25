`timescale 1ns/1ps
// Event timeline, never PCM. Storage is an explicit external adapter; RAM
// availability and a successful nonvolatile commit are separate status bits.
// Each word is {milliseconds[23:0], field[7:0], value[15:0]}.
// Fields 0..WORDS-2 stage controls; the final word is the note-gate mask.
// FE commits the gates and emits one-shot events after their controls have
// arrived. FF ends the take and clears all synth/effect tails.
module performance_take #(
    parameter integer CLK_HZ=50000000, WORDS=33, DEPTH=1024
)(
    input wire clk,resetn,frame_ce,
    input wire [2:0] command,
    input wire [WORDS*16-1:0] live_state,
    input wire [15:0] live_pulses,
    output wire [WORDS*16-1:0] play_state,
    output wire play_valid,
    output reg [15:0] play_pulses,
    output reg recording,playing,kill,
    output reg available,saved,full,
    output reg [3:0] error,
    output reg [1:0] confirm,
    output reg [23:0] elapsed_ms,duration_ms,
    output reg [$clog2(DEPTH):0] count,
    // Adapter owns RAM only during boot/save. Its boot_done is a pulse even
    // for an empty or locked device. A save never stalls the live audio path.
    input wire nv_busy,nv_boot_done,nv_valid,nv_done,nv_ok,nv_full,
    input wire [3:0] nv_error,
    input wire [$clog2(DEPTH):0] nv_count,
    input wire [23:0] nv_duration,
    output reg nv_save,nv_delete,
    input wire nv_we,
    input wire [$clog2(DEPTH)-1:0] nv_address,
    input wire [47:0] nv_data,
    output wire [47:0] nv_q
);
    localparam AW=$clog2(DEPTH), FW=$clog2(WORDS+1), MS_DIV=CLK_HZ/1000;
    localparam MW=MS_DIV<2 ? 1 : $clog2(MS_DIV);
    localparam BOOT=0,IDLE=1,C_SCAN=2,C_MARK=3,C_WAIT=4,C_END=5,
        P_FETCH=6,P_FETCH2=7,P_DECODE=8,P_WAIT=9,SAVE=10,C_READ=11;
    reg [3:0] state;
    reg [MW-1:0] ms_div;
    wire tick=ms_div==MS_DIV-1;
    reg [7:0] field;
    reg [23:0] snapshot_time,stop_time,last_play_time;
    reg [15:0] pending_pulses,snapshot_pulses;
    reg force_snapshot,changed,stopping,final_scan,deleting,primed,has_music,group_active;
    reg [FW-1:0] initial_next;
    reg [AW:0] cursor;
    (* syn_ramstyle="block_ram" *) reg [47:0] events[0:DEPTH-1];
    reg [47:0] ram_q;
    // Playback keeps the read address fixed until the current event is
    // consumed, so the synchronous RAM output already holds the event.
    wire [47:0] held=ram_q;
    // Freeze a complete control group before serializing it into RAM.
    // In particular, both halves of a 32-bit DDS increment must agree.
    reg [WORDS*16-1:0] capture_state;
    // One narrow synchronous history RAM replaces two wide state banks.
    (* syn_ramstyle="block_ram" *) reg [15:0] history[0:WORDS-1];
    reg [15:0] previous_q,capture_word,pending_gates;
    wire [WORDS*16-1:0] played_words;
    wire event_due;
    // K14+K16 is deletion only while idle. During recording/playback its
    // K14 component still has unconditional STOP priority.
    wire stop_command=command==2 || (command==4 && (recording || playing));
    assign event_due=(state==P_DECODE || state==P_WAIT) && held[47:24]<=elapsed_ms &&
        held[47:24]>=last_play_time && (primed || held[47:24]==0) && !stop_command &&
        (group_active || frame_ce || held[23:16]==8'hff);
    wire field_event;
    assign field_event=event_due && held[23:16]<WORDS;
    wire apply_event;
    assign apply_event=event_due && held[23:16]==8'hfe &&
        (primed || initial_next==WORDS);
    genvar word_number;
    generate for(word_number=0;word_number<WORDS;word_number=word_number+1)begin: replay_words
        reg [15:0] value;
        if(word_number==WORDS-1)begin: gate_word
            always @(posedge clk)begin
                if(!resetn || !playing)value<=0;
                else if(apply_event)value<=held[15] ? 16'd0 : pending_gates;
            end
        end else begin: config_word
            always @(posedge clk)
                if(resetn && field_event && held[23:16]==word_number)value<=held[15:0];
        end
        assign played_words[word_number*16 +: 16]=value;
    end endgenerate
    // Control registers have meaning only after the initial snapshot has
    // been restored. Avoid 528 redundant output gates in front of the
    // caller's live/replay mux; gate-word zeroing still releases notes.
    assign play_state=played_words;
    assign play_valid=playing && primed;
    always @(posedge clk)begin
        if(resetn && state==C_READ)begin
            previous_q<=history[field];capture_word<=capture_state[15:0];
        end
        if(resetn && state==C_SCAN)history[field]<=capture_word;
    end
    wire cap_field=state==C_SCAN && (force_snapshot ||
        capture_word!=previous_q);
    wire cap_mark=state==C_MARK && (force_snapshot || changed || snapshot_pulses!=0);
    wire cap_end=state==C_END;
    wire cap_we=cap_field || cap_mark || cap_end;
    wire [47:0] cap_data=cap_end ? {stop_time,8'hff,16'd0} :
        cap_mark ? {snapshot_time,8'hfe,snapshot_pulses} :
        {snapshot_time,field,capture_word};
    always @(posedge clk) begin
        if(resetn && (nv_we || cap_we))
            events[nv_we ? nv_address : count[AW-1:0]]<=nv_we ? nv_data : cap_data;
        ram_q<=events[nv_busy ? nv_address : cursor[AW-1:0]];
    end
    assign nv_q=ram_q;
    task fail;
        input [3:0] code;
        begin
            error<=code;recording<=0;playing<=0;kill<=playing;state<=IDLE;
            play_pulses<=0;confirm<=0;
        end
    endtask
    task begin_capture;
        begin
            state<=C_READ;recording<=1;playing<=0;available<=0;saved<=0;
            full<=0;error<=0;confirm<=0;count<=0;elapsed_ms<=0;duration_ms<=0;
            ms_div<=0;snapshot_time<=0;field<=0;force_snapshot<=1;changed<=0;
            snapshot_pulses<=live_pulses;
            capture_state<=live_state;
            pending_pulses<=0;stopping<=0;final_scan<=0;kill<=1;
            has_music<=0;
        end
    endtask
    task final_snapshot;
        begin
            snapshot_pulses<=pending_pulses | live_pulses;
            capture_state<=live_state;
            pending_pulses<=0;snapshot_time<=stop_time;field<=0;changed<=0;
            force_snapshot<=0;final_scan<=1;state<=C_READ;
        end
    endtask
    task consume_event;
        begin
            if(held[23:16]<WORDS)begin
                if((!primed && held[23:16]!=initial_next) || initial_next>=WORDS)fail(3);
                else begin
                    if(held[23:16]==WORDS-1)pending_gates<=held[15:0];
                    initial_next<=initial_next+1'b1;group_active<=1;
                    state<=P_FETCH;
                end
            end else if(held[23:16]==8'hfe)begin
                if(!primed && (held[47:24]!=0 || initial_next!=WORDS))fail(3);
                else begin
                    play_pulses<=held[15:0];
                    if(held[15])kill<=1;
                    primed<=1;group_active<=0;initial_next<=0;state<=P_FETCH;
                end
            end else if(held[23:16]==8'hff && held[15:0]==0 && primed && !group_active && cursor==count-1)begin
                playing<=0;play_pulses<=0;kill<=1;state<=IDLE;
            end else fail(3);
            last_play_time<=held[47:24];
            cursor<=cursor+1'b1;
        end
    endtask
    always @(posedge clk)begin
        if(!resetn)begin
            state<=BOOT;ms_div<=0;pending_gates<=0;play_pulses<=0;
            recording<=0;playing<=0;kill<=0;available<=0;saved<=0;full<=0;error<=0;
            confirm<=0;elapsed_ms<=0;duration_ms<=0;count<=0;field<=0;snapshot_time<=0;
            stop_time<=0;last_play_time<=0;pending_pulses<=0;snapshot_pulses<=0;
            force_snapshot<=0;changed<=0;stopping<=0;final_scan<=0;deleting<=0;
            primed<=0;has_music<=0;group_active<=0;initial_next<=0;cursor<=0;nv_save<=0;nv_delete<=0;
        end else begin
            // Fields are visited in order. Shifting the frozen group avoids
            // a 33-way, 16-bit selector while keeping each group atomic.
            if(state==C_READ)capture_state<=capture_state>>16;
            kill<=0;play_pulses<=0;nv_save<=0;nv_delete<=0;
            if(recording || (playing && primed))begin
                if(tick)begin ms_div<=0;elapsed_ms<=elapsed_ms+1'b1;end
                else ms_div<=ms_div+1'b1;
            end
            if(recording && !final_scan)pending_pulses<=pending_pulses | live_pulses;
            if(recording && ((|live_state[(WORDS-1)*16 +: 16]) || (|live_pulses[14:0])))has_music<=1;
            if(cap_we)count<=count+1'b1;
            case(state)
                BOOT:if(nv_boot_done)begin
                    available<=nv_valid;saved<=nv_valid;count<=nv_count;duration_ms<=nv_duration;
                    elapsed_ms<=nv_duration;full<=nv_full;error<=nv_error;state<=IDLE;
                end
                IDLE:if(!nv_busy)begin
                    case(command)
                        1:if(available || saved || nv_valid)confirm<=1;else begin_capture;
                        3:if(available && count!=0)begin
                            state<=P_FETCH;cursor<=0;elapsed_ms<=0;ms_div<=0;
                            playing<=1;primed<=0;pending_gates<=0;kill<=1;
                            initial_next<=0;group_active<=0;last_play_time<=0;error<=0;confirm<=0;
                        end else error<=4;
                        4:if(available || saved || nv_valid)confirm<=2;
                        5:if(confirm==1)begin_capture;
                          else if(confirm==2)begin nv_delete<=1;deleting<=1;state<=SAVE;confirm<=0;end
                        6:confirm<=0;
                        7:if(available && count!=0)begin
                            if(!saved)begin
                                error<=0;deleting<=0;nv_save<=1;state<=SAVE;confirm<=0;
                            end
                        end else error<=4;
                        default:begin end
                    endcase
                end
                C_READ:state<=C_SCAN;
                C_SCAN:begin
                    if(cap_field)changed<=1;
                    if(field==WORDS-1)state<=C_MARK;else begin field<=field+1'b1;state<=C_READ;end
                end
                C_MARK:begin
                    force_snapshot<=0;
                    if(final_scan)state<=C_END;
                    else if(stopping)final_snapshot;
                    else state<=C_WAIT;
                end
                C_WAIT:if(stopping)final_snapshot;
                    else if(tick)begin
                        if(count+WORDS*2+3>DEPTH || elapsed_ms==24'hfffffe)begin
                            full<=1;stop_time<=elapsed_ms+1'b1;state<=C_END;
                        end else begin
                            snapshot_pulses<=pending_pulses | live_pulses;
                            capture_state<=live_state;
                            pending_pulses<=0;snapshot_time<=elapsed_ms+1'b1;
                            field<=0;changed<=0;state<=C_READ;
                        end
                    end
                C_END:begin
                    recording<=0;duration_ms<=stop_time;elapsed_ms<=stop_time;
                    // STOP never writes Flash. The closed RAM timeline can
                    // be replayed immediately, including on a locked device.
                    available<=has_music;saved<=0;deleting<=0;state<=IDLE;
                    if(!has_music)begin count<=0;error<=4;end
                end
                SAVE:if(nv_done)begin
                    if(nv_ok)begin
                        saved<=!deleting;available<=!deleting;
                        if(deleting)begin count<=0;duration_ms<=0;elapsed_ms<=0;end
                    end else begin saved<=0;error<=nv_error==0 ? 5 : nv_error;end
                    state<=IDLE;
                end
                P_FETCH:if(cursor>=count)fail(3);else state<=P_FETCH2;
                P_FETCH2:state<=P_DECODE;
                // A group starts on an audio-frame edge, AFTER consumers
                // sampled the prior complete group. At most WORDS fields
                // plus FE take 3*(WORDS+1) clocks, well inside 1024 clocks.
                P_DECODE:if(held[47:24]<last_play_time || (!primed && held[47:24]!=0) ||
                        (group_active && held[47:24]!=last_play_time))fail(3);
                    else if(event_due)consume_event;
                    else state<=P_WAIT;
                P_WAIT:if(event_due)consume_event;
                default:fail(3);
            endcase
            // Control priority is explicit: stop cancels a pending read/apply.
            if(stop_command && playing)begin
                playing<=0;play_pulses<=0;kill<=1;state<=IDLE;confirm<=0;
            end
            if(command==2 && state==IDLE)confirm<=0;
            if(stop_command && recording && !stopping)begin
                stopping<=1;stop_time<=elapsed_ms+(tick ? 1'b1 : 1'b0);
            end
            // Duplicate one-shot events inside one millisecond cannot be
            // represented by a bit mask. Fail visibly instead of losing them.
            if(recording && !stopping && !final_scan && (|(pending_pulses & live_pulses)))fail(6);
            if(recording && tick && state!=C_WAIT && !stopping)fail(7);
            if(recording && count>=DEPTH)fail(7);
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk)
        if(resetn && playing && frame_ce && group_active)
            $fatal(1,"Playback control group crossed an audio-frame boundary");
    initial begin
        if(WORDS<1 || WORDS>254 || DEPTH<WORDS*2+4 || (DEPTH&(DEPTH-1))!=0 || CLK_HZ<1000)
            $fatal(1,"Invalid event timeline parameters");
    end
`endif
endmodule
