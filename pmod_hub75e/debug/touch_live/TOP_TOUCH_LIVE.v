// Minimal live serial diagnostic; sample CLK_IN even when USER_KEY is low.
module TOP_TOUCH_LIVE #(
    parameter TTP_STARTUP_US = 600000
) (
    input wire CLK_IN,
    input wire USER_KEY,
    output wire touch_scl,
    input wire touch_sdo
);
    (* syn_preserve = 1, syn_keep = 1 *) reg [5:0] power_reset_count = 6'd0;
    (* syn_keep = 1 *) wire power_resetn = &power_reset_count;
    always @(posedge CLK_IN) begin
        if (!power_resetn)
            power_reset_count <= power_reset_count + 6'd1;
    end

    (* syn_keep = 1 *) wire [15:0] touch_keys;
    (* syn_keep = 1 *) wire touch_valid;
    (* syn_keep = 1 *) wire [2:0] state_o;
    (* syn_keep = 1 *) wire [3:0] bit_cnt_o;
    (* syn_keep = 1 *) wire frame_start = (state_o == 3'd1) && (bit_cnt_o == 4'd0);

    // Preserve the serial reader even though its results have no display output.
    // A falling-edge snapshot gives GAO's 50 MHz rising edge 10 ns setup.
    // [28:13] keys, [12] SCL, [11] SDO, [10] valid, [9] USER_KEY,
    // [8] power reset, [7:5] state, [4:1] bit count, [0] frame start.
    (* syn_preserve = 1, syn_keep = 1 *) reg [28:0] live_probe = 29'd0;
    always @(negedge CLK_IN) begin
        live_probe <= {touch_keys, touch_scl, touch_sdo, touch_valid,
                       USER_KEY, power_resetn, state_o, bit_cnt_o, frame_start};
    end

    ttp229_ctrl #(
        .CLK_FREQ(50_000_000), .KEY_NUM(16), .TP_ACTIVE_LOW(1),
        .SCL_HALF_US(10), .VALID_PULSE_US(20),
        .FRAME_IDLE_US(3000), .STARTUP_US(TTP_STARTUP_US)
    ) touch_ctrl (
        .clk(CLK_IN), .resetn(power_resetn),
        .sdo(touch_sdo), .scl(touch_scl),
        .touch_valid(touch_valid), .touch_keys(touch_keys),
        .state_o(state_o), .bit_cnt_o(bit_cnt_o)
    );
endmodule
