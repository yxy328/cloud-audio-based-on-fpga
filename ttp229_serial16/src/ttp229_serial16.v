`timescale 1ns/1ps
// TTP229-BSF ONLY. Two-wire synchronous serial interface, NOT I2C.
// Default hardware: TP1 + TP2 pulled down via the module's high-value resistors.
// TP1 pulled down: active-HIGH, SCL idle LOW, rising edge presents next data bit.
// Sample late in the HIGH phase, before returning SCL LOW.
// TP1 open: set ACTIVE_LOW=1 to invert BOTH clock polarity and data interpretation.
// D0..D15 -> module K1..K16 -> keys[0]..keys[15], 1 means pressed.
module ttp229_serial16 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer ACTIVE_LOW = 0,
    parameter integer HALF_US = 10,         // 50 kHz at the default setting
    parameter integer GAP_US = 10_000,      // >2 ms serial timeout/re-alignment
    parameter integer STARTUP_US = 1_000_000,
    parameter integer FILTER_FRAMES = 3     // independently for press/release
) (
    input  wire        clk,
    input  wire        resetn,              // synchronous active-low reset
    input  wire        sdo,                 // module -> FPGA
    output reg         scl,                 // FPGA -> module
    output reg         ready,               // startup wait complete, NOT link detection
    output reg         frame_valid,         // one clk pulse, raw_keys is a complete frame
    output reg  [15:0] raw_keys,
    output reg  [15:0] keys,                 // filtered state; use this in application
    output reg  [15:0] key_press,            // one clk pulse on confirmed press
    output reg  [15:0] key_release           // one clk pulse on confirmed release
);
    // Supported clock: an integer multiple of 1 MHz, >=1 MHz.
    // Keep HALF_US in 10..500; GAP_US >2000, STARTUP_US >=500000 for real hardware.
    // FILTER_FRAMES >=1. Defaults are validated for the current 50 MHz board.
    localparam integer HALF_TICKS = (CLK_HZ / 1_000_000) * HALF_US;
    localparam integer GAP_TICKS = (CLK_HZ / 1_000_000) * GAP_US;
    localparam integer STARTUP_TICKS = (CLK_HZ / 1_000_000) * STARTUP_US;
    localparam integer FILTER_WIDTH = (FILTER_FRAMES < 2) ? 1 : $clog2(FILTER_FRAMES);
    localparam IDLE_LEVEL = ACTIVE_LOW ? 1'b1 : 1'b0;
    localparam [1:0] STARTUP = 2'd0, ACTIVE = 2'd1, RETURN = 2'd2, GAP = 2'd3;

    // Only the first FF receives asynchronous SDO. No SCL-derived clock.
    (* syn_preserve = 1, syn_keep = 1 *) reg sdo_meta;
    (* syn_preserve = 1, syn_keep = 1 *) reg sdo_sync;
    always @(posedge clk) begin
        if (!resetn) begin
            sdo_meta <= IDLE_LEVEL;
            sdo_sync <= IDLE_LEVEL;
        end else begin
            sdo_meta <= sdo;
            sdo_sync <= sdo_meta;
        end
    end

    reg [1:0] state;
    reg [31:0] timer;
    reg [3:0] bit_index;
    reg [15:0] shift;
    wire pressed_bit = ACTIVE_LOW ? ~sdo_sync : sdo_sync;

    always @(posedge clk) begin
        if (!resetn) begin
            scl <= IDLE_LEVEL;
            ready <= 1'b0;
            frame_valid <= 1'b0;
            raw_keys <= 16'h0000;
            state <= STARTUP;
            timer <= STARTUP_TICKS - 1;
            bit_index <= 0;
            shift <= 0;
        end else begin
            frame_valid <= 1'b0;
            case (state)
                STARTUP: begin
                    if (timer != 0)
                        timer <= timer - 1'b1;
                    else begin
                        ready <= 1'b1;
                        scl <= ~IDLE_LEVEL;
                        timer <= HALF_TICKS - 1;
                        state <= ACTIVE;
                    end
                end
                ACTIVE: begin
                    if (timer != 0)
                        timer <= timer - 1'b1;
                    else begin
                        // Data has settled for 10 us; includes the 2-FF delay.
                        shift[bit_index] <= pressed_bit;
                        scl <= IDLE_LEVEL;
                        timer <= HALF_TICKS - 1;
                        state <= RETURN;
                    end
                end
                RETURN: begin
                    if (timer != 0)
                        timer <= timer - 1'b1;
                    else if (bit_index == 15) begin
                        // Last bit was captured in ACTIVE; never early-exit.
                        raw_keys <= shift;
                        frame_valid <= 1'b1;
                        timer <= GAP_TICKS - 1;
                        state <= GAP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        scl <= ~IDLE_LEVEL;
                        timer <= HALF_TICKS - 1;
                        state <= ACTIVE;
                    end
                end
                GAP: begin
                    if (timer != 0)
                        timer <= timer - 1'b1;
                    else begin
                        bit_index <= 0;
                        shift <= 0;
                        scl <= ~IDLE_LEVEL;
                        timer <= HALF_TICKS - 1;
                        state <= ACTIVE;
                    end
                end
                default: begin
                    scl <= IDLE_LEVEL;
                    ready <= 1'b0;
                    bit_index <= 0;
                    shift <= 0;
                    timer <= STARTUP_TICKS - 1;
                    state <= STARTUP;
                end
            endcase
        end
    end

    // Filter COMPLETE frames, not SDO edges or repeated samples of one frame.
    // A glitch on one key does not restart another key's confirmation.
    reg [FILTER_WIDTH-1:0] disagree_count [0:15];
    integer k;
    always @(posedge clk) begin
        if (!resetn) begin
            keys <= 0;
            key_press <= 0;
            key_release <= 0;
            for (k = 0; k < 16; k = k + 1)
                disagree_count[k] <= 0;
        end else begin
            key_press <= 0;
            key_release <= 0;
            if (frame_valid) begin
                for (k = 0; k < 16; k = k + 1) begin
                    if (raw_keys[k] == keys[k])
                        disagree_count[k] <= 0;
                    else if (disagree_count[k] == FILTER_FRAMES - 1) begin
                        keys[k] <= raw_keys[k];
                        key_press[k] <= raw_keys[k];
                        key_release[k] <= ~raw_keys[k];
                        disagree_count[k] <= 0;
                    end else
                        disagree_count[k] <= disagree_count[k] + 1'b1;
                end
            end
        end
    end
endmodule
