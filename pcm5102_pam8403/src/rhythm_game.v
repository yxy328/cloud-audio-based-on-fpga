`timescale 1ns/1ps
// Judgement uses the same millisecond enable as the score, never Bluetooth time.
// Each score event is one judgement (a chord requires every mapped lane).
// Windows end at the following event; edges are consumed once. Long events
// additionally require continuous contact after acquisition until event_end.
module rhythm_game #(parameter integer KEYS=12,TYPED_NOTES=0)(
    input wire clk,resetn,playing,ms_tick,event_start,event_end,
    input wire [KEYS-1:0] touch_keys,event_keys,
    input wire [15:0] event_duration,
    input wire [1:0] event_type,
    input wire gesture,
    // enable, long-note judging, effects, wide head, difficulty[1:0], theme[1:0]
    input wire [7:0] settings,
    output reg session,
    output wire [23:0] score_bcd,
    output wire [11:0] combo_bcd,best_bcd,miss_bcd,
    output reg [1:0] judgement,
    output reg [7:0] flash,
    output reg [KEYS-1:0] flash_keys,
    output reg holding,
    output wire [111:0] snapshot
);
    reg was_playing;
    reg [KEYS-1:0] previous_touch,pending,recent_valid,required_keys,matched;
    wire [KEYS-1:0] rising=touch_keys & ~previous_touch;
    reg [8:0] now_ms,due_ms;
    wire [8:0] elapsed=now_ms-due_ms;
    wire [7:0] window_ms=settings[3:2]==0 ? 8'd80 :
        settings[3:2]==1 ? 8'd120 : settings[3:2]==2 ? 8'd160 : 8'd200;
    // active/flash/epoch invalidate data until a complete event is captured.
    // Only those validity controls need reset; note payloads need no clear.
    reg active,long_note,perfect;
    reg [1:0] note_type;
    reg flick_seen,previous_gesture;
    wire flick_contact=(|(touch_keys & required_keys)) || (|matched);
    wire slide=(|(rising & ~required_keys)) && ((|(previous_touch & required_keys)) || (|matched));
    // One synchronous timestamp RAM and a serial scanner replace twelve
    // independent age counters/comparators. Every lane is serviced in 3 clocks.
    (* syn_ramstyle="block_ram" *) reg [8:0] timestamps[0:15];
    reg [3:0] lane;
    // DRAG/FLICK acquire contacts through the same serial scanner. FLICK
    // remembers those contacts until motion, including a slide off the pad.
    wire level_here=touch_keys[lane] && note_type>=2;
    reg [1:0] phase;
    reg [8:0] stamp_q;
    wire [8:0] stamp_age=now_ms-stamp_q;
    wire edge_here=pending[lane];
    wire [8:0] signed_offset=((note_type>=2 ? level_here : edge_here) ? now_ms : stamp_q)-due_ms;
    (* syn_romstyle="block_rom" *) reg [1:0] judge_rom[0:2047];
    reg [1:0] judge_q;
    reg eligible_q,epoch,read_epoch;
    initial $readmemh("src/rhythm_judge.hex",judge_rom);
    always @(posedge clk)judge_q<=judge_rom[{settings[3:2],signed_offset}];
    // At most 256 chart events: 768 credits of 500 points, combo/miss <=256.
    // Registered ROM conversion replaces four parallel decimal carry chains.
    reg [9:0] credits;
    reg [8:0] combo,best,miss;
    // floor(credits/2) is the thousands group; the final three digits are
    // either 000 or 500. Keep this ROM at 512x12 instead of doubling a 24-bit
    // table to 1024 entries (which would cost another physical BSRAM).
    (* syn_romstyle="block_rom" *) reg [11:0] points_rom[0:511];
    (* syn_romstyle="block_rom" *) reg [11:0] stats_rom[0:511];
    reg [11:0] points_q;
    reg points_half_q;
    reg [11:0] combo_q,best_q,miss_q;
    initial begin
        $readmemh("src/rhythm_points.hex",points_rom);
        $readmemh("src/rhythm_stats.hex",stats_rom);
    end
    always @(posedge clk)begin
        points_q<=points_rom[credits[9:1]];points_half_q<=credits[0];
        combo_q<=stats_rom[combo];best_q<=stats_rom[best];miss_q<=stats_rom[miss];
    end
    assign score_bcd={points_q,points_half_q ? 4'd5 : 4'd0,8'd0};
    assign combo_bcd=combo_q;assign best_bcd=best_q;assign miss_bcd=miss_q;
    assign snapshot={4'd2,settings,session,playing,holding,active,2'd0,judgement,
        score_bcd,combo_bcd,best_bcd,miss_bcd,32'd0};
    task finish_event;
        input success;
        begin
            active<=0;holding<=0;flash<=8'd180;flash_keys<=required_keys;
            if(success)begin
                credits<=credits+(perfect ? 10'd2 : 10'd1)+long_note;
                judgement<=perfect ? 2'd1 : 2'd2;
                combo<=combo+1'b1;
                if(combo+9'd1>best)best<=combo+9'd1;
            end else begin
                judgement<=3;combo<=0;miss<=miss+1'b1;
            end
        end
    endtask
    always @(posedge clk)begin
        stamp_q<=timestamps[lane];
        if(phase==1 && edge_here)timestamps[lane]<=now_ms;
        if(!resetn)begin
            was_playing<=0;session<=0;previous_touch<=0;pending<=0;recent_valid<=0;
            now_ms<=0;
            active<=0;holding<=0;
            credits<=0;combo<=0;best<=0;miss<=0;
            judgement<=0;flash<=0;lane<=0;phase<=0;epoch<=0;
            note_type<=0;flick_seen<=0;previous_gesture<=0;
        end else begin
            previous_touch<=touch_keys;was_playing<=playing;
            previous_gesture<=gesture;
            if(active && note_type==3 && ((gesture && !previous_gesture && flick_contact) || slide))flick_seen<=1;
            phase<=phase==2 ? 0 : phase+1'b1;
            if(phase==1)begin
                read_epoch<=epoch;
                eligible_q<=note_type>=2 ? level_here : edge_here || recent_valid[lane];
                if(edge_here)recent_valid[lane]<=1;
                else if(stamp_age>window_ms)recent_valid[lane]<=0;
            end
            if(phase==2)begin
                lane<=lane==KEYS-1 ? 0 : lane+1'b1;
                if(active && !holding && read_epoch==epoch && eligible_q && judge_q[0] &&
                    required_keys[lane] && !matched[lane])begin
                    matched[lane]<=1;recent_valid[lane]<=0;
                    if(!judge_q[1])perfect<=0;
                end
            end
            // Preserve simultaneous edges, including one on the scanner lane.
            pending<=pending | rising;
            if(phase==1)pending[lane]<=rising[lane];
            if(ms_tick)begin
                now_ms<=now_ms+1'b1;
                if(flash!=0)flash<=flash-1'b1;
            end
            if(active)begin
                if(holding)begin
                    if(event_end || event_start)finish_event(1);
                    else if(!playing)finish_event(0);
                    else if((touch_keys & required_keys)!=required_keys)finish_event(0);
                end else if(matched==required_keys && (note_type!=3 || flick_seen))begin
                    if(long_note)begin
                        if((touch_keys & required_keys)!=required_keys)finish_event(0);
                        else if(event_end || event_start)finish_event(1);
                    else if(!playing)finish_event(0);
                        else holding<=1;
                    end else finish_event(1);
                end else if(elapsed>{1'b0,window_ms} || event_end || !playing || event_start)finish_event(0);
            end
            if(event_start && playing && settings[7])begin
                required_keys<=event_keys;matched<=0;due_ms<=now_ms;epoch<=~epoch;
                active<=event_keys!=0;holding<=0;perfect<=1;
                long_note<=settings[6] && event_duration>=500;
                if(TYPED_NOTES)begin
                    note_type<=event_type==1 && !settings[6] ? 2'd0 : event_type;
                    long_note<=settings[6] && event_type==1;
                end else note_type<=settings[6] && event_duration>=500 ? 2'd1 : 2'd0;
                flick_seen<=0;
            end
            if(playing && !was_playing)begin
                session<=settings[7];credits<=0;combo<=0;best<=0;miss<=0;
                active<=0;holding<=0;recent_valid<=0;pending<=0;
                judgement<=0;flash<=0;
            end
            if(!settings[7])begin session<=0;active<=0;holding<=0;end
        end
    end
endmodule
