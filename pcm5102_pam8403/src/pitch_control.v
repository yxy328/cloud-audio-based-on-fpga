`timescale 1ns/1ps
// A live S2 press changes pitch. Holding S2 never repeats automatically.
module pitch_control (
    input wire clk,
    input wire resetn,
    input wire next_pitch,
    output reg [1:0] note_index,
    output reg [31:0] phase_inc
);
    always @(posedge clk) begin
        if (!resetn)
            note_index <= 2'd0;
        else if (next_pitch)
            note_index <= note_index + 2'd1;
    end

    always @* begin
        case (note_index)
            2'd0: phase_inc = 32'd38702809; // 440.000000 Hz
            2'd1: phase_inc = 32'd46025656; // 523.251131 Hz
            2'd2: phase_inc = 32'd57988693; // 659.255114 Hz
            2'd3: phase_inc = 32'd77405619; // 880.000000 Hz
            default: phase_inc = 32'd38702809;
        endcase
    end
endmodule
