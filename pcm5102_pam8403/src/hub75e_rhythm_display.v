`timescale 1ns/1ps
// 64x64, 1/32-scan HUB75E rhythm display. Every register uses clk; hub_CK
// is an output waveform, never an internal clock. RGB has one full 50MHz
// cycle of setup before each 25MHz external shift-clock rising edge.
//
// A circular bitmap holds note heads rather than a per-note register queue.
// Game pixels use three bitplanes: head present, type low, type high.
// HOLD body pixels set only type low; the same ring scrolls heads and tails.
// Notes closer than one screen pixel share a row and OR their key masks.
// This accepts all 128 score events even at 1ms spacing without consuming
// 128 copies of a timer/position accumulator or blocking the sequencer.
module hub75e_rhythm_display #(
    parameter integer ENABLE_GAME=0,
    parameter integer LEAD_MS = 1500, CONTROL_KEYS=7,
    parameter integer ENABLE_AUDIO_VISUAL = 0,
    parameter integer ENABLE_STATUS = 0,
    parameter integer ENABLE_TAKE_STATUS = 0
) (
    input wire clk,
    input wire resetn,
    input wire [CONTROL_KEYS-1:0] touch_keys,
    input wire touch_mode16,
    input wire [15:0] all_touch_keys,
    input wire [15:0] physical_keys,
    input wire [7:0] ir_keys,
    input wire [1:0] touch_hold,
    input wire pressure_pitch,recording,keys_ready,
    input wire [2:0] timbre,analog_mode,
    input wire [1:0] effect_mode,
    input wire [3:0] effect_wet,
    input wire [4:0] volume,
    input wire [12:0] master_gain,
    input wire [9:0] adc_sample,analog_position,
    input wire analog_valid,
    input wire [7:0] take_flags,
    input wire [3:0] take_error,
    input wire [23:0] take_elapsed,
    input wire [10:0] take_count,
    input wire [CONTROL_KEYS-1:0] guide_keys,
    input wire playing,
    input wire game_spawn_long,game_event_start,game_event_end,
    input wire [1:0] game_spawn_type,game_event_type,
    input wire game_spawn_body,game_gesture,
    input wire [15:0] game_event_duration,
    input wire [7:0] game_settings,
    input wire ms_tick,
    input wire note_spawn,
    input wire [CONTROL_KEYS-1:0] spawn_keys,
    input wire [15:0] spawn_delay_ms,
    input wire [1:0] visual_mode,
    input wire [1:0] reference_ratio,reference_phase,
    input wire [15:0] scope_fsr_gain,
    input wire sample_ce,
    input wire signed [15:0] mixed_sample, touch0, touch1, sensor_sample, guitar_sample,
    output wire note_ready,
    output wire [111:0] visual_snapshot,
    output reg overflow,
    output wire hub_R1,
    output wire hub_G1,
    output wire hub_B1,
    output wire hub_R2,
    output wire hub_G2,
    output wire hub_B2,
    output wire hub_A,
    output wire hub_B,
    output wire hub_C,
    output wire hub_D,
    output wire hub_E,
    output reg hub_CK,
    output reg hub_ST,
    output reg hub_OE
);
    localparam integer TOP_Y = 2;
    localparam integer READ_PORTS=ENABLE_GAME ? 2 : 6;
    localparam integer DATA_BITS=CONTROL_KEYS*(ENABLE_GAME ? 3 : 1);
    wire game_session,game_holding;
    wire [23:0] game_score;
    wire [11:0] game_combo,game_best,game_miss;
    wire [1:0] game_judge;
    wire [7:0] game_flash;
    wire [CONTROL_KEYS-1:0] game_flash_keys;
    wire [111:0] game_snapshot;
    generate if(ENABLE_GAME)begin: game
        rhythm_game #(.KEYS(CONTROL_KEYS),.TYPED_NOTES(1)) u_game(
            .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),
            .event_start(game_event_start),.event_end(game_event_end),
            .touch_keys(touch_keys),.event_keys(guide_keys),.event_duration(game_event_duration),
            .event_type(game_event_type),.gesture(game_gesture),
            .settings(game_settings),.session(game_session),.score_bcd(game_score),
            .combo_bcd(game_combo),.best_bcd(game_best),.miss_bcd(game_miss),
            .judgement(game_judge),.flash(game_flash),.flash_keys(game_flash_keys),
            .holding(game_holding),.snapshot(game_snapshot));
    end else begin: no_game
        assign game_session=0;assign game_holding=0;assign game_score=0;
        assign game_combo=0;assign game_best=0;assign game_miss=0;
        assign game_judge=0;assign game_flash=0;assign game_flash_keys=0;assign game_snapshot=0;
    end endgenerate
    localparam integer HIT_Y = 54;
    localparam integer TRAVEL = HIT_Y-TOP_Y;
    localparam integer PHASE_BITS = $clog2(LEAD_MS+1);
    localparam integer DISTANCE_BITS = $clog2((LEAD_MS+1)*(TRAVEL+1));
    localparam integer REMAINDER_BITS = $clog2(LEAD_MS*8);
    localparam [DISTANCE_BITS-1:0] DIV32 = LEAD_MS*32;
    localparam [DISTANCE_BITS-1:0] DIV16 = LEAD_MS*16;
    localparam [DISTANCE_BITS-1:0] DIV8 = LEAD_MS*8;
    localparam [REMAINDER_BITS-1:0] DIV4 = LEAD_MS*4;
    localparam [REMAINDER_BITS-1:0] DIV2 = LEAD_MS*2;
    localparam [REMAINDER_BITS-1:0] DIV1 = LEAD_MS;

    // Circular rows turn a 448-bit parallel shift into one pointer update.
    // Per-row valid bits clear the wrapped row without a second RAM write.
    reg [5:0] head_top;
    wire [63:0] head_valid;
    wire initializing,clear_pending;
    wire [5:0] init_row,clear_row;
    wire clear_write;
    (* syn_ramstyle="block_ram" *) reg [DATA_BITS-1:0] head_memory[0:63];
    reg [DATA_BITS-1:0] head_read_q,write_previous;
    reg head_read_forward;
    wire [DATA_BITS-1:0] head_read_value=head_read_forward ? write_previous : head_read_q;
    reg [PHASE_BITS-1:0] motion_phase;
    wire [31:0] advanced_phase = motion_phase+TRAVEL;
    wire [31:0] wrapped_phase = advanced_phase-LEAD_MS;
    wire scroll = ms_tick && advanced_phase >= LEAD_MS;
    wire [PHASE_BITS-1:0] next_phase = !ms_tick ? motion_phase :
        (scroll ? wrapped_phase[PHASE_BITS-1:0] : advanced_phase[PHASE_BITS-1:0]);
    // Counting future fractional steps places a late event on the correct
    // row for the current scroll phase. Its head reaches HIT_Y after its
    // advertised delay, to the screen's approximately 29ms resolution.
    // The quotient is only 0..52. Pipeline six constant compare/subtract
    // steps as 3+3 bits rather than placing a divider on a 50MHz path.
    // Every pipeline stage accepts another note each clock, with no FIFO
    // limit or backpressure even for a burst of all 128 score events.
    wire [31:0] bounded_delay_full = spawn_delay_ms > LEAD_MS ? LEAD_MS : {16'd0,spawn_delay_ms};
    wire [PHASE_BITS-1:0] bounded_delay = bounded_delay_full[PHASE_BITS-1:0];
    wire [31:0] distance_full = next_phase+bounded_delay*TRAVEL;
    wire [DISTANCE_BITS-1:0] distance_to_hit = distance_full[DISTANCE_BITS-1:0];
    reg [DISTANCE_BITS-1:0] distance_s0;
    reg [REMAINDER_BITS-1:0] remainder_s1;
    reg [2:0] quotient_hi_s1;
    reg [6:0] insert_y_s2;
    reg [DATA_BITS-1:0] keys_s0, keys_s1, keys_s2;
    reg valid_s0, valid_s1, valid_s2;
    reg scroll_s1;
    reg [1:0] scroll_s2;
    reg [DISTANCE_BITS-1:0] upper_remainder;
    reg [REMAINDER_BITS-1:0] lower_remainder;
    reg [2:0] upper_quotient, lower_quotient;
    // Scrolls AFTER the distance snapshot move the new note down too.
    // This includes a scroll on the exact bitmap-commit edge.
    wire [6:0] insert_y = insert_y_s2+scroll_s2+(scroll ? 7'd1 : 7'd0);
    assign note_ready = resetn && playing && (!ENABLE_GAME || (!initializing && !clear_pending));

    always @* begin
        upper_remainder=distance_s0;
        upper_quotient=0;
        if(upper_remainder>=DIV32) begin
            upper_remainder=upper_remainder-DIV32; upper_quotient[2]=1;
        end
        if(upper_remainder>=DIV16) begin
            upper_remainder=upper_remainder-DIV16; upper_quotient[1]=1;
        end
        if(upper_remainder>=DIV8) begin
            upper_remainder=upper_remainder-DIV8; upper_quotient[0]=1;
        end
        lower_remainder=remainder_s1;
        lower_quotient=0;
        if(lower_remainder>=DIV4) begin
            lower_remainder=lower_remainder-DIV4; lower_quotient[2]=1;
        end
        if(lower_remainder>=DIV2) begin
            lower_remainder=lower_remainder-DIV2; lower_quotient[1]=1;
        end
        if(lower_remainder>=DIV1)
            lower_quotient[0]=1;
    end
    // Data registers need no reset: valid bits invalidate stopped/restarted
    // notes and avoid adding the global reset to the arithmetic data path.
    always @(posedge clk) begin
        distance_s0<=distance_to_hit;
        if(ENABLE_GAME)begin
            keys_s0<={(game_spawn_type[1] ? spawn_keys : {CONTROL_KEYS{1'b0}}),
                ((game_spawn_type==1 ? game_settings[6] : game_spawn_type[0]) ? spawn_keys : {CONTROL_KEYS{1'b0}}),
                (game_spawn_body ? {CONTROL_KEYS{1'b0}} : spawn_keys)};
        end else keys_s0<=spawn_keys;
        remainder_s1<=upper_remainder[REMAINDER_BITS-1:0];
        quotient_hi_s1<=upper_quotient;
        keys_s1<=keys_s0;
        insert_y_s2<=HIT_Y[6:0]-{1'b0,quotient_hi_s1,lower_quotient};
        keys_s2<=keys_s1;
    end

    integer row;
    always @(posedge clk) begin
        if (!resetn || !playing) begin
            motion_phase <= 0;
            overflow <= 0;
            valid_s0 <= 0; valid_s1 <= 0; valid_s2 <= 0;
            scroll_s1 <= 0; scroll_s2 <= 0;
        end else begin
            valid_s0 <= note_spawn && spawn_keys != 0 && (!ENABLE_GAME ||
                (!initializing && (!game_spawn_body || game_settings[6])));
            valid_s1 <= valid_s0;
            valid_s2 <= valid_s1;
            scroll_s1 <= scroll;
            scroll_s2 <= {1'b0,scroll_s1}+{1'b0,scroll};
            if (ms_tick)
                motion_phase <= next_phase;
            if (note_spawn && spawn_keys != 0 && spawn_delay_ms > LEAD_MS)
                overflow <= 1; // Unsupported lookahead was clamped, never silent.
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (LEAD_MS < TRAVEL)
            $fatal(1,"hub75e_rhythm_display LEAD_MS must be at least 52ms");
    end
`endif

    localparam [2:0] S_ROW_PREP = 3'd0;
    localparam [2:0] S_PIXEL_PREP = 3'd1;
    localparam [2:0] S_SHIFT = 3'd2;
    localparam [2:0] S_BLANK = 3'd3;
    localparam [2:0] S_SELECT = 3'd4;
    localparam [2:0] S_LATCH_HIGH = 3'd5;
    localparam [2:0] S_LATCH_LOW = 3'd6;
    reg [2:0] state;
    reg [4:0] scan_row, display_row, pwm_phase;
    reg [5:0] column;
    // Twelve keys at exactly five columns each occupy x=0..59. Advance
    // alongside the scan instead of dividing pixel x by five in the shader.
    wire [3:0] pixel_lane;
    wire [2:0] pixel_lane_x;
    generate if(ENABLE_GAME)begin: five_pixel_columns
        reg [3:0] lane;
        reg [2:0] lane_x;
        assign pixel_lane=lane;assign pixel_lane_x=lane_x;
        always @(posedge clk)begin
            if(state==S_ROW_PREP)begin lane<=0;lane_x<=0;end
            else if(state==S_SHIFT)begin
                if(lane_x==4)begin lane<=lane+1'b1;lane_x<=0;end
                else lane_x<=lane_x+1'b1;
            end
        end
    end else begin: legacy_columns
        assign pixel_lane=0;assign pixel_lane_x=0;
    end endgenerate
    reg have_latched;
    reg [DATA_BITS-1:0] upper_notes, lower_notes;
    reg [14:0] upper_pixel, lower_pixel;
    wire [6:0] upper_y = {2'b00,scan_row};
    wire [6:0] lower_y = {2'b00,scan_row}+7'd32;
    wire display_boundary = state == S_LATCH_LOW && scan_row == 31 && pwm_phase == 31;
    reg [1:0] visual_active;
    wire [14:0] visual_upper, visual_lower;
    wire [103:0] visual_telemetry;
    reg status_active;
    // v1 header: reserved=0, dashboard, XY-valid, FFT-valid; followed by
    // active mode, displayed XY ratio/phase, three 6-bit meters, 16x5 FFT.
    assign visual_snapshot=ENABLE_GAME && game_settings[7] && visual_active==0 ?
        (game_snapshot | {80'd0,status_active,31'd0}) : {4'd1,1'b0,status_active,visual_telemetry[103:102],
        visual_active,visual_telemetry[101:0]};
    wire [14:0] status_upper,status_lower;
    // RAM address prefetch: row prep requests x=0, each shift requests x+1.
    // Its result is available for the following S_PIXEL_PREP clock edge.
    wire [5:0] visual_read_x = state == S_ROW_PREP ? 6'd0 :
        (state == S_SHIFT ? column+6'd1 : column);
    generate if (ENABLE_AUDIO_VISUAL) begin: audio_visual
        audio_visualizer u_visualizer (
            .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.display_boundary(display_boundary),
            .service_ce(state==S_BLANK),.visual_mode(visual_active),
            .style_ce(state==S_LATCH_HIGH),
            .reference_ratio(reference_ratio),.reference_phase(reference_phase),
            .scope_fsr_gain(scope_fsr_gain),
            .mixed_sample(mixed_sample),.touch0(touch0),.touch1(touch1),
            .sensor_sample(sensor_sample),.guitar_sample(guitar_sample),
            .pixel_x(visual_read_x),.pixel_row(scan_row),.upper_rgb(visual_upper),.lower_rgb(visual_lower),
            .telemetry(visual_telemetry)
        );
    end else begin: guide_only
        assign visual_upper = 0;
        assign visual_lower = 0;
        assign visual_telemetry = 0;
    end endgenerate
    generate if(ENABLE_STATUS)begin: status_panel
        hub75e_status #(.ENABLE_TAKE_STATUS(ENABLE_TAKE_STATUS)) u_status(
            .clk(clk),.resetn(resetn),.display_boundary(display_boundary),
            .pixel_x(visual_read_x),.pixel_row(scan_row),
            .mode16(touch_mode16),.hold_notes(touch_hold),.pressure_pitch(pressure_pitch),
            .recording(recording),.keys_ready(keys_ready),.physical_keys(physical_keys),
            .note_gates(all_touch_keys),.ir_keys(ir_keys),.timbre(timbre),.analog_mode(analog_mode),
            .effect_mode(effect_mode),.effect_wet(effect_wet),.volume(volume),.master_gain(master_gain),
            .adc_sample(adc_sample),.analog_position(analog_position),.analog_valid(analog_valid),
            .take_flags(take_flags),.take_error(take_error),.take_elapsed(take_elapsed),.take_count(take_count),
            .upper_rgb(status_upper),.lower_rgb(status_lower));
    end else begin: no_status
        assign status_upper=0;assign status_lower=0;
    end endgenerate
    always @(posedge clk) begin
        if (!resetn)begin visual_active <= 0;status_active<=ENABLE_STATUS;end
        else if (display_boundary)begin
            visual_active <= ENABLE_AUDIO_VISUAL ? visual_mode : 2'd0;
            status_active<=ENABLE_STATUS && !playing && !game_session;
        end
    end

    // The first RAM is the insertion read/modify/write port. Six identical
    // copies supply the upper/lower three-row glyph reads in parallel.
    // This trades seven spare BSRAMs for the parallel shift and wide muxes.
    // Prefetch addresses include the next scroll and next scan row, keeping
    // ROW_PREP and the external 133-clock scan exactly cycle-equivalent.
    wire head_write=resetn && playing && valid_s2 && insert_y<64 && (!ENABLE_GAME || !initializing);
    wire [5:0] head_write_address=head_top+insert_y_s2+scroll_s2;
    wire [5:0] wrapped_head=head_top-6'd1;
    wire head_old_valid=head_valid[head_write_address] &&
        !(scroll && head_write_address==wrapped_head);
    wire [DATA_BITS-1:0] head_write_data=((ENABLE_GAME || head_old_valid) ? head_read_value : {DATA_BITS{1'b0}}) | keys_s2;
    // Predict the following cycle's insert address from quotient stage one.
    // The two occurrences of this cycle's scroll cancel in circular space.
    wire [5:0] head_request=head_top+HIT_Y[5:0]-
        {quotient_hi_s1,lower_quotient}+scroll_s1;
    assign clear_write=ENABLE_GAME && resetn && playing && !head_write && (initializing || clear_pending);
    wire memory_write=head_write || clear_write;
    wire [5:0] memory_write_address=head_write ? head_write_address : initializing ? init_row : clear_row;
    wire [DATA_BITS-1:0] memory_write_data=head_write ? head_write_data : {DATA_BITS{1'b0}};
    wire head_collision=memory_write && head_request==memory_write_address;
    wire [5:0] next_head_top=(!resetn || !playing) ? 6'd0 :
        (scroll ? wrapped_head : head_top);
    wire [4:0] next_scan_row=!resetn ? 5'd0 :
        (state==S_LATCH_LOW ? scan_row+5'd1 : scan_row);
    // Legacy mode retains its original valid-bit implementation. Game mode
    // uses idle RAM write slots: initialize all 64 rows, then clear the newly
    // wrapped top row. Note insertion wins over a pending clear. The top ten
    // rows are outside the game lane, so a three-clock deferred clear is hidden.
    generate if(ENABLE_GAME)begin: clear_raster
        reg init_active,pending_clear;
        reg [5:0] init_address,clear_address;
        assign initializing=init_active;assign clear_pending=pending_clear;
        assign init_row=init_address;assign clear_row=clear_address;
        assign head_valid={64{playing && !init_active}};
        always @(posedge clk)begin
            if(!resetn || !playing)begin
                init_active<=1;init_address<=0;pending_clear<=0;clear_address<=0;
            end else begin
                if(clear_write)begin
                    if(init_active)begin
                        init_address<=init_address+1'b1;
                        if(init_address==63)init_active<=0;
                    end else pending_clear<=0;
                end
                if(scroll && !init_active)begin pending_clear<=1;clear_address<=wrapped_head;end
            end
        end
`ifndef SYNTHESIS
        always @(posedge clk)if(resetn && playing && scroll && pending_clear && !clear_write)
            $fatal(1,"game raster millisecond input outran the clear port");
`endif
    end else begin: legacy_valid
        reg [63:0] valid_rows;
        assign head_valid=valid_rows;
        assign initializing=0;assign clear_pending=0;assign init_row=0;assign clear_row=0;
        always @(posedge clk)begin
            if(!resetn || !playing)valid_rows<=0;
            else begin
                if(scroll)valid_rows[wrapped_head]<=0;
                if(head_write)valid_rows[head_write_address]<=1;
            end
        end
    end endgenerate
    always @(posedge clk)begin
        if(!resetn || !playing)head_top<=0;
        else if(scroll)head_top<=wrapped_head;
        if(memory_write)head_memory[memory_write_address]<=memory_write_data;
        if(!head_collision)head_read_q<=head_memory[head_request];
        head_read_forward<=head_collision;
        write_previous<=memory_write_data;
    end
    wire [DATA_BITS-1:0] panel_heads[0:READ_PORTS-1];
    // Reuse each panel RAM's read port during blanking: fetch the next
    // row's FLICK cap first, then its ordinary head/body row. Freeze the
    // circular origin across both reads so a coincident scroll cannot split
    // the two halves. The external scan remains 133 clocks per row.
    reg [5:0] glyph_top;
    always @(posedge clk)if(state==S_SELECT)glyph_top<=next_head_top;
    wire [4:0] glyph_scan_row=ENABLE_GAME && state==S_LATCH_HIGH ? scan_row+5'd1 : next_scan_row;
    genvar head_port;
    generate for(head_port=0;head_port<READ_PORTS;head_port=head_port+1)begin: panel_memories
        localparam integer OFFSET=ENABLE_GAME ? head_port*32 : (head_port<3 ? 0 : 32);
        localparam integer DY=ENABLE_GAME ? 0 : head_port%3;
        (* syn_ramstyle="block_ram" *) reg [DATA_BITS-1:0] memory[0:63];
        reg [DATA_BITS-1:0] q;
        reg valid_q,forward_q;
        wire [6:0] requested_y={2'd0,glyph_scan_row}+OFFSET+
            (ENABLE_GAME && state==S_LATCH_HIGH ? 7'd1 : 7'd0);
        wire [5:0] address=(ENABLE_GAME ? glyph_top : next_head_top)+requested_y[5:0]-DY;
        wire collision=memory_write && address==memory_write_address;
        wire row_survives=head_valid[address] && !(scroll && address==wrapped_head);
        always @(posedge clk)begin
            if(memory_write)memory[memory_write_address]<=memory_write_data;
            if(!collision)q<=memory[address];
            forward_q<=collision;
            valid_q<=resetn && playing && requested_y>=DY && requested_y<=HIT_Y+DY &&
                (collision || row_survives);
        end
        assign panel_heads[head_port]=valid_q ? (forward_q ? write_previous : q) : 7'd0;
    end endgenerate
    wire [DATA_BITS-1:0] upper_glyph,lower_glyph;
    generate if(ENABLE_GAME)begin: thin_heads
        assign upper_glyph=panel_heads[0];assign lower_glyph=panel_heads[1];
    end else begin: old_heads
        assign upper_glyph=panel_heads[0] | panel_heads[1] | panel_heads[2];
        assign lower_glyph=panel_heads[3] | panel_heads[4] | panel_heads[5];
    end endgenerate
    // The lower three pixels remain the timed head; the upper three come
    // from the adjacent row fetched in the preceding blanking slot.
    wire [CONTROL_KEYS-1:0] flick_caps[0:1];
    reg [CONTROL_KEYS-1:0] upper_flick,lower_flick;
    generate if(ENABLE_GAME)begin: stepped_flick
        assign flick_caps[0]=panel_heads[0][CONTROL_KEYS-1:0] &
            panel_heads[0][CONTROL_KEYS*2-1:CONTROL_KEYS] & panel_heads[0][CONTROL_KEYS*3-1:CONTROL_KEYS*2];
        assign flick_caps[1]=panel_heads[1][CONTROL_KEYS-1:0] &
            panel_heads[1][CONTROL_KEYS*2-1:CONTROL_KEYS] & panel_heads[1][CONTROL_KEYS*3-1:CONTROL_KEYS*2];
    end else begin: no_flick_caps
        assign flick_caps[0]=0;assign flick_caps[1]=0;
    end endgenerate
`ifndef SYNTHESIS
    // Preserve the logical-row debug view; this is absent from hardware.
    wire [DATA_BITS-1:0] note_rows[0:63];
    genvar debug_row;
    generate for(debug_row=0;debug_row<64;debug_row=debug_row+1)begin: debug_heads
        wire [5:0] address=head_top+debug_row;
        assign note_rows[debug_row]=head_valid[address] ? head_memory[address] : 7'd0;
    end endgenerate
`endif

    // Legacy seven-lane and current twelve-lane layouts share the bitmap.
    // above avoids duplicating its per-note timers for the two panel halves.
    function [14:0] pixel_rgb;
        input [5:0] x;
        input [6:0] y;
        input [DATA_BITS-1:0] notes;
        input [3:0] scanned_lane;
        input [2:0] scanned_lane_x;
        input [CONTROL_KEYS-1:0] flick_cap;
        reg [4:0] r, g, b;
        reg [5:0] relative_x;
        reg [3:0] lane;
        reg [2:0] lane_x;
        begin
            r = 0; g = 0; b = 0;
            relative_x = x-(ENABLE_GAME ? 6'd0 : CONTROL_KEYS==12 ? 6'd8 : 6'd4);
            lane = CONTROL_KEYS==12 ? {1'b0,relative_x[5:2]} : {1'b0,relative_x[5:3]};
            lane_x = CONTROL_KEYS==12 ? {1'b0,relative_x[1:0]} : relative_x[2:0];
            if(ENABLE_GAME)begin lane=scanned_lane;lane_x=scanned_lane_x;end
            if (x >= (ENABLE_GAME ? 0 : CONTROL_KEYS==12 ? 8 : 4) && x < (ENABLE_GAME ? 60 : CONTROL_KEYS==12 ? 56 : 60)) begin
                r = 1; g = 1; b = 2;
                if (lane_x == 0) begin r = 2; g = 3; b = 5; end
                if (y == HIT_Y || (!ENABLE_GAME && y == HIT_Y+1)) begin
                    r = 8; g = 8; b = 8;
                    if (playing && guide_keys[lane]) begin r = 31; g = 18; b = 0; end
                end
                if (y >= (ENABLE_GAME ? 60 : HIT_Y+4) && (ENABLE_GAME ||
                    (lane_x >= (CONTROL_KEYS==12 ? 1 : 2) && lane_x < (CONTROL_KEYS==12 ? 3 : 7)))) begin
                    r = 2; g = 3; b = 5;
                    if(ENABLE_GAME)begin r=0;g=lane[0] ? 5 : 8;b=lane[0] ? 14 : 22;end
                    if (touch_keys[lane]) begin
                        r = 0; g = 25; b = 6;
                        if (playing && guide_keys[lane]) begin r = 31; g = 25; b = 0; end
                    end
                end
                if (playing && (!ENABLE_GAME || y>=8) &&
                    (notes[lane] || (ENABLE_GAME && notes[lane+CONTROL_KEYS] && !notes[lane+CONTROL_KEYS*2])) &&
                    (!ENABLE_GAME || !notes[lane+CONTROL_KEYS*2] || !notes[lane+CONTROL_KEYS] || lane_x<=2) &&
                    (ENABLE_GAME || (lane_x >= (CONTROL_KEYS==12 ? 1 : 2) && lane_x < (CONTROL_KEYS==12 ? 3 : 7)))) begin
                    r = 0; g = 24; b = 31;
                    if(ENABLE_GAME)begin
                        if(!notes[lane])begin r=0;g=10;b=24;end
                        if(notes[lane+CONTROL_KEYS*2])begin
                            if(notes[lane+CONTROL_KEYS])begin r=31;g=4;b=24;end
                            else begin r=31;g=25;b=0;end
                        end
                        if(game_holding && guide_keys[lane] && notes[lane+CONTROL_KEYS] && !notes[lane+CONTROL_KEYS*2])begin r=31;g=25;b=0;end
                    end
                end
                if(ENABLE_GAME && playing && y>=8 && flick_cap[lane] && lane_x>=2)begin r=31;g=4;b=24;end
            end
            // Sixteen 3-pixel indicators along the bottom of the guide page.
            // Keeps the existing seven score lanes and all graph pages intact.
            if(!ENABLE_GAME && touch_mode16===1'b1 && y>=60)begin
                r=0;g=0;b=0;
                if(x[1:0]!=0)begin
                    r=2;g=3;b=5;
                    if(all_touch_keys[x[5:2]])begin r=0;g=25;b=12;end
                end
            end
            if(ENABLE_GAME && game_session)begin
                if(y>=48 && y<=54 && x<60 && game_settings[5] &&
                    game_flash!=0 && game_flash_keys[lane])begin
                    if(game_judge==3)begin r=game_flash[7:3];g=0;b=1;end
                    else begin r=game_flash[7:3];g=game_flash[7:3];b=0;end
                end
                if(game_holding && guide_keys[lane] && y==54 && x<60)begin r=31;g=25;b=0;end
            end
            pixel_rgb = {r,g,b};
        end
    endfunction

    // One-bit synchronous font ROM replaces a combinational glyph shifter.
    wire [5:0] hud_x=visual_read_x;
    wire [3:0] hud_digit;
    wire [1:0] combo_digit=2'd2-hud_x[3:2];
    wire [2:0] score_digit=3'd7-hud_x[4:2];
    // Horizontal red score at the upper right matches the reference drawing;
    // the yellow combo remains at the upper left, outside the falling field.
    assign hud_digit=hud_x>=40 ? game_score[score_digit*4+:4] :
        hud_x<12 ? game_combo[combo_digit*4+:4] : 4'd15;
    // Gowin drops scalar reg arrays initialized by readmemh/readmemb.
    // Keep an explicit one-bit vector; gate-level font probes cover all512
    // addresses (the old scalar declaration produced a constant-zero net).
    (* syn_romstyle="block_rom" *) reg [0:0] hud_font[0:511];
    reg hud_bit;
    initial $readmemb("src/rhythm_font.hex",hud_font);
    always @(posedge clk)hud_bit<=hud_font[{hud_digit,scan_row[2:0],hud_x[1:0]}][0];
    (* syn_keep=1 *) wire [14:0] hud_rgb=!hud_bit ? 15'd0 : column>=40 ? {5'd31,5'd3,5'd0} : {5'd31,5'd20,5'd0};
    // Keep the layer values explicit before the pixel register.
    (* syn_keep=1 *) wire [14:0] rhythm_upper=pixel_rgb(column,upper_y,upper_notes,pixel_lane,pixel_lane_x,upper_flick);
    (* syn_keep=1 *) wire [14:0] rhythm_lower=pixel_rgb(column,lower_y,lower_notes,pixel_lane,pixel_lane_x,lower_flick);
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_ROW_PREP;
            scan_row <= 0;
            display_row <= 0;
            pwm_phase <= 0;
            column <= 0;
            // OE stays blank until a complete row has been prepared/shifted.
            have_latched <= 0;
            hub_CK <= 0;
            hub_ST <= 0;
            hub_OE <= 1;
        end else begin
            case (state)
                S_ROW_PREP: begin
                    upper_notes <= upper_glyph;
                    lower_notes <= lower_glyph;
                    column <= 0;
                    hub_CK <= 0;
                    hub_ST <= 0;
                    hub_OE <= !have_latched;
                    state <= S_PIXEL_PREP;
                end
                S_PIXEL_PREP: begin
                    hub_CK <= 0;
                    upper_pixel <= visual_active ? visual_upper : status_active ? status_upper : ENABLE_GAME && game_session && upper_y<8 ? hud_rgb : rhythm_upper;
                    lower_pixel <= visual_active ? visual_lower : status_active ? status_lower : rhythm_lower;
                    state <= S_SHIFT;
                end
                S_SHIFT: begin
                    hub_CK <= 1;
                    if (column == 63)
                        state <= S_BLANK;
                    else begin
                        column <= column+1'b1;
                        state <= S_PIXEL_PREP;
                    end
                end
                S_BLANK: begin
                    hub_CK <= 0;
                    hub_OE <= 1;
                    state <= S_SELECT;
                end
                S_SELECT: begin
                    display_row <= scan_row;
                    state <= S_LATCH_HIGH;
                end
                S_LATCH_HIGH: begin
                    hub_ST <= 1;
                    have_latched <= 1;
                    state <= S_LATCH_LOW;
                end
                S_LATCH_LOW: begin
                    upper_flick <= flick_caps[0];
                    lower_flick <= flick_caps[1];
                    hub_ST <= 0;
                    scan_row <= scan_row+1'b1;
                    if (scan_row == 31)
                        pwm_phase <= pwm_phase+1'b1;
                    state <= S_ROW_PREP;
                end
                default: begin
                    state <= S_ROW_PREP;
                    hub_CK <= 0;
                    hub_ST <= 0;
                    hub_OE <= 1;
                    have_latched <= 0;
                end
            endcase
        end
    end
    assign {hub_E,hub_D,hub_C,hub_B,hub_A} = display_row;
    assign hub_R1 = upper_pixel[14:10] > pwm_phase;
    assign hub_G1 = upper_pixel[9:5] > pwm_phase;
    assign hub_B1 = upper_pixel[4:0] > pwm_phase;
    assign hub_R2 = lower_pixel[14:10] > pwm_phase;
    assign hub_G2 = lower_pixel[9:5] > pwm_phase;
    assign hub_B2 = lower_pixel[4:0] > pwm_phase;
endmodule
