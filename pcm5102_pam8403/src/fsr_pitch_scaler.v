`timescale 1ns/1ps
// Seven notes share a smooth Q0.16 frequency ratio. DDS phases are untouched.
// Full scale is bypassed so volume mode retains the exact original pitches.
// One shared, pipelined multiplier updates the seven steps round-robin.
// Registered select -> two 16x16 products -> registered sum/output bank.
// One scan per audio frame avoids switching the shared DSPs while idle.
// Launch AFTER sample_ce so the newly slewed ratio is used for the next frame.
module fsr_pitch_scaler #(
    parameter integer PER_VOICE_BEND=0,
    parameter [223:0] NOTE_INCREMENTS = {
        32'd43442435, 32'd38702809, 32'd34480283, 32'd30718440,
        32'd28994347, 32'd25831026, 32'd23012828
    }
) (
    input wire clk,
    input wire resetn,
    input wire sample_ce,
    input wire [15:0] pitch_ratio,
    input wire [223:0] note_increments,
    input wire bend_write,bend_reset,
    input wire [2:0] bend_index,
    input wire [15:0] bend_ratio,
    output wire [255:0] phase_increments
);
    generate if(PER_VOICE_BEND) begin: individual
        voice_pitch_scaler #(.NOTE_INCREMENTS(NOTE_INCREMENTS)) u_bend (
            .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.pitch_ratio(pitch_ratio),
            .note_increments(note_increments),.bend_write(bend_write),.bend_reset(bend_reset),
            .bend_index(bend_index),.bend_ratio(bend_ratio),.phase_increments(phase_increments));
    end else begin: legacy
    reg [255:0] increments;
    assign phase_increments=increments;
    reg [2:0] select_index, selected_index, product_index;
    reg [31:0] selected_base, product_base;
    reg [15:0] selected_ratio;
    reg [31:0] product_low, product_high;
    reg product_full;
    reg [1:0] valid_pipe;
    reg scan_active;
    always @(posedge clk) begin
        if (!resetn) begin
            select_index<=0; selected_index<=0; product_index<=0;
            selected_base<=0; selected_ratio<=16'hffff; product_base<=0;
            product_low<=0; product_high<=0; product_full<=1; valid_pipe<=0;
            scan_active<=0;
            increments<={32'd0,NOTE_INCREMENTS};
        end else begin
            if (scan_active) begin
                if (select_index==6) scan_active<=0;
                else select_index<=select_index+1'b1;
                selected_index<=select_index;
                selected_base<=note_increments[select_index*32 +: 32];
                selected_ratio<=pitch_ratio;
            end else if (sample_ce) begin
                scan_active<=1;
                select_index<=0;
            end
            if (valid_pipe[0]) begin
                product_index<=selected_index;
                product_base<=selected_base;
                product_full<=selected_ratio==16'hffff;
                product_low<=selected_base[15:0]*selected_ratio;
                product_high<=selected_base[31:16]*selected_ratio;
            end
            valid_pipe<={valid_pipe[0],scan_active};
            if (valid_pipe[1])
                increments[product_index*32 +: 32] <= product_full ? product_base :
                    product_high + {16'd0,product_low[31:16]};
        end
    end
    end endgenerate
endmodule

// Per-touch Q2.14 bend, multiplied after the common FSR Q0.16 ratio.
// A distributed target bank plus one current-value RAM save one BSRAM.
// The shared multiplier and original 43-clock scan schedule are retained.
module voice_pitch_scaler #(
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
    // Tiny target bank uses LUT RAM, with synchronous capture of old data
    // on a same-edge UART write, matching the original target pipeline.
    (* syn_ramstyle="distributed_ram" *) reg [15:0] targets[0:7];
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
        target_q<=targets[index];
        // The read result is used in LOAD, after a READ cycle. Hold it on
        // writes to infer supported normal mode, avoiding read-before-write.
        if(!(resetn && (state==INIT || state==LOAD))) current_q<=currents[index];
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
