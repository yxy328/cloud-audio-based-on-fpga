`timescale 1ns/1ps
// Seven notes share a smooth Q0.16 frequency ratio. DDS phases are untouched.
// Full scale is bypassed so volume mode retains the exact original pitches.
// One shared, pipelined multiplier updates the seven steps round-robin.
// Registered select -> two 16x16 products -> registered sum/output bank.
// One scan per audio frame avoids switching the shared DSPs while idle.
// Launch AFTER sample_ce so the newly slewed ratio is used for the next frame.
module fsr_pitch_scaler #(
    parameter [223:0] NOTE_INCREMENTS = {
        32'd43442435, 32'd38702809, 32'd34480283, 32'd30718440,
        32'd28994347, 32'd25831026, 32'd23012828
    }
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire [15:0] pitch_ratio,
    input wire [223:0] note_increments,
    output reg [255:0] phase_increments
);
    reg [2:0] select_index, selected_index, product_index;
    reg [31:0] selected_base, product_base;
    reg [15:0] selected_ratio;
    reg [31:0] product_low, product_high;
    reg product_full;
    reg [1:0] valid_pipe;
    reg scan_active;
    always @(posedge clk) begin
        if (!resetn) begin
            select_index<=0; selected_index<=0; product_index<=0;
            selected_base<=0; selected_ratio<=16'hffff; product_base<=0;
            product_low<=0; product_high<=0; product_full<=1; valid_pipe<=0;
            scan_active<=0;
            phase_increments<={32'd0,NOTE_INCREMENTS};
        end else begin
            if (scan_active) begin
                if (select_index==6) scan_active<=0;
                else select_index<=select_index+1'b1;
                selected_index<=select_index;
                selected_base<=note_increments[select_index*32 +: 32];
                selected_ratio<=pitch_ratio;
            end else if (sample_ce) begin
                scan_active<=1;
                select_index<=0;
            end
            if (valid_pipe[0]) begin
                product_index<=selected_index;
                product_base<=selected_base;
                product_full<=selected_ratio==16'hffff;
                product_low<=selected_base[15:0]*selected_ratio;
                product_high<=selected_base[31:16]*selected_ratio;
            end
            valid_pipe<={valid_pipe[0],scan_active};
            if (valid_pipe[1])
                phase_increments[product_index*32 +: 32] <= product_full ? product_base :
                    product_high + {16'd0,product_low[31:16]};
        end
    end
endmodule
