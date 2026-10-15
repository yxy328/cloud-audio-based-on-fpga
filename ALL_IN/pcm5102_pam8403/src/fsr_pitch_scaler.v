`timescale 1ns/1ps
// Seven notes share a smooth Q0.16 frequency ratio. DDS phases are untouched.
// Full scale is bypassed so volume mode retains the exact original pitches.
// Two fabric clock stages keep the multiply outside the DDS accumulator path.
module fsr_pitch_scaler #(
    parameter [223:0] NOTE_INCREMENTS = {
        32'd43442435, 32'd38702809, 32'd34480283, 32'd30718440,
        32'd28994347, 32'd25831026, 32'd23012828
    }
) (
    input wire clk,
    input wire resetn,
    input wire [15:0] pitch_ratio,
    output wire [255:0] phase_increments
);
    reg full_ratio_d;
    always @(posedge clk) begin
        if (!resetn) full_ratio_d <= 1'b1;
        else full_ratio_d <= pitch_ratio == 16'hffff;
    end
    assign phase_increments[255:224] = 32'd0; // Key 8 never starts a note.
    genvar note_index;
    generate
        for (note_index=0; note_index<7; note_index=note_index+1) begin: notes
            localparam [31:0] BASE_STEP = NOTE_INCREMENTS[note_index*32 +: 32];
            reg [47:0] product;
            reg [31:0] step;
            always @(posedge clk) begin
                if (!resetn) begin
                    product <= 48'd0;
                    step <= BASE_STEP;
                end else begin
                    product <= BASE_STEP * pitch_ratio;
                    step <= full_ratio_d ? BASE_STEP : product[47:16];
                end
            end
            assign phase_increments[note_index*32 +: 32] = step;
        end
    endgenerate
endmodule
