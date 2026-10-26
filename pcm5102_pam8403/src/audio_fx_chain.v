`timescale 1ns/1ps
// Three independent histories; C -> D -> R. One time-shared signed multiplier.
// Settings: [1:0] chorus excursion, [3:2] echo decimation,
// [5:4] delay feedback, [7:6] reverb decay. Wet nibbles C/D/R are 0..8 / 16.
// Feedback truncates towards zero, so silence cannot sustain a -1 LSB cycle.
module audio_fx_chain(
    input wire clk,resetn,sample_valid,
    input wire signed [15:0] dry,
    input wire [2:0] mask,
    input wire [7:0] settings,
    input wire [11:0] wet_mix,
    output reg signed [15:0] sample,
    output reg valid,overrun
);
    (* syn_ramstyle="block_ram" *) reg signed [15:0] chorus_memory[0:2047];
    (* syn_ramstyle="block_ram" *) reg signed [15:0] delay_memory[0:4095];
    (* syn_ramstyle="block_ram" *) reg signed [15:0] reverb_memory[0:4095];
    localparam IDLE=0,C_READ0=1,C_LOAD0=2,C_READ1=3,C_LOAD1=4,
        C_INTERP_MUL=5,C_INTERP_LOAD=6,C_WET_MUL=7,C_MIX=8,
        D_START=9,D_READ=10,D_LOAD=11,D_FB_MUL=12,D_FB_LOAD=13,D_WET_MUL=14,D_MIX=15,
        R_START=16,R_READ=17,R_LOAD=18,R_FB_MUL=19,R_CALC=20,R_WRITE=21,R_WET_MUL=22,R_MIX=23;
    reg [4:0] state;
    reg [2:0] previous_mask,held_mask;
    reg [7:0] previous_settings,held_settings;
    reg [11:0] held_mix;
    reg [15:0] lfo;
    wire [14:0] triangle=lfo[15] ? ~lfo[14:0] : lfo[14:0];
    wire [15:0] modulation=settings[1:0]==0 ? {1'b0,triangle}>>2 :
        settings[1:0]==1 ? {1'b0,triangle}>>1 : settings[1:0]==2 ? {1'b0,triangle} : {triangle,1'b0};
    wire [10:0] chorus_delay=11'd1024+{3'd0,modulation[15:8]};
    reg [10:0] cp,ca;
    reg [11:0] cf,dp;
    reg [12:0] df;
    reg [7:0] fraction;
    reg c_ready0,c_ready1,delay_ready,delay_capture,delay_change;
    reg [2:0] capture_count;
    wire [2:0] capture_last=held_settings[3:2]==1 ? 3'd1 : held_settings[3:2]==2 ? 3'd3 : 3'd5;
    reg signed [15:0] chorus_q,delay_q,reverb_q,c_tap,stage,tap,delay_hold,filtered,delay_write;
    wire [10:0] chorus_read_address=state==C_READ0 ? ca : ca-11'd1;
    reg [9:0] rp[0:5];
    reg [9:0] age,line_length;
    reg [11:0] line_base;
    reg [2:0] line_index;
    reg phase;
    reg signed [15:0] previous_input,network,rev_hold,rev_write,comb_input;
    reg signed [17:0] comb_sum;
    wire [11:0] rev_address=line_base+rp[line_index];
    wire signed [17:0] sum_next=comb_sum+$signed(tap);
    wire signed [17:0] filtered_ext={{2{filtered[15]}},filtered};
    wire signed [17:0] filter_sum=$signed(stage)+
        (held_settings[3:2]==1 ? filtered_ext : filtered_ext+(filtered_ext<<<1));
    wire signed [17:0] filter_next=held_settings[3:2]==1 ? half_z(filter_sum) : quarter_z(filter_sum);
    wire signed [17:0] average_input=$signed(stage)+$signed(previous_input);
    wire signed [15:0] allpass_stored=saturate($signed(network)+half_z($signed(tap)));
    wire signed [17:0] allpass_y=$signed(tap)-half_z($signed(allpass_stored));
    reg signed [17:0] mul_a;
    reg signed [8:0] mul_b;
    reg signed [26:0] product;
    wire signed [17:0] mixed=$signed(stage)+q4_z(product);
    integer i;
    function [15:0] saturate;
        input signed [17:0] x;
        begin if(x>32767)saturate=16'h7fff;else if(x< -32768)saturate=16'h8000;else saturate=x[15:0];end
    endfunction
    function signed [17:0] half_z;
        input signed [17:0] x;
        begin half_z=(x>>>1)+$signed({17'd0,(x[17] && x[0])});end
    endfunction
    function signed [17:0] quarter_z;
        input signed [17:0] x;
        begin quarter_z=(x>>>2)+$signed({17'd0,(x[17] && (|x[1:0]))});end
    endfunction
    function signed [17:0] sixteenth_z;
        input signed [17:0] x;
        begin sixteenth_z=(x>>>4)+$signed({17'd0,(x[17] && (|x[3:0]))});end
    endfunction
    function signed [17:0] q4_z;
        input signed [26:0] x;
        begin q4_z=(x>>>4)+$signed({26'd0,(x[26] && (|x[3:0]))});end
    endfunction
    function signed [17:0] q8_z;
        input signed [26:0] x;
        begin q8_z=(x>>>8)+$signed({26'd0,(x[26] && (|x[7:0]))});end
    endfunction
    // One physical read port and a dedicated output register per RAM.
    always @(posedge clk)begin
        if(state==C_READ0 || state==C_READ1)chorus_q<=chorus_memory[chorus_read_address];
        if(state==D_READ && delay_capture)delay_q<=delay_memory[dp];
        if(state==R_READ)reverb_q<=reverb_memory[rev_address];
    end
    always @* begin
        mul_a=$signed(tap);mul_b=0;
        case(state)
        C_INTERP_MUL:begin mul_a=$signed(tap)-$signed(c_tap);mul_b=$signed({1'b0,fraction});end
        C_WET_MUL:mul_b=$signed({5'd0,held_mix[3:0]});
        D_WET_MUL:mul_b=$signed({5'd0,held_mix[7:4]});
        R_WET_MUL:mul_b=$signed({5'd0,held_mix[11:8]});
        D_FB_MUL:case(held_settings[5:4])0:mul_b=4;1:mul_b=8;2:mul_b=10;default:mul_b=12;endcase
        R_FB_MUL:case(held_settings[7:6])0:mul_b=10;1:mul_b=12;2:mul_b=13;default:mul_b=14;endcase
        default:mul_b=0;
        endcase
        case(line_index)
        0:begin line_base=0;line_length=618;end
        1:begin line_base=618;line_length=658;end
        2:begin line_base=1276;line_length=707;end
        3:begin line_base=1983;line_length=751;end
        4:begin line_base=2734;line_length=308;end
        default:begin line_base=3042;line_length=244;end
        endcase
    end
    always @(posedge clk)begin
        if(!resetn)begin
            state<=IDLE;previous_mask<=0;held_mask<=0;previous_settings<=0;held_settings<=0;held_mix<=0;
            lfo<=0;cp<=0;ca<=0;cf<=0;dp<=0;df<=0;fraction<=0;c_ready0<=0;c_ready1<=0;
            delay_ready<=0;delay_capture<=0;delay_change<=0;capture_count<=0;
            c_tap<=0;stage<=0;tap<=0;delay_hold<=0;filtered<=0;delay_write<=0;product<=0;
            age<=0;line_index<=0;phase<=0;previous_input<=0;network<=0;rev_hold<=0;rev_write<=0;comb_input<=0;comb_sum<=0;
            sample<=0;valid<=0;overrun<=0;
            for(i=0;i<6;i=i+1)rp[i]<=0;
        end else begin
            valid<=0;
            if(sample_valid && state!=IDLE)overrun<=1;
            if(state==C_INTERP_MUL || state==C_WET_MUL || state==D_FB_MUL ||
               state==D_WET_MUL || state==R_FB_MUL || state==R_WET_MUL)product<=mul_a*mul_b;
            case(state)
            IDLE:if(sample_valid)begin
                held_mask<=mask;previous_mask<=mask;held_settings<=settings;previous_settings<=settings;
                held_mix<={wet_mix[11:8]>8 ? 4'd8 : wet_mix[11:8],wet_mix[7:4]>8 ? 4'd8 : wet_mix[7:4],wet_mix[3:0]>8 ? 4'd8 : wet_mix[3:0]};
                stage<=dry;lfo<=lfo+1'b1;fraction<=modulation[7:0];
                if(mask[0]!=previous_mask[0] || settings[1:0]!=previous_settings[1:0])begin
                    cp<=0;cf<=0;ca<=0;c_ready0<=0;c_ready1<=0;
                end else begin
                    ca<=cp-chorus_delay;c_ready0<=cf>=chorus_delay;c_ready1<=cf>chorus_delay;
                end
                delay_change<=mask[1]!=previous_mask[1] || settings[3:2]!=previous_settings[3:2];
                if(mask[1]!=previous_mask[1] || settings[3:2]!=previous_settings[3:2])begin
                    dp<=0;df<=0;capture_count<=0;filtered<=0;delay_hold<=0;
                end
                if(mask[2]!=previous_mask[2] || settings[7:6]!=previous_settings[7:6])begin
                    age<=0;phase<=0;previous_input<=0;network<=0;rev_hold<=0;
                    for(i=0;i<6;i=i+1)rp[i]<=0;
                end
                state<=C_READ0;
            end
            C_READ0:begin chorus_memory[cp]<=stage;cp<=cp+1'b1;if(cf<2048)cf<=cf+1'b1;state<=C_LOAD0;end
            C_LOAD0:begin c_tap<=c_ready0 ? chorus_q : 16'sd0;state<=C_READ1;end
            C_READ1:state<=C_LOAD1;
            C_LOAD1:begin tap<=c_ready1 ? chorus_q : 16'sd0;state<=C_INTERP_MUL;end
            C_INTERP_MUL:state<=C_INTERP_LOAD;
            C_INTERP_LOAD:begin tap<=saturate($signed(c_tap)+q8_z(product));state<=C_WET_MUL;end
            C_WET_MUL:state<=C_MIX;
            C_MIX:begin if(held_mask[0])stage<=saturate(mixed);state<=D_START;end
            D_START:begin
                delay_ready<=df==4096;
                if(held_settings[3:2]==0)begin delay_capture<=1;capture_count<=0;filtered<=0;end
                else if(delay_change)begin
                    delay_capture<=0;capture_count<=1;
                    filtered<=held_settings[3:2]==1 ? half_z($signed(stage)) : quarter_z($signed(stage));
                end else begin
                    filtered<=filter_next[15:0];
                    if(capture_count==capture_last)begin delay_capture<=1;capture_count<=0;end
                    else begin delay_capture<=0;capture_count<=capture_count+1'b1;end
                end
                state<=D_READ;
            end
            D_READ:state<=D_LOAD;
            D_LOAD:begin if(delay_capture)tap<=delay_ready ? delay_q : 16'sd0;else tap<=delay_hold;state<=D_FB_MUL;end
            D_FB_MUL:state<=D_FB_LOAD;
            D_FB_LOAD:begin
                delay_write<=saturate(half_z(held_settings[3:2]==0 ? $signed(stage) : $signed(filtered))+q4_z(product));
                state<=D_WET_MUL;
            end
            D_WET_MUL:state<=D_MIX;
            D_MIX:begin
                delay_hold<=tap;
                if(delay_capture)begin delay_memory[dp]<=delay_write;dp<=dp+1'b1;if(df<4096)df<=df+1'b1;end
                if(held_mask[1])stage<=saturate(mixed);state<=R_START;
            end
            R_START:begin
                previous_input<=stage;phase<=!phase;
                if(!phase && held_mask[2])begin
                    comb_input<=sixteenth_z(average_input);comb_sum<=0;line_index<=0;state<=R_READ;
                end else begin tap<=rev_hold;state<=R_WET_MUL;end
            end
            R_READ:state<=R_LOAD;
            R_LOAD:begin tap<=age>=line_length ? reverb_q : 16'sd0;state<=R_FB_MUL;end
            R_FB_MUL:state<=R_CALC;
            R_CALC:begin
                if(line_index<4)begin
                    rev_write<=saturate($signed(comb_input)+q4_z(product));comb_sum<=sum_next;
                    if(line_index==3)network<=saturate(quarter_z(sum_next));
                end else begin rev_write<=allpass_stored;network<=saturate(allpass_y);end
                state<=R_WRITE;
            end
            R_WRITE:begin
                reverb_memory[rev_address]<=rev_write;
                rp[line_index]<=rp[line_index]==line_length-1 ? 10'd0 : rp[line_index]+1'b1;
                if(line_index==5)begin
                    if(age<751)age<=age+1'b1;rev_hold<=network;tap<=network;state<=R_WET_MUL;
                end else begin line_index<=line_index+1'b1;state<=R_READ;end
            end
            R_WET_MUL:state<=R_MIX;
            R_MIX:begin sample<=held_mask[2] ? saturate(mixed) : stage;valid<=1;state<=IDLE;end
            default:state<=IDLE;
            endcase
        end
    end
endmodule
