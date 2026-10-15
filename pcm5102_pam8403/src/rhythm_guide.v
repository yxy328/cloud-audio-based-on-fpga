`timescale 1ns/1ps
// Seven-lane pixel renderer for the existing 64x64 HUB75E panel.
// Keep RGB in the panel's native five-bit format. Render the upper/lower
// row pair separately, then register both results before the scan shift edge.
//
// A sequencer submits each note before its hit time:
//   note_spawn=1, spawn_keys=key mask, spawn_delay_ms=time until hit.
// Normally submit at LEAD_MS (1500ms). Shorter delays start partway down;
// longer delays wait above the screen. Consecutive equal notes remain separate.
// guide_keys marks the currently due note and does not create a falling note.
// This lets the current-only song interface show a target without pretending
// to know future notes. A later lookahead reader can drive note_spawn.
module rhythm_guide #(
    parameter integer PANEL_WIDTH = 64,
    parameter integer PANEL_HEIGHT = 64,
    parameter integer TOP_Y = 2,
    parameter integer HIT_Y = 54,
    parameter integer LEAD_MS = 1500, // Must be >= HIT_Y-TOP_Y.
    parameter integer HIT_WINDOW_MS = 100,
    parameter integer NOTE_SLOTS = 8
) (
    input wire clk,
    input wire resetn,
    input wire [8:0] pixel_x,
    input wire [6:0] pixel_y,
    input wire [6:0] guide_keys,
    input wire [6:0] touch_keys,
    input wire playing,
    input wire ms_tick,
    input wire note_spawn,
    input wire [6:0] spawn_keys,
    input wire [15:0] spawn_delay_ms,
    output wire note_ready,
    output reg note_overflow,
    output reg [4:0] red,
    output reg [4:0] green,
    output reg [4:0] blue
);
    localparam integer LEFT_X = 4;
    localparam integer LANE_WIDTH = (PANEL_WIDTH-8)/7;
    localparam integer RIGHT_X = LEFT_X+7*LANE_WIDTH;
    localparam integer TRAVEL = HIT_Y-TOP_Y;

    reg [NOTE_SLOTS-1:0] used;
    reg [6:0] keys [0:NOTE_SLOTS-1];
    reg [6:0] note_y [0:NOTE_SLOTS-1];
    reg [15:0] remaining_ms [0:NOTE_SLOTS-1];
    reg [15:0] wait_ms [0:NOTE_SLOTS-1];
    reg [15:0] tail_ms [0:NOTE_SLOTS-1];
    reg [31:0] phase [0:NOTE_SLOTS-1];
    reg free_found;
    integer free_slot;
    integer slot;
    integer draw_slot;
    integer lane;
    integer lane_x;
    reg [31:0] initial_progress;
    reg [6:0] initial_y;
    reg [31:0] initial_phase;
    reg [15:0] initial_wait;
    reg note_pixel;

    // Only the spawn path uses constant division/modulo. During playback
    // each slot advances with a fractional pixel accumulator once per ms.
    always @* begin
        initial_progress = 0;
        initial_y = TOP_Y;
        initial_phase = 0;
        initial_wait = 0;
        if (spawn_delay_ms > LEAD_MS)
            initial_wait = spawn_delay_ms-LEAD_MS;
        else begin
            initial_progress = (LEAD_MS-spawn_delay_ms)*TRAVEL;
            initial_y = TOP_Y+initial_progress/LEAD_MS;
            initial_phase = initial_progress%LEAD_MS;
        end
        free_found = 0;
        free_slot = 0;
        for (slot=0; slot<NOTE_SLOTS; slot=slot+1) begin
            if (!used[slot] && !free_found) begin
                free_found = 1;
                free_slot = slot;
            end
        end
    end
    assign note_ready = playing && free_found;

    integer update_slot;
    always @(posedge clk) begin
        if (!resetn || !playing) begin
            used <= 0;
            note_overflow <= 0;
            for (update_slot=0; update_slot<NOTE_SLOTS; update_slot=update_slot+1) begin
                keys[update_slot] <= 0;
                note_y[update_slot] <= TOP_Y;
                remaining_ms[update_slot] <= 0;
                wait_ms[update_slot] <= 0;
                tail_ms[update_slot] <= 0;
                phase[update_slot] <= 0;
            end
        end else begin
            if (ms_tick) begin
                for (update_slot=0; update_slot<NOTE_SLOTS; update_slot=update_slot+1) begin
                    if (used[update_slot]) begin
                        if (remaining_ms[update_slot] != 0) begin
                            remaining_ms[update_slot] <= remaining_ms[update_slot]-1'b1;
                            if (wait_ms[update_slot] != 0)
                                wait_ms[update_slot] <= wait_ms[update_slot]-1'b1;
                            else if (remaining_ms[update_slot] == 1) begin
                                note_y[update_slot] <= HIT_Y;
                                phase[update_slot] <= 0;
                            end else if (phase[update_slot]+TRAVEL >= LEAD_MS) begin
                                phase[update_slot] <= phase[update_slot]+TRAVEL-LEAD_MS;
                                if (note_y[update_slot] < HIT_Y)
                                    note_y[update_slot] <= note_y[update_slot]+1'b1;
                            end else
                                phase[update_slot] <= phase[update_slot]+TRAVEL;
                        end else if (tail_ms[update_slot] <= 1)
                            used[update_slot] <= 0;
                        else
                            tail_ms[update_slot] <= tail_ms[update_slot]-1'b1;
                    end
                end
            end
            if (note_spawn && spawn_keys != 0) begin
                if (free_found) begin
                    used[free_slot] <= 1;
                    keys[free_slot] <= spawn_keys;
                    note_y[free_slot] <= initial_y;
                    remaining_ms[free_slot] <= spawn_delay_ms;
                    wait_ms[free_slot] <= initial_wait;
                    tail_ms[free_slot] <= HIT_WINDOW_MS;
                    phase[free_slot] <= initial_phase;
                end else
                    note_overflow <= 1;
            end
        end
    end

    // Lanes 1..7 run from left to right. Notes are cyan; due targets are
    // amber, pressed lanes green, and a pressed current target is white.
    // Three-pixel notes and two-pixel separators remain legible on 64x64.
    always @* begin
        red = 0;
        green = 0;
        blue = 0;
        lane = 0;
        lane_x = 0;
        note_pixel = 0;
        if (pixel_x >= LEFT_X && pixel_x < RIGHT_X && pixel_y < PANEL_HEIGHT) begin
            lane = (pixel_x-LEFT_X)/LANE_WIDTH;
            lane_x = (pixel_x-LEFT_X)%LANE_WIDTH;
            red = 1;
            green = 1;
            blue = 2;
            if (lane_x == 0) begin
                red = 2;
                green = 3;
                blue = 5;
            end
            if (pixel_y == HIT_Y || pixel_y == HIT_Y+1) begin
                red = 8;
                green = 8;
                blue = 8;
                if (playing && guide_keys[lane]) begin
                    red = 31;
                    green = 18;
                    blue = 0;
                end
            end
            if (pixel_y >= HIT_Y+4 && lane_x >= 2 && lane_x < LANE_WIDTH-1) begin
                red = 2;
                green = 3;
                blue = 5;
                if (touch_keys[lane]) begin
                    red = 0;
                    green = 25;
                    blue = 6;
                    if (playing && guide_keys[lane]) begin
                        red = 31;
                        green = 31;
                        blue = 31;
                    end
                end
            end
            for (draw_slot=0; draw_slot<NOTE_SLOTS; draw_slot=draw_slot+1) begin
                if (playing && used[draw_slot] && wait_ms[draw_slot] == 0 &&
                    keys[draw_slot][lane] && lane_x >= 2 && lane_x < LANE_WIDTH-1 &&
                    pixel_y >= note_y[draw_slot] && pixel_y < note_y[draw_slot]+3)
                    note_pixel = 1;
            end
            if (note_pixel) begin
                red = 0;
                green = 24;
                blue = 31;
            end
        end
    end
endmodule
