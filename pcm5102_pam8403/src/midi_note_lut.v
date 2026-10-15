`timescale 1ns/1ps
// Registered equal-temperament MIDI 60..72 -> DDS steps.
// round(440 * 2^((MIDI-69)/12) * 2^32 / 48828.125).
module midi_note_lut (
    input wire clk,
    input wire resetn,
    input wire [55:0] note_map,
    output reg [223:0] phase_increments
);
    function [31:0] midi_step;
        input [7:0] note;
        begin
            case (note)
                60: midi_step=32'd23012828;
                61: midi_step=32'd24381242;
                62: midi_step=32'd25831026;
                63: midi_step=32'd27367019;
                64: midi_step=32'd28994347;
                65: midi_step=32'd30718440;
                66: midi_step=32'd32545054;
                67: midi_step=32'd34480283;
                68: midi_step=32'd36530588;
                69: midi_step=32'd38702809;
                70: midi_step=32'd41004198;
                71: midi_step=32'd43442435;
                72: midi_step=32'd46025656;
                default: midi_step=32'd0;
            endcase
        end
    endfunction
    integer key_index;
    always @(posedge clk) begin
        if (!resetn) phase_increments <= {
            32'd43442435,32'd38702809,32'd34480283,32'd30718440,
            32'd28994347,32'd25831026,32'd23012828};
        else for (key_index=0;key_index<7;key_index=key_index+1)
            phase_increments[key_index*32 +: 32] <= midi_step(note_map[key_index*8 +: 8]);
    end
endmodule
