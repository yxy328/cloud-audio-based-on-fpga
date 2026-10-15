// Dock S2 is active-high (H10). Default: debounced level 0=8, 1=16.
// TOGGLE_MODE=1 optionally makes each confirmed press toggle the mode.
module ttp229_mode_select #(
    parameter CLK_FREQ = 50_000_000,
    parameter DEBOUNCE_MS = 20,
    parameter TOGGLE_MODE = 0
) (
    input wire clk,
    input wire resetn,
    input wire s2,
    output reg mode_16,
    output reg mode_changed,
    output wire [1:0] state_o
);
    localparam DB_TICKS = (DEBOUNCE_MS < 1) ? 1 :
                         (CLK_FREQ / 1000) * DEBOUNCE_MS;
    localparam DB_WIDTH = (DB_TICKS < 2) ? 1 : $clog2(DB_TICKS);
    localparam [1:0] S_LOW = 2'd0, S_CONFIRM_HIGH = 2'd1,
                     S_HIGH = 2'd2, S_CONFIRM_LOW = 2'd3;
    reg [1:0] s2_sync;
    reg [1:0] state;
    reg [DB_WIDTH-1:0] count;
    assign state_o = state;

    always @(posedge clk) begin
        if (!resetn)
            s2_sync <= 2'b00;
        else
            s2_sync <= {s2_sync[0], s2};
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_LOW;
            count <= 0;
            mode_16 <= 1'b0;
            mode_changed <= 1'b0;
        end else begin
            mode_changed <= 1'b0;
            case (state)
                S_LOW, S_CONFIRM_HIGH: begin
                    if (!s2_sync[1]) begin
                        state <= S_LOW;
                        count <= 0;
                    end else if (count == DB_TICKS - 1) begin
                        state <= S_HIGH;
                        count <= 0;
                        mode_16 <= TOGGLE_MODE ? ~mode_16 : 1'b1;
                        mode_changed <= 1'b1;
                    end else begin
                        state <= S_CONFIRM_HIGH;
                        count <= count + 1'b1;
                    end
                end
                S_HIGH, S_CONFIRM_LOW: begin
                    if (s2_sync[1]) begin
                        state <= S_HIGH;
                        count <= 0;
                    end else if (count == DB_TICKS - 1) begin
                        state <= S_LOW;
                        count <= 0;
                        if (!TOGGLE_MODE) begin
                            mode_16 <= 1'b0;
                            mode_changed <= 1'b1;
                        end
                    end else begin
                        state <= S_CONFIRM_LOW;
                        count <= count + 1'b1;
                    end
                end
                default: begin
                    state <= S_LOW;
                    count <= 0;
                    mode_16 <= 1'b0;
                    mode_changed <= mode_16;
                end
            endcase
        end
    end
endmodule
