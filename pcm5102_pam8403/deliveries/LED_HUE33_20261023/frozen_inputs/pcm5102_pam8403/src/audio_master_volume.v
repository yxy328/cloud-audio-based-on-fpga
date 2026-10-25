`timescale 1ns/1ps
// Continuous master-volume stage. The control and PCM input share clk.
// Q12 gain: 0=mute, 4096=unity. Slew once per stereo frame to soften changes;
// i2s_tx still captures one output sample for both left and right channels.
module audio_master_volume #(
    parameter integer SLEW_STEP=64, // <=1.311ms full-scale at 48828.125Hz
    parameter [12:0] RESET_GAIN=13'd4096
)(
    input wire clk, resetn, frame_ce,
    input wire signed [15:0] sample_in,
    input wire [12:0] target_gain,
    output wire signed [15:0] sample_out,
    output reg [12:0] applied_gain
);
    wire [12:0] bounded_gain=(target_gain>13'd4096) ? 13'd4096 : target_gain;
    wire [13:0] rise_distance={1'b0,bounded_gain}-{1'b0,applied_gain};
    wire [13:0] fall_distance={1'b0,applied_gain}-{1'b0,bounded_gain};
    // Full-width intermediates retain carry/borrow. The distance test makes
    // either selected ramp step stay between the current and bounded gain.
    wire [13:0] rising_gain={1'b0,applied_gain}+SLEW_STEP[13:0];
    wire [13:0] falling_gain={1'b0,applied_gain}-SLEW_STEP[13:0];
    reg signed [29:0] product;
    always @(posedge clk) begin
        if(!resetn) begin
            applied_gain<=(RESET_GAIN>13'd4096) ? 13'd4096 : RESET_GAIN;
            product<=0;
        end else begin
            if(frame_ce) begin
                if(bounded_gain>applied_gain)
                    applied_gain<=(rise_distance>SLEW_STEP) ? rising_gain[12:0] : bounded_gain;
                else if(bounded_gain<applied_gain)
                    applied_gain<=(fall_distance>SLEW_STEP) ? falling_gain[12:0] : bounded_gain;
            end
            product<=sample_in * $signed({1'b0,applied_gain});
        end
    end
    // Attenuation only: the signed result fits 16 bits, including -32768.
    // Exact unity and mute; other gains round towards negative infinity.
    assign sample_out=product[27:12];
endmodule
