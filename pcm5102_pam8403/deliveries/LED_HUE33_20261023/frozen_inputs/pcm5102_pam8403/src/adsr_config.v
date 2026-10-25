`timescale 1ns/1ps
// Atomic profile conversion. One small serial divider serves both profiles;
// ms -> samples is exactly ms*3125/64 at Fs=48828.125Hz, rounded nearest.
module adsr_config #(
    parameter [15:0] DEFAULT_A=98, DEFAULT_D=3906,
    DEFAULT_S=39321, DEFAULT_R=488
)(
    input wire clk,resetn,request,restore,profile,
    input wire [15:0] attack_ms,decay_ms,sustain_percent,release_ms,
    output reg done,
    output reg [63:0] touch_config,
    // {enable,A16,D16,R16,S9,Astep24,Dstep24,Rstep24}.
    output reg [129:0] sensor_config
);
    localparam IDLE=0,LOAD=1,DIVIDE=2,COMMIT=3,PREPARE=4,CONVERT=5;
    reg [2:0] state,multiply_left;
    reg [1:0] field;
    reg target;
    reg [47:0] times;
    reg [6:0] percentage;
    reg [15:0] a,d,r,s;
    reg [23:0] sa,sd,sr;
    reg [24:0] quotient;
    reg [16:0] remainder;
    reg [15:0] divisor;
    reg [4:0] left;
    // 3125=5^5. Five serial shift-add clocks replace a long six-adder path.
    // Even the full unsigned 16-bit input times 3125 fits 28 bits.
    reg [27:0] product;
    wire [15:0] ticks=(product[27:6]==0) ? 16'd1 : product[21:6];
    wire [16:0] shifted={remainder[15:0],quotient[24]};
    wire subtract=shifted>={1'b0,divisor};
    wire [16:0] rem_next=subtract ? shifted-{1'b0,divisor} : shifted;
    wire [24:0] q_next={quotient[23:0],subtract};
    wire [23:0] step=q_next[24] ? 24'hffffff : q_next[23:0];
    wire [16:0] rounded_s={1'b0,s}+17'd128;
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE;field<=0;target<=0;times<=0;percentage<=0;
            a<=1;d<=1;r<=1;s<=0;sa<=0;sd<=0;sr<=0;
            quotient<=0;remainder<=0;divisor<=1;left<=0;done<=0;
            product<=0;multiply_left<=0;
            touch_config<={DEFAULT_A,DEFAULT_D,DEFAULT_S,DEFAULT_R};sensor_config<=0;
        end else begin
            done<=0;
            case(state)
                IDLE:if(request) begin
                    if(restore) begin
                        if(profile) sensor_config<=0;
                        else touch_config<={DEFAULT_A,DEFAULT_D,DEFAULT_S,DEFAULT_R};
                        done<=1;
                    end else begin
                        target<=profile;times<={attack_ms,decay_ms,release_ms};
                        percentage<=sustain_percent[6:0];field<=0;state<=PREPARE;
                    end
                end
                PREPARE:begin
                    product<={12'd0,times[47:32]};multiply_left<=5;
                    state<=(field==3) ? LOAD : CONVERT;
                end
                CONVERT:begin
                    product<=(product<<2)+product+((multiply_left==1) ? 28'd32 : 28'd0);
                    multiply_left<=multiply_left-1'b1;
                    if(multiply_left==1)state<=LOAD;
                end
                LOAD:begin
                    remainder<=0;left<=24;state<=DIVIDE;
                    if(field==3) begin
                        quotient<=({18'd0,percentage}<<16)-percentage;divisor<=100;
                    end else begin
                        quotient<=25'h1000000;divisor<=ticks;
                        if(field==0) a<=ticks;
                        else if(field==1) d<=ticks;
                        else r<=ticks;
                        times<={times[31:0],16'd0};
                    end
                end
                DIVIDE:begin
                    remainder<=rem_next;quotient<=q_next;
                    if(left==0) begin
                        if(field==0) sa<=step;
                        else if(field==1) sd<=step;
                        else if(field==2) sr<=step;
                        else s<=q_next[15:0];
                        if(field==3) state<=COMMIT;
                        else begin field<=field+1'b1;state<=PREPARE;end
                    end else left<=left-1'b1;
                end
                COMMIT:begin
                    if(target) sensor_config<={1'b1,a,d,r,rounded_s[16:8],sa,sd,sr};
                    else touch_config<={a,d,s,r};
                    done<=1;state<=IDLE;
                end
            endcase
        end
    end
endmodule
