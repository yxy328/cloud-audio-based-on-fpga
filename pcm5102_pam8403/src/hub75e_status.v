`timescale 1ns/1ps
// Eight rows of 8x8 tiles for the existing 64x64 panel. All settings are
// snapshotted at a full PWM boundary. A single dual-port block font ROM
// serves both panel halves; no OLED, second clock, or framebuffer is used.
module hub75e_status #(parameter ENABLE_TAKE_STATUS=0)(
    input wire clk,resetn,display_boundary,
    input wire [5:0] pixel_x,
    input wire [4:0] pixel_row,
    input wire mode16,hold_notes,pressure_pitch,recording,keys_ready,
    input wire [15:0] physical_keys,note_gates,
    input wire [7:0] ir_keys,
    input wire [2:0] timbre,analog_mode,
    input wire [1:0] effect_mode,
    input wire [3:0] effect_wet,
    input wire [4:0] volume,
    input wire [12:0] master_gain,
    input wire [9:0] adc_sample,analog_position,
    input wire analog_valid,
    input wire [7:0] take_flags,
    input wire [3:0] take_error,
    input wire [23:0] take_elapsed,
    input wire [10:0] take_count,
    output wire [14:0] upper_rgb,lower_rgb
);
    localparam [5:0] A=17,B=18,C=19,D=20,E=21,F=22,
        K=23,H=24,T=25,R=26,V=27,P=28,W=29,ALERT=30,BLANK=31;
    localparam [3:0] BLACK=0,WHITE=1,CYAN=2,GREEN=3,AMBER=4,
        RED=5,BLUE_DIM=6,GRAY_DIM=7,AMBER_DIM=8;
    reg mode_q,hold_q,pressure_q,record_q,ready_q,adc_valid_q;
    reg [15:0] physical_q,gates_q;
    reg [7:0] ir_q;
    reg [2:0] timbre_q,analog_q;
    reg [1:0] effect_q;
    reg [3:0] wet_q;
    reg [4:0] volume_q;
    reg [9:0] adc_q;
    reg [5:0] volume_fill,analog_fill;
    reg [7:0] take_q;
    reg [3:0] take_error_q;
    reg [10:0] take_count_q;
    reg [23:0] time_binary;
    reg [31:0] time_bcd,adjusted_bcd,time_display;
    reg [4:0] time_left;
    integer digit;
    always @*begin
        adjusted_bcd=time_bcd;
        for(digit=0;digit<8;digit=digit+1)
            if(time_bcd[digit*4 +: 4]>=5)adjusted_bcd[digit*4 +: 4]=time_bcd[digit*4 +: 4]+4'd3;
    end
    always @(posedge clk)begin
        if(!resetn)begin
            take_q<=0;take_error_q<=0;take_count_q<=0;time_binary<=0;time_bcd<=0;
            time_display<=0;time_left<=0;
        end else if(ENABLE_TAKE_STATUS)begin
            if(display_boundary)begin
                take_q<=take_flags;take_error_q<=take_error;take_count_q<=take_count;
                time_binary<=take_elapsed;time_bcd<=0;time_left<=24;time_display<=time_bcd;
            end else if(time_left!=0)begin
                time_bcd<={adjusted_bcd[30:0],time_binary[23]};time_binary<={time_binary[22:0],1'b0};
                time_left<=time_left-1'b1;
            end
        end
    end
    wire [8:0] gain_times3={2'd0,master_gain[12:6]}+{1'd0,master_gain[12:6],1'b0};
    wire [7:0] position_times3={2'd0,analog_position[9:4]}+{1'd0,analog_position[9:4],1'b0};
    always @(posedge clk) begin
        if(!resetn)begin
            mode_q<=0;hold_q<=0;pressure_q<=0;record_q<=0;ready_q<=0;adc_valid_q<=0;
            physical_q<=0;gates_q<=0;ir_q<=0;timbre_q<=0;analog_q<=0;effect_q<=0;wet_q<=0;
            volume_q<=16;adc_q<=0;volume_fill<=48;analog_fill<=0;
        end else if(display_boundary)begin
            mode_q<=mode16;hold_q<=hold_notes;pressure_q<=pressure_pitch;record_q<=recording;
            ready_q<=keys_ready;adc_valid_q<=analog_valid;
            physical_q<=physical_keys;gates_q<=note_gates;ir_q<=ir_keys;
            timbre_q<=timbre;analog_q<=analog_mode;effect_q<=effect_mode;wet_q<=effect_wet;
            volume_q<=volume;adc_q<=adc_sample;volume_fill<=gain_times3[7:2];
            analog_fill<=analog_position==1023 ? 6'd48 : position_times3[7:2];
        end
    end
    function [5:0] hex_glyph;
        input [3:0] value;
        begin hex_glyph=value<4'd10 ? {2'd0,value} : A+{2'd0,value}-6'd10; end
    endfunction
    // {glyph, foreground palette, background palette}; tile rows are:
    // K/H/T/R, volume, K1..8, K9..16, ADC, pressure+slider, effect, IR1..8.
    function [13:0] tile_style;
        input [5:0] x,y;
        reg [5:0] glyph;
        reg [3:0] fg,bg,key_index;
        reg [5:0] bar_x;
        begin
            glyph=BLANK;fg=CYAN;bg=BLACK;key_index=0;bar_x=x-6'd16;
            if(ENABLE_TAKE_STATUS && (take_q!=0 || take_error_q!=0) &&
                (y[5:3]==0 || y[5:3]==1 || y[5:3]>=6))begin
                case(y[5:3])
                    0:case(x[5:3])
                        0:glyph=R;1:begin glyph={5'd0,take_q[0]};fg=take_q[0] ? RED : GRAY_DIM;end
                        2:glyph=P;3:begin glyph={5'd0,take_q[1]};fg=take_q[1] ? GREEN : GRAY_DIM;end
                        4:glyph=B;5:glyph={5'd0,take_q[5]};6:glyph=A;7:glyph={5'd0,take_q[2]};
                    endcase
                    1:case(x[5:3])
                        0:glyph=T;
                        1:glyph={2'd0,time_display[31:28]};2:glyph={2'd0,time_display[27:24]};
                        3:glyph={2'd0,time_display[23:20]};4:glyph={2'd0,time_display[19:16]};
                        5:glyph={2'd0,time_display[15:12]};6:glyph=34;7:glyph={2'd0,time_display[11:8]};
                    endcase
                    6:case(x[5:3])
                        0:glyph=33;1:begin glyph={5'd0,take_q[3]};fg=take_q[3] ? GREEN : RED;end
                        2:glyph=F;3:begin glyph={5'd0,take_q[4]};fg=take_q[4] ? AMBER : GRAY_DIM;end
                        4:glyph=E;5:begin glyph=hex_glyph(take_error_q);fg=take_error_q!=0 ? RED : GREEN;end
                        6:glyph=C;7:begin glyph={4'd0,take_q[7:6]};fg=take_q[7:6]!=0 ? AMBER : GRAY_DIM;end
                    endcase
                    7:case(x[5:3])
                        0:glyph=E;1:glyph=hex_glyph({1'b0,take_count_q[10:8]});
                        2:glyph=hex_glyph(take_count_q[7:4]);3:glyph=hex_glyph(take_count_q[3:0]);
                        4:glyph=C;5:glyph=4;6:glyph=0;7:glyph=0;
                    endcase
                endcase
            end else case(y[5:3])
                0:case(x[5:3])
                    0:begin glyph=K;fg=ready_q ? CYAN : RED;end
                    1:glyph=mode_q ? 16 : 8;
                    2:glyph=H;
                    3:begin glyph={5'd0,hold_q};fg=hold_q ? GREEN : GRAY_DIM;end
                    4:glyph=T;
                    5:glyph={3'd0,timbre_q};
                    6:begin glyph=R;fg=record_q ? RED : GRAY_DIM;end
                    7:begin glyph={5'd0,record_q};fg=record_q ? RED : GRAY_DIM;end
                endcase
                1:begin
                    if(x[5:3]==0)glyph=V;
                    else if(x[5:3]==1)glyph={1'b0,volume_q};
                    else if(y[2:0]>=2 && y[2:0]<=5)
                        bg=bar_x<volume_fill ? GREEN : BLUE_DIM;
                end
                2,3:begin
                    key_index={y[3],x[5:3]};
                    glyph={2'd0,key_index}+1'b1;fg=WHITE;
                    if(!mode_q && key_index>=8)begin fg=GRAY_DIM;bg=BLACK;end
                    else if(x[2:0]!=7 && y[2:0]!=7)begin
                        bg=physical_q[key_index] ? GREEN : gates_q[key_index] ? CYAN : BLUE_DIM;
                        if(!mode_q && key_index==7)bg=physical_q[7] ? AMBER : AMBER_DIM;
                    end
                end
                4:case(x[5:3])
                    0:begin glyph=A;fg=adc_valid_q ? CYAN : RED;end
                    1:glyph={3'd0,analog_q};
                    3:glyph={4'd0,adc_q[9:8]};
                    4:glyph=hex_glyph(adc_q[7:4]);
                    5:glyph=hex_glyph(adc_q[3:0]);
                    7:begin glyph=adc_valid_q ? BLANK : ALERT;fg=RED;end
                    default:glyph=BLANK;
                endcase
                5:begin
                    if(x[5:3]==0)glyph=P;
                    else if(x[5:3]==1)glyph={5'd0,pressure_q};
                    else if(y[2:0]>=2 && y[2:0]<=5)
                        bg=!adc_valid_q ? RED : bar_x<analog_fill ? AMBER : AMBER_DIM;
                end
                6:case(x[5:3])
                    0:glyph=E;
                    1:glyph={4'd0,effect_q};
                    2:glyph=W;
                    3:glyph={2'd0,wet_q};
                    // IR is written as two small letters in the last tiles.
                    6:glyph=32;
                    7:glyph=R;
                    default:glyph=BLANK;
                endcase
                7:begin
                    glyph={3'd0,x[5:3]}+1'b1;fg=WHITE;
                    if(x[2:0]!=7 && y[2:0]!=7)bg=ir_q[x[5:3]] ? AMBER : AMBER_DIM;
                end
            endcase
            tile_style={glyph,fg,bg};
        end
    endfunction
    function [14:0] color;
        input [3:0] index;
        begin case(index)
            WHITE:color={5'd24,5'd24,5'd24};
            CYAN:color={5'd0,5'd20,5'd28};
            GREEN:color={5'd0,5'd26,5'd10};
            AMBER:color={5'd28,5'd16,5'd0};
            RED:color={5'd31,5'd2,5'd1};
            BLUE_DIM:color={5'd1,5'd3,5'd5};
            GRAY_DIM:color={5'd2,5'd2,5'd2};
            AMBER_DIM:color={5'd4,5'd2,5'd0};
            default:color=0;
        endcase end
    endfunction
    wire [13:0] upper_cell=tile_style(pixel_x,{1'b0,pixel_row});
    wire [13:0] lower_cell=tile_style(pixel_x,{1'b1,pixel_row});
    // 64 glyphs x eight rows; tools/generate_status_font.py maintains these.
    (* syn_romstyle="block_rom" *) reg [7:0] font[0:511];
    reg [7:0] upper_bits,lower_bits,upper_colors,lower_colors;
    reg [2:0] font_x;
    always @(posedge clk)begin
        upper_bits<=font[{upper_cell[13:8],pixel_row[2:0]}];
        lower_bits<=font[{lower_cell[13:8],pixel_row[2:0]}];
        upper_colors<=upper_cell[7:0];lower_colors<=lower_cell[7:0];
        font_x<=pixel_x[2:0];
    end
    assign upper_rgb=color(upper_bits[7-font_x] ? upper_colors[7:4] : upper_colors[3:0]);
    assign lower_rgb=color(lower_bits[7-font_x] ? lower_colors[7:4] : lower_colors[3:0]);
    // FONT_INITIALIZATION_BEGIN
    initial begin
        font[0]=8'h00; font[1]=8'h38; font[2]=8'h28; font[3]=8'h28; font[4]=8'h28; font[5]=8'h38; font[6]=8'h00; font[7]=8'h00; // 0: 0
        font[8]=8'h00; font[9]=8'h10; font[10]=8'h30; font[11]=8'h10; font[12]=8'h10; font[13]=8'h38; font[14]=8'h00; font[15]=8'h00; // 1: 1
        font[16]=8'h00; font[17]=8'h38; font[18]=8'h08; font[19]=8'h38; font[20]=8'h20; font[21]=8'h38; font[22]=8'h00; font[23]=8'h00; // 2: 2
        font[24]=8'h00; font[25]=8'h38; font[26]=8'h08; font[27]=8'h38; font[28]=8'h08; font[29]=8'h38; font[30]=8'h00; font[31]=8'h00; // 3: 3
        font[32]=8'h00; font[33]=8'h28; font[34]=8'h28; font[35]=8'h38; font[36]=8'h08; font[37]=8'h08; font[38]=8'h00; font[39]=8'h00; // 4: 4
        font[40]=8'h00; font[41]=8'h38; font[42]=8'h20; font[43]=8'h38; font[44]=8'h08; font[45]=8'h38; font[46]=8'h00; font[47]=8'h00; // 5: 5
        font[48]=8'h00; font[49]=8'h38; font[50]=8'h20; font[51]=8'h38; font[52]=8'h28; font[53]=8'h38; font[54]=8'h00; font[55]=8'h00; // 6: 6
        font[56]=8'h00; font[57]=8'h38; font[58]=8'h08; font[59]=8'h10; font[60]=8'h10; font[61]=8'h10; font[62]=8'h00; font[63]=8'h00; // 7: 7
        font[64]=8'h00; font[65]=8'h38; font[66]=8'h28; font[67]=8'h38; font[68]=8'h28; font[69]=8'h38; font[70]=8'h00; font[71]=8'h00; // 8: 8
        font[72]=8'h00; font[73]=8'h38; font[74]=8'h28; font[75]=8'h38; font[76]=8'h08; font[77]=8'h38; font[78]=8'h00; font[79]=8'h00; // 9: 9
        font[80]=8'h00; font[81]=8'h4e; font[82]=8'hca; font[83]=8'h4a; font[84]=8'h4a; font[85]=8'hee; font[86]=8'h00; font[87]=8'h00; // 10: 10
        font[88]=8'h00; font[89]=8'h44; font[90]=8'hcc; font[91]=8'h44; font[92]=8'h44; font[93]=8'hee; font[94]=8'h00; font[95]=8'h00; // 11: 11
        font[96]=8'h00; font[97]=8'h4e; font[98]=8'hc2; font[99]=8'h4e; font[100]=8'h48; font[101]=8'hee; font[102]=8'h00; font[103]=8'h00; // 12: 12
        font[104]=8'h00; font[105]=8'h4e; font[106]=8'hc2; font[107]=8'h4e; font[108]=8'h42; font[109]=8'hee; font[110]=8'h00; font[111]=8'h00; // 13: 13
        font[112]=8'h00; font[113]=8'h4a; font[114]=8'hca; font[115]=8'h4e; font[116]=8'h42; font[117]=8'he2; font[118]=8'h00; font[119]=8'h00; // 14: 14
        font[120]=8'h00; font[121]=8'h4e; font[122]=8'hc8; font[123]=8'h4e; font[124]=8'h42; font[125]=8'hee; font[126]=8'h00; font[127]=8'h00; // 15: 15
        font[128]=8'h00; font[129]=8'h4e; font[130]=8'hc8; font[131]=8'h4e; font[132]=8'h4a; font[133]=8'hee; font[134]=8'h00; font[135]=8'h00; // 16: 16
        font[136]=8'h00; font[137]=8'h10; font[138]=8'h28; font[139]=8'h38; font[140]=8'h28; font[141]=8'h28; font[142]=8'h00; font[143]=8'h00; // 17: A
        font[144]=8'h00; font[145]=8'h30; font[146]=8'h28; font[147]=8'h30; font[148]=8'h28; font[149]=8'h30; font[150]=8'h00; font[151]=8'h00; // 18: B
        font[152]=8'h00; font[153]=8'h38; font[154]=8'h20; font[155]=8'h20; font[156]=8'h20; font[157]=8'h38; font[158]=8'h00; font[159]=8'h00; // 19: C
        font[160]=8'h00; font[161]=8'h30; font[162]=8'h28; font[163]=8'h28; font[164]=8'h28; font[165]=8'h30; font[166]=8'h00; font[167]=8'h00; // 20: D
        font[168]=8'h00; font[169]=8'h38; font[170]=8'h20; font[171]=8'h30; font[172]=8'h20; font[173]=8'h38; font[174]=8'h00; font[175]=8'h00; // 21: E
        font[176]=8'h00; font[177]=8'h38; font[178]=8'h20; font[179]=8'h30; font[180]=8'h20; font[181]=8'h20; font[182]=8'h00; font[183]=8'h00; // 22: F
        font[184]=8'h00; font[185]=8'h28; font[186]=8'h28; font[187]=8'h30; font[188]=8'h28; font[189]=8'h28; font[190]=8'h00; font[191]=8'h00; // 23: K
        font[192]=8'h00; font[193]=8'h28; font[194]=8'h28; font[195]=8'h38; font[196]=8'h28; font[197]=8'h28; font[198]=8'h00; font[199]=8'h00; // 24: H
        font[200]=8'h00; font[201]=8'h38; font[202]=8'h10; font[203]=8'h10; font[204]=8'h10; font[205]=8'h10; font[206]=8'h00; font[207]=8'h00; // 25: T
        font[208]=8'h00; font[209]=8'h30; font[210]=8'h28; font[211]=8'h30; font[212]=8'h28; font[213]=8'h28; font[214]=8'h00; font[215]=8'h00; // 26: R
        font[216]=8'h00; font[217]=8'h28; font[218]=8'h28; font[219]=8'h28; font[220]=8'h28; font[221]=8'h10; font[222]=8'h00; font[223]=8'h00; // 27: V
        font[224]=8'h00; font[225]=8'h30; font[226]=8'h28; font[227]=8'h30; font[228]=8'h20; font[229]=8'h20; font[230]=8'h00; font[231]=8'h00; // 28: P
        font[232]=8'h00; font[233]=8'h28; font[234]=8'h28; font[235]=8'h38; font[236]=8'h38; font[237]=8'h28; font[238]=8'h00; font[239]=8'h00; // 29: W
        font[240]=8'h00; font[241]=8'h10; font[242]=8'h10; font[243]=8'h10; font[244]=8'h00; font[245]=8'h10; font[246]=8'h00; font[247]=8'h00; // 30: !
        font[248]=8'h00; font[249]=8'h00; font[250]=8'h00; font[251]=8'h00; font[252]=8'h00; font[253]=8'h00; font[254]=8'h00; font[255]=8'h00; // 31:  
        font[256]=8'h00; font[257]=8'h38; font[258]=8'h10; font[259]=8'h10; font[260]=8'h10; font[261]=8'h38; font[262]=8'h00; font[263]=8'h00; // 32: I
        font[264]=8'h00; font[265]=8'h38; font[266]=8'h20; font[267]=8'h38; font[268]=8'h08; font[269]=8'h38; font[270]=8'h00; font[271]=8'h00; // 33: S
        font[272]=8'h00; font[273]=8'h00; font[274]=8'h00; font[275]=8'h00; font[276]=8'h00; font[277]=8'h10; font[278]=8'h00; font[279]=8'h00; // 34: .
        font[280]=8'h00; font[281]=8'h00; font[282]=8'h00; font[283]=8'h00; font[284]=8'h00; font[285]=8'h00; font[286]=8'h00; font[287]=8'h00; // 35:  
        font[288]=8'h00; font[289]=8'h00; font[290]=8'h00; font[291]=8'h00; font[292]=8'h00; font[293]=8'h00; font[294]=8'h00; font[295]=8'h00; // 36:  
        font[296]=8'h00; font[297]=8'h00; font[298]=8'h00; font[299]=8'h00; font[300]=8'h00; font[301]=8'h00; font[302]=8'h00; font[303]=8'h00; // 37:  
        font[304]=8'h00; font[305]=8'h00; font[306]=8'h00; font[307]=8'h00; font[308]=8'h00; font[309]=8'h00; font[310]=8'h00; font[311]=8'h00; // 38:  
        font[312]=8'h00; font[313]=8'h00; font[314]=8'h00; font[315]=8'h00; font[316]=8'h00; font[317]=8'h00; font[318]=8'h00; font[319]=8'h00; // 39:  
        font[320]=8'h00; font[321]=8'h00; font[322]=8'h00; font[323]=8'h00; font[324]=8'h00; font[325]=8'h00; font[326]=8'h00; font[327]=8'h00; // 40:  
        font[328]=8'h00; font[329]=8'h00; font[330]=8'h00; font[331]=8'h00; font[332]=8'h00; font[333]=8'h00; font[334]=8'h00; font[335]=8'h00; // 41:  
        font[336]=8'h00; font[337]=8'h00; font[338]=8'h00; font[339]=8'h00; font[340]=8'h00; font[341]=8'h00; font[342]=8'h00; font[343]=8'h00; // 42:  
        font[344]=8'h00; font[345]=8'h00; font[346]=8'h00; font[347]=8'h00; font[348]=8'h00; font[349]=8'h00; font[350]=8'h00; font[351]=8'h00; // 43:  
        font[352]=8'h00; font[353]=8'h00; font[354]=8'h00; font[355]=8'h00; font[356]=8'h00; font[357]=8'h00; font[358]=8'h00; font[359]=8'h00; // 44:  
        font[360]=8'h00; font[361]=8'h00; font[362]=8'h00; font[363]=8'h00; font[364]=8'h00; font[365]=8'h00; font[366]=8'h00; font[367]=8'h00; // 45:  
        font[368]=8'h00; font[369]=8'h00; font[370]=8'h00; font[371]=8'h00; font[372]=8'h00; font[373]=8'h00; font[374]=8'h00; font[375]=8'h00; // 46:  
        font[376]=8'h00; font[377]=8'h00; font[378]=8'h00; font[379]=8'h00; font[380]=8'h00; font[381]=8'h00; font[382]=8'h00; font[383]=8'h00; // 47:  
        font[384]=8'h00; font[385]=8'h00; font[386]=8'h00; font[387]=8'h00; font[388]=8'h00; font[389]=8'h00; font[390]=8'h00; font[391]=8'h00; // 48:  
        font[392]=8'h00; font[393]=8'h00; font[394]=8'h00; font[395]=8'h00; font[396]=8'h00; font[397]=8'h00; font[398]=8'h00; font[399]=8'h00; // 49:  
        font[400]=8'h00; font[401]=8'h00; font[402]=8'h00; font[403]=8'h00; font[404]=8'h00; font[405]=8'h00; font[406]=8'h00; font[407]=8'h00; // 50:  
        font[408]=8'h00; font[409]=8'h00; font[410]=8'h00; font[411]=8'h00; font[412]=8'h00; font[413]=8'h00; font[414]=8'h00; font[415]=8'h00; // 51:  
        font[416]=8'h00; font[417]=8'h00; font[418]=8'h00; font[419]=8'h00; font[420]=8'h00; font[421]=8'h00; font[422]=8'h00; font[423]=8'h00; // 52:  
        font[424]=8'h00; font[425]=8'h00; font[426]=8'h00; font[427]=8'h00; font[428]=8'h00; font[429]=8'h00; font[430]=8'h00; font[431]=8'h00; // 53:  
        font[432]=8'h00; font[433]=8'h00; font[434]=8'h00; font[435]=8'h00; font[436]=8'h00; font[437]=8'h00; font[438]=8'h00; font[439]=8'h00; // 54:  
        font[440]=8'h00; font[441]=8'h00; font[442]=8'h00; font[443]=8'h00; font[444]=8'h00; font[445]=8'h00; font[446]=8'h00; font[447]=8'h00; // 55:  
        font[448]=8'h00; font[449]=8'h00; font[450]=8'h00; font[451]=8'h00; font[452]=8'h00; font[453]=8'h00; font[454]=8'h00; font[455]=8'h00; // 56:  
        font[456]=8'h00; font[457]=8'h00; font[458]=8'h00; font[459]=8'h00; font[460]=8'h00; font[461]=8'h00; font[462]=8'h00; font[463]=8'h00; // 57:  
        font[464]=8'h00; font[465]=8'h00; font[466]=8'h00; font[467]=8'h00; font[468]=8'h00; font[469]=8'h00; font[470]=8'h00; font[471]=8'h00; // 58:  
        font[472]=8'h00; font[473]=8'h00; font[474]=8'h00; font[475]=8'h00; font[476]=8'h00; font[477]=8'h00; font[478]=8'h00; font[479]=8'h00; // 59:  
        font[480]=8'h00; font[481]=8'h00; font[482]=8'h00; font[483]=8'h00; font[484]=8'h00; font[485]=8'h00; font[486]=8'h00; font[487]=8'h00; // 60:  
        font[488]=8'h00; font[489]=8'h00; font[490]=8'h00; font[491]=8'h00; font[492]=8'h00; font[493]=8'h00; font[494]=8'h00; font[495]=8'h00; // 61:  
        font[496]=8'h00; font[497]=8'h00; font[498]=8'h00; font[499]=8'h00; font[500]=8'h00; font[501]=8'h00; font[502]=8'h00; font[503]=8'h00; // 62:  
        font[504]=8'h00; font[505]=8'h00; font[506]=8'h00; font[507]=8'h00; font[508]=8'h00; font[509]=8'h00; font[510]=8'h00; font[511]=8'h00; // 63:  
    end
    // FONT_INITIALIZATION_END
endmodule
