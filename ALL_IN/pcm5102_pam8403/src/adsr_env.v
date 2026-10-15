`timescale 1ns/1ps
// Linear ADSR in the audio sample domain, gain=0..65535 (unsigned Q0.16).
// A short hardware division runs only when a segment starts (16 clk cycles).
// Each sample then uses add/subtract and a remainder accumulator. Segment
// endpoints are exact even when the starting gain is low or on retrigger.
module adsr_env #(
    parameter ATTACK_SAMPLES = 98,
    parameter DECAY_SAMPLES = 3906,
    parameter [15:0] SUSTAIN_LEVEL = 16'd39321,
    parameter RELEASE_SAMPLES = 24414
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire gate,
    output reg [15:0] gain,
    output reg [2:0] state,
    output wire active
);
    localparam [2:0] IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2,
                     SUSTAIN=3'd3, RELEASE=3'd4;
    localparam [31:0] A_TICKS = (ATTACK_SAMPLES < 1) ? 1 : ATTACK_SAMPLES;
    localparam [31:0] D_TICKS = (DECAY_SAMPLES < 1) ? 1 : DECAY_SAMPLES;
    localparam [31:0] R_TICKS = (RELEASE_SAMPLES < 1) ? 1 : RELEASE_SAMPLES;
    reg gate_seen;
    reg [15:0] target_gain;
    reg rising;
    reg [31:0] segment_ticks;
    reg [31:0] ticks_left;
    reg [15:0] step_size;
    reg [31:0] step_remainder;
    reg [32:0] slope_error;
    reg dividing;
    reg [4:0] divide_left;
    reg [15:0] quotient;
    reg [32:0] remainder;

    wire [32:0] shifted_remainder = {remainder[31:0],quotient[15]};
    wire divide_one = shifted_remainder >= {1'b0,segment_ticks};
    wire [32:0] next_remainder = divide_one
        ? shifted_remainder - {1'b0,segment_ticks} : shifted_remainder;
    wire [15:0] next_quotient = {quotient[14:0],divide_one};
    wire [32:0] next_error = slope_error + {1'b0,step_remainder};
    wire extra_step = next_error >= {1'b0,segment_ticks};
    wire [16:0] delta = {1'b0,step_size} + extra_step;
    // Preserve the original low 16 bits without an implicit width truncation.
    wire [16:0] next_gain_rise = {1'b0,gain} + delta;
    wire [16:0] next_gain_fall = {1'b0,gain} - delta;

    assign active = state != IDLE;

    // All callers explicitly provide the starting level, including a
    // boundary whose final gain is being committed on the current edge.
    task start_segment;
        input [2:0] next_state;
        input [15:0] start_gain;
        input [15:0] end_gain;
        input [31:0] length;
        begin
            state <= next_state;
            target_gain <= end_gain;
            rising <= end_gain >= start_gain;
            segment_ticks <= length;
            ticks_left <= length;
            quotient <= (end_gain >= start_gain)
                ? end_gain - start_gain : start_gain - end_gain;
            remainder <= 33'd0;
            divide_left <= 5'd15;
            dividing <= 1'b1;
            step_size <= 16'd0;
            step_remainder <= 32'd0;
            slope_error <= 33'd0;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            gain <= 16'd0;
            state <= IDLE;
            gate_seen <= 1'b0;
            target_gain <= 16'd0;
            rising <= 1'b0;
            segment_ticks <= 32'd1;
            ticks_left <= 32'd0;
            step_size <= 16'd0;
            step_remainder <= 32'd0;
            slope_error <= 33'd0;
            dividing <= 1'b0;
            divide_left <= 5'd0;
            quotient <= 16'd0;
            remainder <= 33'd0;
        end else begin
            gate_seen <= gate;
            // Gate events have priority over an in-flight division/ramp.
            // Neither event resets gain: release and retrigger are continuous.
            if (gate && !gate_seen) begin
                start_segment(ATTACK,gain,16'hffff,A_TICKS);
            end else if (!gate && gate_seen) begin
                if (gain == 16'd0) begin
                    state <= IDLE;
                    dividing <= 1'b0;
                    ticks_left <= 32'd0;
                end else begin
                    start_segment(RELEASE,gain,16'd0,R_TICKS);
                end
            end else if (dividing) begin
                quotient <= next_quotient;
                remainder <= next_remainder;
                if (divide_left == 0) begin
                    step_size <= next_quotient;
                    step_remainder <= next_remainder[31:0];
                    dividing <= 1'b0;
                end else begin
                    divide_left <= divide_left - 1'b1;
                end
            end else if (sample_ce) begin
                case (state)
                    ATTACK, DECAY, RELEASE: begin
                        if (ticks_left <= 1) begin
                            gain <= target_gain;
                            ticks_left <= 32'd0;
                            slope_error <= 33'd0;
                            case (state)
                                ATTACK: start_segment(DECAY,16'hffff,SUSTAIN_LEVEL,D_TICKS);
                                DECAY: state <= SUSTAIN;
                                RELEASE: state <= IDLE;
                                default: state <= IDLE;
                            endcase
                        end else begin
                            ticks_left <= ticks_left - 1'b1;
                            slope_error <= extra_step
                                ? next_error - {1'b0,segment_ticks} : next_error;
                            if (rising)
                                gain <= next_gain_rise[15:0];
                            else
                                gain <= next_gain_fall[15:0];
                        end
                    end
                    SUSTAIN: gain <= SUSTAIN_LEVEL;
                    default: gain <= 16'd0;
                endcase
            end
        end
    end
endmodule
