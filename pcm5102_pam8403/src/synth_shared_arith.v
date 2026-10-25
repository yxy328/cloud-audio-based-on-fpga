`timescale 1ns/1ps
// Fixed sensor-priority arbitration. The sensor reserves every result until
// consumption; the touch controller waits only in its request states.
// Both clients consume the registered result before the next clock replaces it.
module synth_shared_arith(
    input wire clk,
    input wire sensor_mul_request, touch_mul_request,
    input wire signed [32:0] sensor_mul_a, touch_mul_a,
    input wire signed [17:0] sensor_mul_b, touch_mul_b,
    output wire touch_mul_grant,
    output reg signed [50:0] product,
    input wire sensor_sine_request, touch_sine_request,
    input wire [31:0] sensor_sine_phase, touch_sine_phase,
    output wire touch_sine_grant,
    output wire signed [15:0] sine
);
    wire signed [32:0] mul_a=sensor_mul_request ? sensor_mul_a : touch_mul_a;
    wire signed [17:0] mul_b=sensor_mul_request ? sensor_mul_b : touch_mul_b;
    assign touch_mul_grant=touch_mul_request && !sensor_mul_request;
    always @(posedge clk)product<=mul_a*mul_b;
    wire [31:0] sine_phase=sensor_sine_request ? sensor_sine_phase : touch_sine_phase;
    assign touch_sine_grant=touch_sine_request && !sensor_sine_request;
    touch_sine_rom u_sine(.clk(clk),.phase(sine_phase),.sample(sine));
endmodule
