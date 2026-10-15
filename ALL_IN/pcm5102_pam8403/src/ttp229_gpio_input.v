`timescale 1ns/1ps
// Eight parallel OUT pins; startup inhibition and independent key debounce.
module ttp229_gpio_input #(
    parameter CLK_FREQ = 50_000_000,
    parameter STARTUP_US = 600000,
    parameter DEBOUNCE_MS = 2,
    parameter ACTIVE_LOW = 0
) (
    input wire clk, resetn, enable,
    input wire [7:0] touch_out,
    output wire [7:0] keys_raw,
    output reg [7:0] keys_stable,
    output reg sample_valid, ready
);
    localparam integer START_CYCLES = (CLK_FREQ/1000000)*STARTUP_US;
    localparam integer TICK_CYCLES = CLK_FREQ/1000;
    (* syn_preserve = 1 *) reg [7:0] meta, sync;
    reg [31:0] startup_count, tick_count;
    reg [31:0] counts [0:7];
    integer k;
    assign keys_raw = ACTIVE_LOW ? ~sync : sync;
    always @(posedge clk) begin
        if (!resetn || !enable) begin
            meta <= ACTIVE_LOW ? 8'hff : 0;
            sync <= ACTIVE_LOW ? 8'hff : 0;
            startup_count <= 0; tick_count <= 0;
            keys_stable <= 0; ready <= 0; sample_valid <= 0;
            for (k=0; k<8; k=k+1) counts[k] <= 0;
        end else begin
            meta <= touch_out; sync <= meta; sample_valid <= 0;
            if (!ready) begin
                if (START_CYCLES <= 1 || startup_count == START_CYCLES-1)
                    ready <= 1;
                else startup_count <= startup_count+1'b1;
            end else if (tick_count == TICK_CYCLES-1) begin
                tick_count <= 0; sample_valid <= 1;
                for (k=0; k<8; k=k+1) begin
                    if (keys_raw[k] == keys_stable[k]) counts[k] <= 0;
                    else if (DEBOUNCE_MS <= 1 || counts[k] == DEBOUNCE_MS-1) begin
                        keys_stable[k] <= keys_raw[k]; counts[k] <= 0;
                    end else counts[k] <= counts[k]+1'b1;
                end
            end else tick_count <= tick_count+1'b1;
        end
    end
endmodule
