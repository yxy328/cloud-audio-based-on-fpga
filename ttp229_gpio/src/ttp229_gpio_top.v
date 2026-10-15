`timescale 1ns/1ps
// TTP229-BSF OUT1..OUT8 direct-input test, Tang Primer 25K Dock J3 GPIO.
// Module OUT1 -> touch_out[0] ... OUT8 -> touch_out[7]; all FPGA INPUTS.
// Default direct outputs are CMOS ACTIVE-HIGH, unlike the serial output.
// Use 3.3V power and common ground. TP2 must match the selected mode.
// S2 (H10) toggles mode: 0=OUT1..8, 1=16-key SCL/SDO.
// SCL is now driven by FPGA F6; remove the old fixed 3.3V SCL connection.
module ttp229_gpio_top #(
    parameter CLK_FREQ = 50_000_000,
    parameter STARTUP_MS = 600,
    parameter DEBOUNCE_MS = 20,
    parameter ACTIVE_LOW = 0,
    parameter SERIAL_ACTIVE_LOW = 1,
    parameter S2_DEBOUNCE_MS = 20,
    parameter S2_TOGGLE_MODE = 1
) (
    input wire CLK_IN,
    input wire [7:0] touch_out,
    input wire S2,
    input wire touch_sdo,
    output wire touch_scl
);
    localparam MS_TICKS = CLK_FREQ / 1000;
    localparam MS_COUNT_WIDTH = (MS_TICKS < 2) ? 1 : $clog2(MS_TICKS);
    localparam DEBOUNCE_WIDTH = (DEBOUNCE_MS < 2) ? 1 : $clog2(DEBOUNCE_MS);

    // Automatic reset; module calibration gets another 600 ms below.
    reg [5:0] power_reset_count = 6'd0;
    (* syn_keep = 1 *) wire power_resetn = &power_reset_count;
    always @(posedge CLK_IN) begin
        if (!power_resetn)
            power_reset_count <= power_reset_count + 6'd1;
    end

    // Two-stage synchronization for eight independent asynchronous inputs.
    (* syn_keep = 1 *) wire mode_16;
    wire mode_changed;
    wire [1:0] mode_state;
    ttp229_mode_select #(
        .CLK_FREQ(CLK_FREQ), .DEBOUNCE_MS(S2_DEBOUNCE_MS),
        .TOGGLE_MODE(S2_TOGGLE_MODE)
    ) mode_select (
        .clk(CLK_IN), .resetn(power_resetn), .s2(S2),
        .mode_16(mode_16), .mode_changed(mode_changed), .state_o(mode_state)
    );

    reg [7:0] input_meta;
    reg [7:0] input_sync;
    wire [7:0] gpio_keys_raw = ACTIVE_LOW ? ~input_sync : input_sync;
    wire [15:0] serial_keys;
    wire serial_valid;
    wire [2:0] serial_state;
    wire [3:0] serial_bit_cnt;
    (* syn_keep = 1 *) reg ready;
    (* syn_keep = 1 *) wire [15:0] keys_raw = mode_16 ? serial_keys : {8'd0, gpio_keys_raw};
    // No serial clocks in GPIO mode. Re-enable waits >2ms to realign K1.
    ttp229_ctrl #(
        .CLK_FREQ(CLK_FREQ), .KEY_NUM(16), .TP_ACTIVE_LOW(SERIAL_ACTIVE_LOW),
        .STARTUP_US(3000), .ENABLE_CONTROL(1)
    ) serial_ctrl (
        .clk(CLK_IN), .resetn(power_resetn), .sdo(touch_sdo), .scl(touch_scl),
        .touch_valid(serial_valid), .touch_keys(serial_keys),
        .state_o(serial_state), .bit_cnt_o(serial_bit_cnt),
        .mode_16(1'b1), .enable(mode_16 && ready)
    );
    always @(posedge CLK_IN) begin
        if (!power_resetn) begin
            input_meta <= ACTIVE_LOW ? 8'hff : 8'h00;
            input_sync <= ACTIVE_LOW ? 8'hff : 8'h00;
        end else begin
            input_meta <= touch_out;
            input_sync <= input_meta;
        end
    end

    // A clock enable, rather than another clock domain, samples at 1 ms.
    reg [MS_COUNT_WIDTH-1:0] ms_count;
    reg ms_tick;
    always @(posedge CLK_IN) begin
        if (!power_resetn) begin
            ms_count <= 0;
            ms_tick <= 1'b0;
        end else if (ms_count == MS_TICKS - 1) begin
            ms_count <= 0;
            ms_tick <= 1'b1;
        end else begin
            ms_count <= ms_count + 1'b1;
            ms_tick <= 1'b0;
        end
    end

    reg [31:0] startup_count;
    always @(posedge CLK_IN) begin
        if (!power_resetn) begin
            startup_count <= 0;
            ready <= 1'b0;
        end else if (!ready) begin
            if (STARTUP_MS == 0)
                ready <= 1'b1;
            else if (ms_tick) begin
                if (startup_count == STARTUP_MS - 1)
                    ready <= 1'b1;
                else
                    startup_count <= startup_count + 1'b1;
            end
        end
    end

    // Debounce each key independently: 20 successive 1 ms samples must
    // disagree with its confirmed value before either press or release
    // is accepted. A short glitch on one key does not delay other keys.
    (* syn_keep = 1 *) reg [15:0] keys_stable;
    reg [DEBOUNCE_WIDTH-1:0] debounce_count [0:15];
    integer key_index;
    always @(posedge CLK_IN) begin
        if (!power_resetn || !ready || mode_changed) begin
            keys_stable <= 16'd0;
            for (key_index = 0; key_index < 16; key_index = key_index + 1)
                debounce_count[key_index] <= 0;
        end else if (ms_tick) begin
            for (key_index = 0; key_index < 16; key_index = key_index + 1) begin
                if (keys_raw[key_index] == keys_stable[key_index])
                    debounce_count[key_index] <= 0;
                else if (debounce_count[key_index] == DEBOUNCE_MS - 1) begin
                    keys_stable[key_index] <= keys_raw[key_index];
                    debounce_count[key_index] <= 0;
                end else
                    debounce_count[key_index] <= debounce_count[key_index] + 1'b1;
            end
        end
    end

    // Internal heartbeat can be observed in GAO without consuming a pin.
    reg [8:0] heartbeat_ms;
    (* syn_keep = 1 *) reg heartbeat;
    always @(posedge CLK_IN) begin
        if (!power_resetn) begin
            heartbeat_ms <= 9'd0;
            heartbeat <= 1'b0;
        end else if (ms_tick) begin
            if (heartbeat_ms == 9'd499) begin
                heartbeat_ms <= 9'd0;
                heartbeat <= ~heartbeat;
            end else
                heartbeat_ms <= heartbeat_ms + 1'b1;
        end
    end

    // Stretch a confirmed-key change to 1 ms for reliable GAO triggering.
    reg [15:0] stable_d;
    reg [MS_COUNT_WIDTH-1:0] event_remaining;
    wire stable_changed = (keys_stable != stable_d);
    wire key_event = mode_changed || stable_changed || (event_remaining != 0);
    always @(posedge CLK_IN) begin
        if (!power_resetn) begin
            stable_d <= 16'd0;
            event_remaining <= 0;
        end else begin
            stable_d <= keys_stable;
            if (stable_changed || mode_changed)
                event_remaining <= MS_TICKS - 1;
            else if (event_remaining != 0)
                event_remaining <= event_remaining - 1'b1;
        end
    end

    // CLK_IN/256 = 195.3125 kHz. 16384 samples cover 83.886 ms, enough
    // to compare the input edge and 20 ms debounce. Never gated by reset.
    (* syn_preserve = 1, syn_keep = 1 *) reg [7:0] gao_div = 8'd0;
    wire [7:0] gao_div_next = gao_div + 8'd1;
    // Keep a separate clock register, with no feedback from its own Q.
    // The counter Q remains ordinary CLK_IN-domain data; only this Q is
    // the generated-clock root. This avoids assigning a clock to feedback.
    (* syn_preserve = 1, syn_keep = 1 *) reg gao_clock = 1'b0;
    always @(posedge CLK_IN) begin
        gao_div <= gao_div_next;
        // One master-cycle phase delay keeps this register distinct from
        // gao_div[7]. Its transitions still occur on master rising edges.
        gao_clock <= gao_div[7];
    end

    // Capture on the opposite master edge before GAO samples.
    // [7:0] OUT pins; [23:8] raw keys; [39:24] confirmed keys;
    // [40] resetn; [41] ready; [42] heartbeat; [43] event; [44] GAO phase;
    // [45] mode; [46] S2; [47] SCL; [48] SDO; [49] serial_valid;
    // [52:50] serial FSM; [56:53] bit index; [58:57] S2 debounce FSM.
    (* syn_preserve = 1, syn_keep = 1 *) reg [58:0] gao_probe = 59'd0;
    always @(negedge CLK_IN) begin
        gao_probe <= {mode_state, serial_bit_cnt, serial_state, serial_valid,
                      touch_sdo, touch_scl, S2, mode_16,
                      gao_clock, key_event, heartbeat, ready, power_resetn,
                      keys_stable, keys_raw, touch_out};
    end
endmodule
