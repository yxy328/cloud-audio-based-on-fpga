`timescale 1ns/1ps
// 32-bit phase; the high 8 bits address an effective 256-point sine table.
// Quarter-wave constants include both endpoints, generated offline as
// round(32767 * sin(pi * index / 128)). No real arithmetic in the hardware.
module nco_sine #(
    parameter [31:0] INC = 32'd38_702_432
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    output wire signed [15:0] sample
);
    reg [31:0] phase;
    wire [7:0] address = phase[31:24];
    wire [6:0] table_index = address[6]
        ? (7'd64 - {1'b0, address[5:0]}) : {1'b0, address[5:0]};
    wire signed [15:0] magnitude = quarter_sine(table_index);

    assign sample = address[7] ? -magnitude : magnitude;
    always @(posedge clk) begin
        if (!resetn)
            phase <= 32'd0;
        else if (sample_ce)
            phase <= phase + INC;
    end

    function signed [15:0] quarter_sine;
        input [6:0] index;
        begin
            case (index)
                7'd0: quarter_sine = 16'sd0;
                7'd1: quarter_sine = 16'sd804;
                7'd2: quarter_sine = 16'sd1608;
                7'd3: quarter_sine = 16'sd2410;
                7'd4: quarter_sine = 16'sd3212;
                7'd5: quarter_sine = 16'sd4011;
                7'd6: quarter_sine = 16'sd4808;
                7'd7: quarter_sine = 16'sd5602;
                7'd8: quarter_sine = 16'sd6393;
                7'd9: quarter_sine = 16'sd7179;
                7'd10: quarter_sine = 16'sd7962;
                7'd11: quarter_sine = 16'sd8739;
                7'd12: quarter_sine = 16'sd9512;
                7'd13: quarter_sine = 16'sd10278;
                7'd14: quarter_sine = 16'sd11039;
                7'd15: quarter_sine = 16'sd11793;
                7'd16: quarter_sine = 16'sd12539;
                7'd17: quarter_sine = 16'sd13279;
                7'd18: quarter_sine = 16'sd14010;
                7'd19: quarter_sine = 16'sd14732;
                7'd20: quarter_sine = 16'sd15446;
                7'd21: quarter_sine = 16'sd16151;
                7'd22: quarter_sine = 16'sd16846;
                7'd23: quarter_sine = 16'sd17530;
                7'd24: quarter_sine = 16'sd18204;
                7'd25: quarter_sine = 16'sd18868;
                7'd26: quarter_sine = 16'sd19519;
                7'd27: quarter_sine = 16'sd20159;
                7'd28: quarter_sine = 16'sd20787;
                7'd29: quarter_sine = 16'sd21403;
                7'd30: quarter_sine = 16'sd22005;
                7'd31: quarter_sine = 16'sd22594;
                7'd32: quarter_sine = 16'sd23170;
                7'd33: quarter_sine = 16'sd23731;
                7'd34: quarter_sine = 16'sd24279;
                7'd35: quarter_sine = 16'sd24811;
                7'd36: quarter_sine = 16'sd25329;
                7'd37: quarter_sine = 16'sd25832;
                7'd38: quarter_sine = 16'sd26319;
                7'd39: quarter_sine = 16'sd26790;
                7'd40: quarter_sine = 16'sd27245;
                7'd41: quarter_sine = 16'sd27683;
                7'd42: quarter_sine = 16'sd28105;
                7'd43: quarter_sine = 16'sd28510;
                7'd44: quarter_sine = 16'sd28898;
                7'd45: quarter_sine = 16'sd29268;
                7'd46: quarter_sine = 16'sd29621;
                7'd47: quarter_sine = 16'sd29956;
                7'd48: quarter_sine = 16'sd30273;
                7'd49: quarter_sine = 16'sd30571;
                7'd50: quarter_sine = 16'sd30852;
                7'd51: quarter_sine = 16'sd31113;
                7'd52: quarter_sine = 16'sd31356;
                7'd53: quarter_sine = 16'sd31580;
                7'd54: quarter_sine = 16'sd31785;
                7'd55: quarter_sine = 16'sd31971;
                7'd56: quarter_sine = 16'sd32137;
                7'd57: quarter_sine = 16'sd32285;
                7'd58: quarter_sine = 16'sd32412;
                7'd59: quarter_sine = 16'sd32521;
                7'd60: quarter_sine = 16'sd32609;
                7'd61: quarter_sine = 16'sd32678;
                7'd62: quarter_sine = 16'sd32728;
                7'd63: quarter_sine = 16'sd32757;
                7'd64: quarter_sine = 16'sd32767;
                default: quarter_sine = 16'sd0;
            endcase
        end
    endfunction
endmodule
