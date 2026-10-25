`timescale 1ns/1ps

// Slow-GAO observation of the 50 MHz touch/UI domain (Verilog-2001).
// Capture on the master's falling edge: a GAO clock derived from a
// rising-edge divider then has half a master cycle of setup time.
// A 20 us event makes every debounced press/release visible at 3.125 MHz.
module gao_touch_debug (
    input wire        clk,
    input wire        resetn,
    input wire [15:0] touch_keys,
    input wire [15:0] keys_stable,
    input wire        image_requested,
    input wire [3:0]  brightness_requested,
    input wire        image_active,
    input wire [3:0]  brightness_active,
    input wire        touch_valid,
    (* syn_keep = 1, syn_preserve = 1 *)
    output reg [43:0] gao_probe
);
    // 1000 master periods at 50 MHz = 20 us. A change starts the first
    // period immediately, and the counter retains the next 999 periods.
    localparam [9:0] EVENT_REMAINING = 10'd999;
    reg [15:0] keys_stable_d;
    reg [9:0] event_remaining;
    wire stable_changed = (keys_stable != keys_stable_d);
    wire event_active = stable_changed || (event_remaining != 10'd0);

    // Match TOP's startup state even if resetn starts low and the divided
    // GAO clock has never run: T selected, full brightness (level 8).
    initial begin
        keys_stable_d = 16'h0000;
        event_remaining = 10'd0;
        gao_probe = {1'b0, 1'b0, 4'd8, 1'b0, 4'd8, 1'b0,
                     16'h0000, 16'h0000};
    end

    always @(negedge clk or negedge resetn) begin
        if (!resetn) begin
            keys_stable_d <= 16'h0000;
            event_remaining <= 10'd0;
            gao_probe <= {1'b0, 1'b0, 4'd8, 1'b0, 4'd8, 1'b0,
                          16'h0000, 16'h0000};
        end
        else begin
            keys_stable_d <= keys_stable;
            if (stable_changed)
                event_remaining <= EVENT_REMAINING;
            else if (event_remaining != 10'd0)
                event_remaining <= event_remaining - 1'b1;

            // [15:0] raw; [31:16] stable; [32] requested image;
            // [36:33] requested brightness; [37] active image;
            // [41:38] active brightness; [42] frame valid;
            // [43] debounced-key change event (press or release).
            gao_probe <= {event_active, touch_valid, brightness_active,
                          image_active, brightness_requested,
                          image_requested, keys_stable, touch_keys};
        end
    end
endmodule
