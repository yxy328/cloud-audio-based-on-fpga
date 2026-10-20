`timescale 1ns/1ps
// Sixteen independent gated DDS/ADSR contexts, one arithmetic path and
// one 256x16 context RAM. Worst-case 16 simultaneous segment divisions
// complete within the 1024-clock stereo frame. First seven retain remap/bend.
module touch_tdm_synth #(parameter integer VOLUME_SHIFT=4)(
    input wire clk,resetn,sample_ce,
    input wire [15:0] gates,
    input wire [223:0] low_steps,
    input wire [63:0] adsr_config,
    input wire [15:0] pitch_ratio,
    output reg signed [15:0] sample,
    output reg [15:0] active,
    output reg clipped,
    output reg overrun
);
    // Thirteen 16-bit words per voice fit one 18Kbit synchronous RAM.
    // Serial context reads/writes avoid a wide shallow RAM and LUT mux bank.
    (* syn_ramstyle="block_ram" *) reg [15:0] contexts[0:255];
    reg [15:0] context_q;
    reg [7:0] address,init_address;
    reg [3:0] index,field;
    reg [3:0] state;
    localparam INIT=0,IDLE=1,LOAD=2,ENV=3,DIVIDE=4,PITCH=5,PITCH_WAIT=6,
        WAVE=7,GAIN=8,GAIN_WAIT=9,STORE=10,PUBLISH=11,READ_WAIT=12,READ_WORD=13,WAVE_WAIT=14;
    reg [15:0] frame_gates;
    reg [223:0] frame_steps;
    reg [63:0] config_snapshot;
    reg [15:0] ratio_snapshot;
    reg [31:0] phase;
    reg seen;
    reg [2:0] stage;
    reg [15:0] gain,target,ticks,length,step,remainder,error,decay,sustain,release_time;
    reg [15:0] quotient;
    reg [16:0] div_remainder;
    reg [4:0] divide_left;
    reg signed [32:0] mul_a;
    reg signed [17:0] mul_b;
    reg signed [50:0] product;
    reg [31:0] lookup_phase;
    wire signed [15:0] sine;
    reg signed [23:0] sum;
    reg [15:0] context_write;
    always @*begin
        case(field)
            0:context_write=phase[15:0];1:context_write=phase[31:16];
            2:context_write={12'd0,seen,stage};3:context_write=gain;
            4:context_write=target;5:context_write=ticks;6:context_write=length;
            7:context_write=step;8:context_write=remainder;9:context_write=error;
            10:context_write=decay;11:context_write=sustain;default:context_write=release_time;
        endcase
    end
    always @(posedge clk)begin
        if(resetn && (state==INIT || state==STORE))
            contexts[state==INIT ? init_address : {index,field}]<=state==INIT ? 16'd0 : context_write;
    end
    always @(posedge clk)context_q<=contexts[address];
    wire [16:0] next_error={1'b0,error}+{1'b0,remainder};
    wire carry=next_error>={1'b0,length};
    wire [16:0] delta={1'b0,step}+carry;
    // Keep the carry/borrow through the arithmetic, then explicitly select
    // the 16-bit context word. Valid ADSR segments stay in 0..65535.
    wire [16:0] error_next=carry ? next_error-{1'b0,length} : next_error;
    wire [16:0] gain_next=target>=gain ? {1'b0,gain}+delta : {1'b0,gain}-delta;
    // Q16 gain (high keys have one extra attenuation bit). Preserve the
    // arithmetic shift before selecting the signed mixer/monitor widths.
    wire signed [50:0] scaled_product=product>>>(index<7 ? (16+VOLUME_SHIFT) : (17+VOLUME_SHIFT));
    wire [16:0] shifted={div_remainder[15:0],quotient[15]};
    wire subtract=shifted>={1'b0,length};
    wire [16:0] rem_next=subtract ? shifted-{1'b0,length} : shifted;
    wire [15:0] q_next={quotient[14:0],subtract};
    touch_sine_rom u_sine(.clk(clk),.phase(lookup_phase),.sample(sine));
    always @(posedge clk) product<=mul_a*mul_b;
    function [31:0] note_step;
        input [3:0] key;
        begin case(key)
            0:note_step=46025656; 1:note_step=51662052; 2:note_step=57988693;
            3:note_step=61436880; 4:note_step=68960566; 5:note_step=77405619;
            6:note_step=86884869; 7:note_step=92051312; default:note_step=103324105;
        endcase end
    endfunction
    task segment;
        input [2:0] next_stage;
        input [15:0] end_gain, duration;
        begin
            stage<=next_stage;target<=end_gain;
            length<=duration==0 ? 16'd1 : duration;
            ticks<=duration==0 ? 16'd1 : duration;
            quotient<=(end_gain>=gain) ? end_gain-gain : gain-end_gain;
            div_remainder<=0;divide_left<=15;error<=0;state<=DIVIDE;
        end
    endtask
    always @(posedge clk) begin
        if(!resetn) begin
            state<=INIT;index<=0;sample<=0;active<=0;overrun<=0;clipped<=0;sum<=0;
            address<=0;init_address<=0;field<=0;phase<=0;seen<=0;stage<=0;gain<=0;target<=0;ticks<=0;
            length<=1;step<=0;remainder<=0;error<=0;decay<=1;sustain<=0;release_time<=1;
            frame_gates<=0;frame_steps<=0;config_snapshot<=0;ratio_snapshot<=65535;
            quotient<=0;div_remainder<=0;divide_left<=0;mul_a<=0;mul_b<=0;lookup_phase<=0;
        end else begin
            if(sample_ce && state!=IDLE && state!=INIT)overrun<=1;
            case(state)
                INIT:begin
                    if(init_address==255)begin index<=0;state<=IDLE;end else init_address<=init_address+1'b1;
                end
                IDLE:if(sample_ce)begin
                    frame_gates<=gates;frame_steps<=low_steps;config_snapshot<=adsr_config;ratio_snapshot<=pitch_ratio;
                    index<=0;sum<=0;state<=LOAD;
                end
                LOAD:begin field<=0;address<={index,4'd0};state<=READ_WAIT;end
                READ_WAIT:state<=READ_WORD;
                READ_WORD:begin
                    case(field)
                        0:phase[15:0]<=context_q;1:phase[31:16]<=context_q;
                        2:{seen,stage}<=context_q[3:0];3:gain<=context_q;4:target<=context_q;
                        5:ticks<=context_q;6:length<=context_q;7:step<=context_q;
                        8:remainder<=context_q;9:error<=context_q;10:decay<=context_q;
                        11:sustain<=context_q;12:release_time<=context_q;
                    endcase
                    if(field==12)state<=ENV;
                    else begin field<=field+1'b1;address<=address+1'b1;state<=READ_WAIT;end
                end
                ENV:begin
                    seen<=frame_gates[index];state<=PITCH;
                    if(frame_gates[index] && !seen)begin
                        decay<=config_snapshot[47:32];sustain<=config_snapshot[31:16];release_time<=config_snapshot[15:0];
                        segment(1,65535,config_snapshot[63:48]);
                    end else if(!frame_gates[index] && seen)begin
                        if(gain==0)stage<=0;else segment(4,0,release_time);
                    end else if(stage==1 || stage==2 || stage==4)begin
                        if(ticks<=1)begin
                            gain<=target;
                            if(stage==1)begin
                                // Attack ends at 65535; use that committed level
                                // as the origin of the decay division.
                                stage<=2;target<=sustain;length<=decay==0 ? 16'd1 : decay;
                                ticks<=decay==0 ? 16'd1 : decay;quotient<=65535-sustain;
                                div_remainder<=0;divide_left<=15;error<=0;state<=DIVIDE;
                            end else stage<=stage==2 ? 3 : 0;
                        end else begin
                            ticks<=ticks-1'b1;error<=error_next[15:0];
                            gain<=gain_next[15:0];
                        end
                    end else if(stage==3)gain<=sustain;
                    else gain<=0;
                end
                DIVIDE:begin
                    quotient<=q_next;div_remainder<=rem_next;
                    if(divide_left==0)begin step<=q_next;remainder<=rem_next[15:0];state<=PITCH;end
                    else divide_left<=divide_left-1'b1;
                end
                PITCH:begin mul_a<=$signed({1'b0,note_step(index-4'd7)});mul_b<=$signed({2'b0,ratio_snapshot});state<=PITCH_WAIT;end
                PITCH_WAIT:state<=WAVE;
                WAVE:begin
                    lookup_phase<=phase;
                    phase<=phase+((index<7) ? frame_steps[index*32+:32] :
                        (ratio_snapshot==65535) ? note_step(index-4'd7) : product[47:16]);
                    state<=WAVE_WAIT;
                end
                WAVE_WAIT:state<=GAIN;
                GAIN:begin mul_a<=$signed(sine);mul_b<=$signed({2'b0,gain});state<=GAIN_WAIT;end
                GAIN_WAIT:begin field<=0;state<=STORE;end
                STORE:begin
                    if(field==0)begin sum<=sum+$signed(scaled_product[23:0]);active[index]<=stage!=0;end
                    if(field==12)begin
                        if(index==15)state<=PUBLISH;else begin index<=index+1'b1;state<=LOAD;end
                    end else field<=field+1'b1;
                end
                PUBLISH:begin
                    clipped<=sum>32767 || sum< -32768;
                    sample<=sum>32767 ? 16'sh7fff : sum< -32768 ? 16'sh8000 : sum[15:0];state<=IDLE;
                end
                default:state<=INIT;
            endcase
        end
    end
`ifndef SYNTHESIS
    reg [255:0] voice_samples;
    always @(posedge clk)begin
        if(!resetn)voice_samples<=0;
        else if(state==STORE && field==0)voice_samples[index*16+:16]<=scaled_product[15:0];
    end
    wire [255:0] gains;
    wire [47:0] states;
    wire [511:0] phases;
    genvar debug_voice;
    generate for(debug_voice=0;debug_voice<16;debug_voice=debug_voice+1)begin: debug_state
        assign gains[debug_voice*16+:16]=contexts[debug_voice*16+3];
        assign states[debug_voice*3+:3]=contexts[debug_voice*16+2][2:0];
        assign phases[debug_voice*32+:32]={contexts[debug_voice*16+1],contexts[debug_voice*16]};
    end endgenerate
`endif
endmodule
