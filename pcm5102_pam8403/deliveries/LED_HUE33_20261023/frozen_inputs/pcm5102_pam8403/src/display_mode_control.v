`timescale 1ns/1ps
// Debounced S2: a short release restarts the score outside XY; in XY it
// cycles reference presets and the live delayed mix. A long hold switches
// the display once, without restarting the score on either edge.
module display_mode_control #(
    parameter integer HOLD_FRAMES = 48828
) (
    input wire clk, resetn, frame_ce, button_level,
    input wire xy_write,
    input wire [1:0] xy_ratio, xy_phase,
    input wire visual_write,
    input wire [1:0] remote_mode,
    output reg restart,
    output reg [1:0] visual_mode,
    output reg [1:0] reference_ratio, reference_phase
);
    localparam integer COUNT_BITS = HOLD_FRAMES < 2 ? 1 : $clog2(HOLD_FRAMES);
    reg [COUNT_BITS-1:0] held_frames;
    reg previous_level, long_fired;
    always @(posedge clk) begin
        if (!resetn) begin
            held_frames <= 0;
            previous_level <= 0;
            long_fired <= 0;
            restart <= 0;
            visual_mode <= 0;
            reference_ratio <= 2;
            reference_phase <= 0;
        end else begin
            previous_level <= button_level;
            restart <= 0;
            if(visual_write) begin
                visual_mode<=remote_mode;
                held_frames<=0;
                // A held local key cannot undo the remote command on release.
                long_fired<=button_level;
            end else if (!button_level) begin
                held_frames <= 0;
                long_fired <= 0;
                if (previous_level && !long_fired) begin
                    if(visual_mode==2) begin
                        // eight -> multi-loop -> circle -> ellipse -> line -> mix
                        if(reference_ratio==2) begin reference_ratio<=3;reference_phase<=0;end
                        else if(reference_ratio==3) begin reference_ratio<=1;reference_phase<=2;end
                        else if(reference_ratio==1 && reference_phase==2) reference_phase<=1;
                        else if(reference_ratio==1 && reference_phase!=0) reference_phase<=0;
                        else if(reference_ratio==1) begin reference_ratio<=0;reference_phase<=0;end
                        else begin reference_ratio<=2;reference_phase<=0;end
                    end else restart <= 1;
                end
            end else if (frame_ce && !long_fired) begin
                if (held_frames == HOLD_FRAMES-1) begin
                    visual_mode <= visual_mode+2'd1;
                    long_fired <= 1;
                end else
                    held_frames <= held_frames+1'b1;
            end
            // An acknowledged remote command wins over a simultaneous release.
            if(xy_write) begin
                reference_ratio<=xy_ratio;
                reference_phase<=xy_phase;
            end
        end
    end
`ifndef SYNTHESIS
    initial if (HOLD_FRAMES < 1) $fatal(1,"HOLD_FRAMES must be positive");
`endif
endmodule
