// Reusable OUT1..OUT8 reader extracted from the standalone GPIO project.
// All eight ports are inputs; default direct output polarity is active-high.
// The startup timer runs in both modes. Disabling clears debounce and frames.
module ttp229_gpio_input #(
    parameter CLK_FREQ = 50_000_000,
    parameter STARTUP_US = 600000,
    parameter DEBOUNCE_MS = 20,
    parameter ACTIVE_LOW = 0,
    parameter VALID_PULSE_US = 20
) (
    input wire clk,
    input wire resetn,
    input wire enable,
    input wire [7:0] touch_out,
    output wire [7:0] keys_raw,
    output reg [7:0] keys_stable,
    output reg sample_valid,
    output reg ready
);
    localparam MS_TICKS = CLK_FREQ / 1000;
    localparam MS_WIDTH = (MS_TICKS < 2) ? 1 : $clog2(MS_TICKS);
    localparam DB_SAMPLES = (DEBOUNCE_MS < 1) ? 1 : DEBOUNCE_MS;
    localparam DB_WIDTH = (DB_SAMPLES < 2) ? 1 : $clog2(DB_SAMPLES);
    localparam STARTUP_TICKS = STARTUP_US * (CLK_FREQ / 1_000_000);
    localparam VALID_TICKS = VALID_PULSE_US * (CLK_FREQ / 1_000_000);
    localparam VALID_WIDTH = (VALID_TICKS < 2) ? 1 : $clog2(VALID_TICKS);
    reg [7:0] input_meta, input_sync;
    reg [MS_WIDTH-1:0] ms_count;
    reg ms_tick;
    reg [31:0] startup_count;
    reg [DB_WIDTH-1:0] debounce_count [0:7];
    reg [VALID_WIDTH-1:0] valid_remaining;
    integer key_index;
    assign keys_raw = ACTIVE_LOW ? ~input_sync : input_sync;

    always @(posedge clk) begin
        if (!resetn) begin
            input_meta <= ACTIVE_LOW ? 8'hff : 8'h00;
            input_sync <= ACTIVE_LOW ? 8'hff : 8'h00;
            ms_count <= 0;
            ms_tick <= 1'b0;
            startup_count <= 0;
            ready <= 1'b0;
        end else begin
            input_meta <= touch_out;
            input_sync <= input_meta;
            if (ms_count == MS_TICKS - 1) begin
                ms_count <= 0;
                ms_tick <= 1'b1;
            end else begin
                ms_count <= ms_count + 1'b1;
                ms_tick <= 1'b0;
            end
            if (!ready) begin
                if (STARTUP_TICKS == 0 || startup_count == STARTUP_TICKS - 1)
                    ready <= 1'b1;
                else
                    startup_count <= startup_count + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn || !ready || !enable) begin
            keys_stable <= 8'd0;
            sample_valid <= 1'b0;
            valid_remaining <= 0;
            for (key_index = 0; key_index < 8; key_index = key_index + 1)
                debounce_count[key_index] <= 0;
        end else begin
            if (ms_tick) begin
                sample_valid <= 1'b1;
                valid_remaining <= VALID_TICKS - 1;
                for (key_index = 0; key_index < 8; key_index = key_index + 1) begin
                    if (keys_raw[key_index] == keys_stable[key_index])
                        debounce_count[key_index] <= 0;
                    else if (debounce_count[key_index] == DB_SAMPLES - 1) begin
                        keys_stable[key_index] <= keys_raw[key_index];
                        debounce_count[key_index] <= 0;
                    end else
                        debounce_count[key_index] <= debounce_count[key_index] + 1'b1;
                end
            end else if (sample_valid) begin
                if (valid_remaining == 0)
                    sample_valid <= 1'b0;
                else
                    valid_remaining <= valid_remaining - 1'b1;
            end
        end
    end
endmodule
