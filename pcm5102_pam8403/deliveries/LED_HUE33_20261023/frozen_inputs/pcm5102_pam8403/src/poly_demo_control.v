`timescale 1ns/1ps
// Each live S2 event selects one audition state; there is no automatic score.
// S1 gates the selected voices. Release/pitch events only affect voice 1.
module poly_demo_control (
    input wire clk,
    input wire resetn,
    input wire play_gate,
    input wire next_scene,
    output reg [1:0] scene,
    output wire [3:0] gates,
    output wire [127:0] phase_increments
);
    always @(posedge clk) begin
        if (!resetn)
            scene <= 2'd0;
        else if (next_scene)
            scene <= scene + 2'd1;
    end
    wire [3:0] selected = (scene == 2'd1) ? 4'b1101 : 4'b1111;
    wire [31:0] second_pitch = (scene == 2'd3) ? 32'd51662052 : 32'd46025656;
    assign gates = selected & {4{play_gate}};
    // Voice 0=A4, voice 1=C5/D5, voice 2=E5, voice 3=A5.
    assign phase_increments = {32'd77405619,32'd57988693,second_pitch,32'd38702809};
endmodule
