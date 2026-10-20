`timescale 1ns/1ps
// 64x64, 1/32-scan HUB75E rhythm display. Every register uses clk; hub_CK
// is an output waveform, never an internal clock. RGB has one full 50MHz
// cycle of setup before each 25MHz external shift-clock rising edge.
//
// A 64x7 bitmap holds note heads rather than a per-note register queue.
// Notes closer than one screen pixel share a row and OR their key masks.
// This accepts all 128 score events even at 1ms spacing without consuming
// 128 copies of a timer/position accumulator or blocking the sequencer.
module hub75e_rhythm_display #(
    parameter integer LEAD_MS = 1500,
    parameter integer ENABLE_AUDIO_VISUAL = 0,
    parameter integer ENABLE_STATUS = 0,
    parameter integer ENABLE_TAKE_STATUS = 0
) (
    input wire clk,
    input wire resetn,
    input wire [6:0] touch_keys,
    input wire touch_mode16,
    input wire [15:0] all_touch_keys,
    input wire [15:0] physical_keys,
    input wire [7:0] ir_keys,
    input wire touch_hold,pressure_pitch,recording,keys_ready,
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
    input wire [6:0] guide_keys,
    input wire playing,
    input wire ms_tick,
    input wire note_spawn,
    input wire [6:0] spawn_keys,
    input wire [15:0] spawn_delay_ms,
    input wire [1:0] visual_mode,
    input wire [1:0] reference_ratio,reference_phase,
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

    reg [6:0] note_rows [0:63];
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
    reg [6:0] keys_s0, keys_s1, keys_s2;
    reg valid_s0, valid_s1, valid_s2;
    reg scroll_s1;
    reg [1:0] scroll_s2;
    reg [DISTANCE_BITS-1:0] upper_remainder;
    reg [REMAINDER_BITS-1:0] lower_remainder;
    reg [2:0] upper_quotient, lower_quotient;
    // Scrolls AFTER the distance snapshot move the new note down too.
    // This includes a scroll on the exact bitmap-commit edge.
    wire [6:0] insert_y = insert_y_s2+scroll_s2+(scroll ? 7'd1 : 7'd0);
    assign note_ready = resetn && playing;

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
        keys_s0<=spawn_keys;
        remainder_s1<=upper_remainder[REMAINDER_BITS-1:0];
        quotient_hi_s1<=upper_quotient;
        keys_s1<=keys_s0;
        insert_y_s2<=HIT_Y[6:0]-{1'b0,quotient_hi_s1,lower_quotient};
        keys_s2<=keys_s1;
    end

    reg was_playing;
    always @(posedge clk)begin
        if(!resetn)was_playing<=0;else was_playing<=playing;
    end
    integer row;
    always @(posedge clk) begin
        if (!resetn || !playing) begin
            motion_phase <= 0;
            overflow <= 0;
            valid_s0 <= 0; valid_s1 <= 0; valid_s2 <= 0;
            scroll_s1 <= 0; scroll_s2 <= 0;
            // Nothing writes rows while stopped; clear once on stop/reset.
            if(!resetn || was_playing)
                for (row=0; row<64; row=row+1)note_rows[row] <= 0;
        end else begin
            valid_s0 <= note_spawn && spawn_keys != 0;
            valid_s1 <= valid_s0;
            valid_s2 <= valid_s1;
            scroll_s1 <= scroll;
            scroll_s2 <= {1'b0,scroll_s1}+{1'b0,scroll};
            if (ms_tick)
                motion_phase <= next_phase;
            if (note_spawn && spawn_keys != 0 && spawn_delay_ms > LEAD_MS)
                overflow <= 1; // Unsupported lookahead was clamped, never silent.
            if (scroll || valid_s2) begin
                for (row=0; row<64; row=row+1) begin
                    if (scroll) begin
                        if (row == 0)
                            note_rows[row] <= 0;
                        else
                            note_rows[row] <= note_rows[row-1];
                    end
                    if (valid_s2 && insert_y == row) begin
                        if (scroll) begin
                            if (row == 0)
                                note_rows[row] <= keys_s2;
                            else
                                note_rows[row] <= note_rows[row-1] | keys_s2;
                        end else
                            note_rows[row] <= note_rows[row] | keys_s2;
                    end
                end
            end
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
    reg have_latched;
    reg [6:0] upper_notes, lower_notes;
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
    assign visual_snapshot={4'd1,1'b0,status_active,visual_telemetry[103:102],
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
            .reference_ratio(reference_ratio),.reference_phase(reference_phase),
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
            status_active<=ENABLE_STATUS && !playing;
        end
    end

    // Capture the row masks once per row scan. Only heads through HIT_Y
    // are drawn; their three-pixel glyph can extend through HIT_Y+2.
    // Form each three-pixel glyph with fixed wiring BEFORE selecting a row.
    // Two 32-row selections replace six independently addressed selections.
    // These are combinational wires: a scroll/insert on the capture edge has
    // exactly the same visibility as the original bitmap reads.
    wire [6:0] glyph_rows [0:63];
    genvar glyph_y;
    generate for(glyph_y=0;glyph_y<64;glyph_y=glyph_y+1)begin: glyph
        wire [6:0] head,previous,prior;
        if(glyph_y<=HIT_Y)begin: head_valid
            assign head=note_rows[glyph_y];
        end else begin: head_empty
            assign head=0;
        end
        if(glyph_y>=1 && glyph_y<=HIT_Y+1)begin: previous_valid
            assign previous=note_rows[glyph_y-1];
        end else begin: previous_empty
            assign previous=0;
        end
        if(glyph_y>=2 && glyph_y<=HIT_Y+2)begin: prior_valid
            assign prior=note_rows[glyph_y-2];
        end else begin: prior_empty
            assign prior=0;
        end
        assign glyph_rows[glyph_y]=head | previous | prior;
    end endgenerate

    // Same seven-lane layout/colors as rhythm_guide.v. Sharing the bitmap
    // above avoids duplicating its per-note timers for the two panel halves.
    function [14:0] pixel_rgb;
        input [5:0] x;
        input [6:0] y;
        input [6:0] notes;
        reg [4:0] r, g, b;
        reg [5:0] relative_x;
        reg [2:0] lane;
        reg [2:0] lane_x;
        begin
            r = 0; g = 0; b = 0;
            relative_x = x-6'd4;
            lane = relative_x[5:3];
            lane_x = relative_x[2:0];
            if (x >= 4 && x < 60) begin
                r = 1; g = 1; b = 2;
                if (lane_x == 0) begin r = 2; g = 3; b = 5; end
                if (y == HIT_Y || y == HIT_Y+1) begin
                    r = 8; g = 8; b = 8;
                    if (playing && guide_keys[lane]) begin r = 31; g = 18; b = 0; end
                end
                if (y >= HIT_Y+4 && lane_x >= 2 && lane_x < 7) begin
                    r = 2; g = 3; b = 5;
                    if (touch_keys[lane]) begin
                        r = 0; g = 25; b = 6;
                        if (playing && guide_keys[lane]) begin r = 31; g = 31; b = 31; end
                    end
                end
                if (playing && notes[lane] && lane_x >= 2 && lane_x < 7) begin
                    r = 0; g = 24; b = 31;
                end
            end
            // Sixteen 3-pixel indicators along the bottom of the guide page.
            // Keeps the existing seven score lanes and all graph pages intact.
            if(touch_mode16===1'b1 && y>=60)begin
                r=0;g=0;b=0;
                if(x[1:0]!=0)begin
                    r=2;g=3;b=5;
                    if(all_touch_keys[x[5:2]])begin r=0;g=25;b=12;end
                end
            end
            pixel_rgb = {r,g,b};
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_ROW_PREP;
            scan_row <= 0;
            display_row <= 0;
            pwm_phase <= 0;
            column <= 0;
            have_latched <= 0;
            upper_notes <= 0;
            lower_notes <= 0;
            upper_pixel <= 0;
            lower_pixel <= 0;
            hub_CK <= 0;
            hub_ST <= 0;
            hub_OE <= 1;
        end else begin
            case (state)
                S_ROW_PREP: begin
                    upper_notes <= glyph_rows[{1'b0,scan_row}];
                    lower_notes <= glyph_rows[{1'b1,scan_row}];
                    column <= 0;
                    hub_CK <= 0;
                    hub_ST <= 0;
                    hub_OE <= !have_latched;
                    state <= S_PIXEL_PREP;
                end
                S_PIXEL_PREP: begin
                    hub_CK <= 0;
                    upper_pixel <= visual_active ? visual_upper : status_active ? status_upper : pixel_rgb(column, upper_y, upper_notes);
                    lower_pixel <= visual_active ? visual_lower : status_active ? status_lower : pixel_rgb(column, lower_y, lower_notes);
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
