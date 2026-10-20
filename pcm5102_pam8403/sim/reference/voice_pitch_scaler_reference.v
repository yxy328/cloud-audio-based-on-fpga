`timescale 1ns/1ps
module voice_pitch_scaler_reference #(
    parameter [223:0] NOTE_INCREMENTS={32'd43442435,32'd38702809,32'd34480283,
        32'd30718440,32'd28994347,32'd25831026,32'd23012828},
    parameter [15:0] SLEW_STEP=16
)(
    input wire clk,resetn,sample_ce,
    input wire [15:0] pitch_ratio,
    input wire [223:0] note_increments,
    input wire bend_write,bend_reset,
    input wire [2:0] bend_index,
    input wire [15:0] bend_ratio,
    output reg [255:0] phase_increments
);
    localparam INIT=0,IDLE=1,READ=2,LOAD=3,FSR_WAIT=4,FSR_DONE=5,BEND_WAIT=6,BEND_DONE=7;
    (* syn_ramstyle="block_ram" *) reg [15:0] targets[0:7];
    (* syn_ramstyle="block_ram" *) reg [15:0] currents[0:7];
    reg [15:0] target_q,current_q;
    reg [3:0] clear_left;
    reg [2:0] index,state;
    reg [15:0] frame_ratio,selected_bend,mul_ratio;
    reg [25:0] mul_base;
    reg [41:0] product;
    wire [15:0] next_current=(target_q>current_q) ?
        ((target_q-current_q>SLEW_STEP) ? current_q+SLEW_STEP : target_q) :
        ((current_q-target_q>SLEW_STEP) ? current_q-SLEW_STEP : target_q);
    always @(posedge clk) begin
        target_q<=targets[index]; current_q<=currents[index];
        if(resetn) begin
            if(clear_left!=0) targets[clear_left[2:0]-3'd1]<=16'd16384;
            else if(bend_write && bend_index<7 && bend_ratio>=8192 && bend_ratio<=32768)
                targets[bend_index]<=bend_ratio;
            if(state==INIT) currents[index]<=16'd16384;
            else if(state==LOAD) currents[index]<=next_current;
        end
        product<=mul_base*mul_ratio;
    end
    always @(posedge clk) begin
        if(!resetn) begin
            clear_left<=8; index<=0;state<=INIT;
            frame_ratio<=65535;selected_bend<=16384;mul_ratio<=16384;mul_base<=0;
            phase_increments<={32'd0,NOTE_INCREMENTS};
        end else begin
            if(bend_reset) clear_left<=8;
            else if(clear_left!=0)clear_left<=clear_left-1'b1;
            case(state)
                INIT:if(index==7)begin index<=0;state<=IDLE;end else index<=index+1'b1;
                IDLE:if(sample_ce)begin index<=0;state<=READ;end
                READ:begin
                    if(index==0)frame_ratio<=pitch_ratio;
                    state<=LOAD;
                end
                LOAD:begin
                    selected_bend<=next_current;
                    mul_base<=note_increments[index*32 +: 26];mul_ratio<=frame_ratio;
                    state<=FSR_WAIT;
                end
                FSR_WAIT:state<=FSR_DONE;
                FSR_DONE:begin
                    mul_base<=(frame_ratio==65535) ? mul_base : product[41:16];
                    mul_ratio<=selected_bend;state<=BEND_WAIT;
                end
                BEND_WAIT:state<=BEND_DONE;
                BEND_DONE:begin
                    phase_increments[index*32 +: 32]<={5'd0,product[40:14]};
                    if(index==6)state<=IDLE;
                    else begin index<=index+1'b1;state<=READ;end
                end
            endcase
        end
    end
endmodule
