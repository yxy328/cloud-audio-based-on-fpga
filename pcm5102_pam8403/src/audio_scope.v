`timescale 1ns/1ps
// 64x64 scope styling. A 2048x16 ROM holds 3x5 glyphs and percent
// conversion constants. Its port is shared with blanking-time conversions;
// color interpolation is a small combinational RGB5 palette, without DSP.
module audio_scope(
    input wire clk,resetn,service_ce,publish,display_valid,
    input wire [7:0] capture_peak,
    input wire [5:0] capture_peak64,
    input wire [19:0] range_word,
    input wire [2:0] shown_range,
    input wire [1:0] visual_mode,shown_ratio,shown_phase,
    input wire [5:0] pixel_x,
    input wire [4:0] pixel_row,
    output reg [14:0] upper_rgb,lower_rgb,
    output wire xy_label_on
);
    (* syn_romstyle="block_rom" *) reg [15:0] style_rom[0:2047];
    initial $readmemh("src/scope_style.hex",style_rom);
    reg [15:0] style_q;
    reg [11:0] peak_bcd;
    reg [5:0] shown_level;
    reg [14:0] shown_color;
    reg [7:0] label_char;
    wire peak_digit=pixel_row>=26 && pixel_row<=30 && pixel_x>=8 && pixel_x<20;
    reg [3:0] peak_nibble;
    always @*case(pixel_x[4:2])
        2:peak_nibble=peak_bcd[11:8]==0 ? 4'd15 : peak_bcd[11:8];
        3:peak_nibble=peak_bcd[7:4];
        default:peak_nibble=peak_bcd[3:0];
    endcase
    wire [10:0] background_address={shown_range,8'd0}+11'd256+{3'd0,pixel_row,pixel_x[5:3]};
    wire [10:0] rom_address=service_ce ? 11'd16+{3'd0,capture_peak} : visual_mode==2 ?
        11'd145+{3'd0,label_char} : peak_digit ? {7'd0,peak_nibble} : background_address;
    always @(posedge clk)style_q<=style_rom[rom_address];

    function [14:0] palette;
        input [5:0] peak;
        reg [5:0] limited;
        reg [7:0] q;
        reg [5:0] u;
        reg [8:0] seven_u;
        reg [4:0] d,r,g,b;
        begin
            // PCM/64, 33 hue points: 180deg cyan -> 360deg red, clamped
            // at 2048 PCM counts. All constant products use shifts/adds.
            // 2048 counts is the nominal loud reference after /16 source
            // attenuation, not a claim of digital clipping or acoustic SPL.
            limited=peak>6'd32 ? 6'd32 : peak;
            q=({2'd0,limited}<<2)+({2'd0,limited}<<1);
            u=q[5:0];
            seven_u=({3'd0,u}<<3)-{3'd0,u};
            d=seven_u[8:4];
            case(q[7:6])
                0:begin r=5'd3;g=5'd31-d;b=5'd31;end
                1:begin r=5'd3+d;g=5'd3;b=5'd31;end
                2:begin r=5'd31;g=5'd3;b=5'd31-d;end
                default:begin r=5'd31;g=5'd3;b=5'd3;end
            endcase
            palette={r,g,b};
        end
    endfunction
    always @(posedge clk)begin
        if(!resetn)begin
            peak_bcd<=0;
            shown_level<=0;shown_color<={5'd8,5'd8,5'd8};
        end else begin
            if(publish)begin
                // S_LATCH_HIGH fetched the percentage on the preceding edge.
                peak_bcd<=style_q[11:0];
                // Only the original conservative axis decides silence.
                // A nonzero sub-64-count window uses palette(0), cyan.
                shown_color<=capture_peak==0 ? {5'd8,5'd8,5'd8} : palette(capture_peak64);
                shown_level<=capture_peak[7:2]+(|capture_peak[1:0]);
            end
        end
    end

    wire [11:0] phase_digits=shown_phase==0 ? 12'h000 : shown_phase==1 ? 12'h045 :
        shown_phase==2 ? 12'h090 : 12'h135;
    always @*begin
        label_char=" ";
        case(pixel_x[5:2])
            1:label_char=shown_ratio==0 ? "A" : "R";
            2:label_char=shown_ratio==0 ? "U" : "E";
            3:label_char=shown_ratio==0 ? "D" : "F";
            5:if(shown_ratio!=0)label_char=shown_ratio==3 ? "2" : "1";
            6:if(shown_ratio!=0)label_char=":";
            7:if(shown_ratio!=0)label_char=shown_ratio==2 ? "2" : shown_ratio==3 ? "3" : "1";
            9:if(shown_ratio!=0)label_char="P";
            10:if(shown_ratio!=0)label_char={4'h3,phase_digits[11:8]};
            11:if(shown_ratio!=0)label_char={4'h3,phase_digits[7:4]};
            12:if(shown_ratio!=0)label_char={4'h3,phase_digits[3:0]};
            default:label_char=" ";
        endcase
    end
    wire [2:0] glyph_row=visual_mode==2 ? pixel_row[2:0] : pixel_row-5'd26;
    wire [4:0] glyph_index=5'd14-({glyph_row,1'b0}+glyph_row)-pixel_x[1:0];
    wire label_dot=pixel_x[1:0]!=3 && style_q[glyph_index];
    assign xy_label_on=visual_mode==2 && display_valid && pixel_row<5 && label_dot;
    function signed [6:0] ordinate;
        input signed [9:0] value;
        input [2:0] scale;
        reg signed [5:0] delta;
        begin
            // safe_range guarantees that the published endpoints fit +/-16
            // pixels. Select only the six significant coordinate bits; no
            // wide barrel shifter or out-of-range arithmetic is required.
            case(scale)
                0:delta={value[9],value[9:5]};
                1:delta=value[9:4];
                2:delta=value[8:3];
                3:delta=value[7:2];
                4:delta=value[6:1];
                default:delta=value[5:0];
            endcase
            ordinate=7'sd27-{{1{delta[5]}},delta};
        end
    endfunction
    wire signed [6:0] top_y=ordinate(range_word[19:10],shown_range);
    wire signed [6:0] bottom_y=ordinate(range_word[9:0],shown_range);
    function [14:0] graph;
        input [5:0] x,y;
        input signed [6:0] top,bottom;
        input valid;
        input [14:0] color;
        begin
            graph=0;
            if(x>=16 && y>=8 && y<=45)begin
                if((y==27 && x[1:0]==0) ||
                   ((x==16 || x==39 || x==63) && y[2:0]==3))graph={5'd0,5'd2,5'd2};
                if(valid && $signed({1'b0,y})>=top && $signed({1'b0,y})<=bottom)graph=color;
            end
        end
    endfunction
    always @*begin
        upper_rgb=graph(pixel_x,{1'b0,pixel_row},top_y,bottom_y,display_valid,shown_color);
        lower_rgb=graph(pixel_x,{1'b1,pixel_row},top_y,bottom_y,display_valid,shown_color);
        if(!peak_digit && style_q[{1'b0,pixel_x[2:0]}])upper_rgb={5'd9,5'd12,5'd12};
        if(!peak_digit && style_q[{1'b1,pixel_x[2:0]}])
            lower_rgb=pixel_row==14 ? {5'd0,5'd4,5'd3} : {5'd11,5'd15,5'd14};
        // Zero label shares its row with the independent peak digits below.
        if(pixel_x>=12 && pixel_x<=14 && pixel_row>=25 && pixel_row<=29 &&
           (pixel_x!=13 || pixel_row==25 || pixel_row==29))upper_rgb={5'd9,5'd12,5'd12};
        if(peak_digit && label_dot)lower_rgb={5'd11,5'd15,5'd14};
        if(pixel_row>=27 && pixel_row<=29 && pixel_x>=32 && (pixel_x-6'd32)<shown_level)lower_rgb=shown_color;
    end
endmodule
