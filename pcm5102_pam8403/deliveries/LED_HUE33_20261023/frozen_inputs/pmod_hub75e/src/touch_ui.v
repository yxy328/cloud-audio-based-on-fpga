// TTP229 frame debounce and display controls (Verilog-2001).
// Hardware assumptions: TP2 selects 16-key serial mode; TP3 + TP4 select
// multi-key mode. Power-cycle after changing jumpers. ttp229_ctrl converts
// the default active-low SDO into touch_keys[i] = 1 for key i + 1.
// The top-level keeps SCL / SDO on F6 / F7 and supplies this module with
// the same clock as ttp229_ctrl. A 20 us valid pulse is sampled only once.
// Display-domain synchronization / PWM-boundary updates belong in TOP.
module touch_ui #(
    parameter integer STABLE_FRAMES = 3,
    parameter MODE_CONTROL = 0
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        touch_valid,
    input  wire [15:0] touch_keys,
    output reg  [15:0] keys_stable,
    output reg  [15:0] key_press,
    output reg         image_sel,   // 0 = logoT (default), 1 = logoS
    output reg  [3:0]  brightness,  // 1 .. 8, default 8
    input wire         clear_keys,
    input wire         mode_16
);
    // Constant function avoids SystemVerilog $clog2 and a zero-width
    // counter when STABLE_FRAMES = 1. Treat smaller values as one frame.
    function integer counter_width;
        input integer value;
        integer remaining;
        begin
            remaining = value;
            counter_width = 0;
            while (remaining > 0) begin
                counter_width = counter_width + 1;
                remaining = remaining >> 1;
            end
            if (counter_width == 0)
                counter_width = 1;
        end
    endfunction

    localparam integer FRAME_LIMIT = (STABLE_FRAMES < 1) ? 1 : STABLE_FRAMES;
    localparam integer COUNT_WIDTH = counter_width(FRAME_LIMIT);

    reg                valid_d;
    reg [15:0]         candidate;
    reg [COUNT_WIDTH-1:0] same_count;

    wire frame_start = touch_valid && !valid_d;
    wire accept_frame = (FRAME_LIMIT == 1) ||
                        ((touch_keys == candidate) &&
                         (same_count >= FRAME_LIMIT - 1));
    wire [15:0] press_now = touch_keys & ~keys_stable;
    wire minus_press = (MODE_CONTROL && !mode_16) ? press_now[6] : press_now[14];
    wire plus_press = (MODE_CONTROL && !mode_16) ? press_now[7] : press_now[15];

    always @(posedge clk) begin
        if (!resetn) begin
            valid_d     <= 1'b0;
            candidate   <= 16'h0000;
            same_count  <= {COUNT_WIDTH{1'b0}};
            keys_stable <= 16'h0000;
            key_press   <= 16'h0000;
            image_sel   <= 1'b0;
            brightness  <= 4'd8;
        end
        else if (MODE_CONTROL && clear_keys) begin
            // Discard old-mode debounce and events; retain display settings.
            valid_d <= 1'b0;
            candidate <= 16'h0000;
            same_count <= 0;
            keys_stable <= 16'h0000;
            key_press <= 16'h0000;
        end else begin
            valid_d   <= touch_valid;
            key_press <= 16'h0000;

            if (frame_start) begin
                // Compare the entire 16-bit frame: three matching frames
                // are required for both press and release by default.
                if (touch_keys != candidate) begin
                    candidate  <= touch_keys;
                    same_count <= 1;
                end
                else if (same_count < FRAME_LIMIT)
                    same_count <= same_count + 1'b1;

                if (accept_frame) begin
                    keys_stable <= touch_keys;
                    key_press   <= press_now;

                    // Process this event in the same clock as acceptance.
                    // Key 2 (T) wins if keys 1 and 2 are pressed together.
                    if (press_now[1])
                        image_sel <= 1'b0;
                    else if (press_now[0])
                        image_sel <= 1'b1;

                    // Keys 15 / 16 are minus / plus. Simultaneous events
                    // cancel, and holding a key never repeats the action.
                    if (minus_press && !plus_press) begin
                        if (brightness > 4'd1)
                            brightness <= brightness - 1'b1;
                    end
                    else if (plus_press && !minus_press) begin
                        if (brightness < 4'd8)
                            brightness <= brightness + 1'b1;
                    end
                end
            end
        end
    end
endmodule
