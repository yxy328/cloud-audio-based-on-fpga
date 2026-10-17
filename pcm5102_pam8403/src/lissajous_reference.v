`timescale 1ns/1ps
// Display-only coherent DDS pair. One base turn per 256 sample enables;
// ratios are exact integers, so every 512-point capture closes its curve.
// Both axes have 14-pixel amplitude: 1:1 quadrature is a circle on square LEDs.
// Quarter-wave tables map directly to pixels; no DSP or block RAM is needed.
module lissajous_reference (
    input wire clk, resetn, restart, sample_ce,
    input wire [1:0] ratio, phase,
    output wire [5:0] x,
    output wire [4:0] y
);
    reg [7:0] angle;
    always @(posedge clk) begin
        if (!resetn || restart) angle<=0;
        else if(sample_ce) angle<=angle+1'b1;
    end
    wire [7:0] angle_x=ratio==3 ? (angle<<1) : angle;
    wire [7:0] angle_y=(ratio==2 ? (angle<<1) :
        ratio==3 ? (angle+(angle<<1)) : angle)+{phase,5'd0};
    function signed [4:0] sine_pixel;
        input [7:0] a;
        reg [6:0] index;
        reg signed [4:0] magnitude;
        begin
            index=a[6] ? 7'd64-{1'b0,a[5:0]} : {1'b0,a[5:0]};
            case(index)
                0,1:magnitude=0;
                2,3,4:magnitude=1;
                5,6,7:magnitude=2;
                8,9,10:magnitude=3;
                11,12,13:magnitude=4;
                14,15,16:magnitude=5;
                17,18,19:magnitude=6;
                20,21,22,23:magnitude=7;
                24,25,26:magnitude=8;
                27,28,29,30:magnitude=9;
                31,32,33,34:magnitude=10;
                35,36,37,38,39:magnitude=11;
                40,41,42,43,44:magnitude=12;
                45,46,47,48,49,50,51,52,53:magnitude=13;
                default:magnitude=14;
            endcase
            sine_pixel=a[7] ? -magnitude : magnitude;
        end
    endfunction
    wire signed [4:0] sx=sine_pixel(angle_x),sy=sine_pixel(angle_y);
    assign x=6'd32+{sx[4],sx};
    assign y=5'd16-sy;
endmodule
