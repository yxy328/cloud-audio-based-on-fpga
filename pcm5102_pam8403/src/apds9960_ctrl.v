`timescale 1ns/1ps
// ============================================================================
//  APDS-9960: fast FIFO draining, channel means and gesture tracking.
//  Direction uses the normalized first/last strong samples across FIFO reads.
// ============================================================================

module apds9960_ctrl #(
    parameter DELAY_INIT = 5_000_000,
    parameter DELAY_POLL = 500_000,   // 10ms idle/calibration delay at 50MHz
    parameter DELAY_ACTIVE = 100_000, // 2ms while tracking a hand
    parameter [2:0] QUIET_POLLS = 3'd3,
    parameter [23:0] RELEASE_HOLD_CYCLES = 24'd750_000, // 15ms since last signal
    // Margins ABOVE the measured background, not absolute ADC thresholds.
    // Keep the view clear during the first 32 polls after initialization.
    parameter [9:0] SIGNAL_SUM = 10'd40,
    parameter [9:0] RELEASE_SUM = 10'd20,
    parameter ENABLE_BASELINE = 1,
    parameter [7:0] GESTURE_CONFIG2 = 8'h29, // 2x gain, 50 mA, 2.8 ms wait
    parameter [7:0] GESTURE_PULSE = 8'hC9    // ten 32 us pulses (was 42)
) (
    input  wire       clk,
    input  wire       rst_n,

    output reg        i2c_start,
    output reg [6:0]  i2c_addr,
    output reg [7:0]  i2c_reg,
    output reg        i2c_rw,
    output reg [7:0]  i2c_wdata,
    output reg [7:0]  i2c_rdlen,
    input  wire       i2c_busy,
    input  wire       i2c_done,
    input  wire       i2c_nack,
    input  wire [7:0] i2c_rdata,
    input  wire       i2c_rvalid,

    output reg        gesture_valid,
    output reg [7:0]  raw_u, raw_d, raw_l, raw_r,  // FIFO channel means
    output reg [2:0]  start_dir,  // 起点方向 0=无 1=上 2=下 3=左 4=右
    output reg [2:0]  end_dir,    // 终点方向
    output reg        init_done,
    output reg [7:0]  dbg_peak,        // 最近一次 FIFO 批次的峰值通道计数
    output reg        dir_evaluated,   // 1 = 本次上报来自方向判定 (否则只是采样)
    output wire [7:0] dbg_gstatus,
    output wire [7:0] dbg_gflvl,
    output reg [7:0]  dbg_id, dbg_enable, dbg_proximity, dbg_error,
    output reg [7:0]  dbg_nack_count, dbg_nack_reg,
    output reg [7:0]  dbg_gconf2, dbg_gpulse
);

    localparam [6:0] DEV_ADDR = 7'h39;

    localparam [7:0]
        R_ENABLE  = 8'h80, R_ATIME   = 8'h81, R_WTIME   = 8'h83,
        R_PPULSE  = 8'h8E, R_CONFIG2 = 8'h90, R_GPENTH  = 8'hA0,
        R_GEXTH   = 8'hA1, R_GCONF1  = 8'hA2, R_GCONF2  = 8'hA3,
        R_GPULSE  = 8'hA6, R_GCONF4  = 8'hAB, R_GFLVL   = 8'hAE,
        R_GSTATUS = 8'hAF, R_GFIFO   = 8'hFC,
        R_ID      = 8'h92, R_PDATA   = 8'h9C;

    // Sticky error bits: NACK, ID, ENABLE, FIFO level, overflow, short read.
    localparam [7:0] ERR_NACK = 8'h01, ERR_ID = 8'h02,
        ERR_ENABLE = 8'h04, ERR_LEVEL = 8'h08,
        ERR_OVERFLOW = 8'h10, ERR_SHORT = 8'h20, ERR_CONFIG = 8'h40;

    // Sensor setup: reduce gain with VL powered; INT is unused (polling).
    reg [7:0] init_reg, init_val;
    reg [3:0] init_step;

    always @(*) begin
        case (init_step)
        4'd0 :  begin init_reg = R_ENABLE;  init_val = 8'h00; end
        4'd1 :  begin init_reg = R_WTIME;   init_val = 8'hFF; end
        4'd2 :  begin init_reg = R_ATIME;   init_val = 8'hFF; end
        4'd3 :  begin init_reg = R_PPULSE;  init_val = 8'h8F; end
        4'd4 :  begin init_reg = R_CONFIG2; init_val = 8'h01; end
        4'd5 :  begin init_reg = R_GPENTH;  init_val = 8'h05; end
        4'd6 :  begin init_reg = R_GEXTH;   init_val = 8'h03; end
        4'd7 :  begin init_reg = R_GCONF1;  init_val = 8'h00; end
        4'd8 :  begin init_reg = R_GCONF2;  init_val = GESTURE_CONFIG2; end
        4'd9 :  begin init_reg = R_GPULSE;  init_val = GESTURE_PULSE; end
        4'd10:  begin init_reg = R_ENABLE;  init_val = 8'h05; end
        4'd11:  begin init_reg = R_GCONF4;  init_val = 8'h01; end // GMODE, no INT
        4'd12:  begin init_reg = R_ENABLE;  init_val = 8'h45; end
        default: begin init_reg = R_ENABLE; init_val = 8'h00; end
        endcase
    end

    // ================= 状态机 =================
    localparam [4:0]
        S_INIT_DELAY = 5'd0, S_INIT_WR    = 5'd1, S_INIT_WAIT  = 5'd2,
        S_POLL_DELAY = 5'd3, S_RD_STATUS  = 5'd4, S_WAIT_STATUS= 5'd5,
        S_RD_GFLVL   = 5'd6, S_WAIT_GFLVL = 5'd7, S_RD_FIFO    = 5'd8,
        S_WAIT_FIFO  = 5'd9, S_RD_ID = 5'd10, S_WAIT_ID = 5'd11,
        S_RD_ENABLE = 5'd12, S_WAIT_ENABLE = 5'd13,
        S_RD_PROX = 5'd14, S_WAIT_PROX = 5'd15,
        S_REPORT = 5'd16, S_FINISH_POLL = 5'd17,
        S_AVERAGE = 5'd18, S_DIR_DELTA = 5'd19,
        S_DIR_STRENGTH = 5'd20, S_DIR_REPORT = 5'd21,
        S_RD_GCONF2 = 5'd22, S_WAIT_GCONF2 = 5'd23,
        S_RD_GPULSE = 5'd24, S_WAIT_GPULSE = 5'd25;

    reg [4:0]  state;
    reg [23:0] delay_cnt;
    reg [7:0]  gstatus_reg, gflvl_reg;
    reg [7:0]  batch_peak;
    reg [1:0]  byte_phase;
    reg [7:0]  dataset_cnt;    // 当前数据集序号 (0 起)
    reg [15:0] acc_u, acc_d, acc_l, acc_r;
    reg [7:0] sample_u, sample_d, sample_l;
    reg read_seen, batch_signal, batch_overflow;
    wire [7:0] read_value = i2c_rvalid ? i2c_rdata :
        (state == S_WAIT_ID ? dbg_id :
         state == S_WAIT_ENABLE ? dbg_enable :
         state == S_WAIT_GCONF2 ? dbg_gconf2 :
         state == S_WAIT_GPULSE ? dbg_gpulse :
         state == S_WAIT_STATUS ? gstatus_reg : gflvl_reg);

    reg event_active, event_bad;
    reg [7:0] event_samples;
    reg [2:0] quiet_polls;
    reg [23:0] silence_cycles;
    reg baseline_ready;
    reg [5:0] calibration_polls;
    reg [12:0] cal_u, cal_d, cal_l, cal_r;
    // Q8.6 background. A 1/64 update avoids absorbing a slow, distant swipe.
    reg [13:0] base_u, base_d, base_l, base_r;
    wire [7:0] corrected_u = sample_u > base_u[13:6] ? sample_u - base_u[13:6] : 8'd0;
    wire [7:0] corrected_d = sample_d > base_d[13:6] ? sample_d - base_d[13:6] : 8'd0;
    wire [7:0] corrected_l = sample_l > base_l[13:6] ? sample_l - base_l[13:6] : 8'd0;
    wire [7:0] corrected_r = i2c_rdata > base_r[13:6] ? i2c_rdata - base_r[13:6] : 8'd0;
    wire sample_saturated = sample_u >= 8'd250 || sample_d >= 8'd250 ||
                            sample_l >= 8'd250 || i2c_rdata >= 8'd250;
    wire [7:0] poll_u = gflvl_reg == 0 ? 8'd0 : raw_u;
    wire [7:0] poll_d = gflvl_reg == 0 ? 8'd0 : raw_d;
    wire [7:0] poll_l = gflvl_reg == 0 ? 8'd0 : raw_l;
    wire [7:0] poll_r = gflvl_reg == 0 ? 8'd0 : raw_r;
    reg signed [8:0] first_ud, first_lr, last_ud, last_lr;
    reg [8:0] first_ud_sum, first_lr_sum, last_ud_sum, last_lr_sum;
    wire signed [8:0] sample_ud =
        $signed({1'b0, corrected_u}) - $signed({1'b0, corrected_d});
    wire signed [8:0] sample_lr =
        $signed({1'b0, corrected_l}) - $signed({1'b0, corrected_r});
    wire [8:0] sample_ud_sum = {1'b0, corrected_u} + {1'b0, corrected_d};
    wire [8:0] sample_lr_sum = {1'b0, corrected_l} + {1'b0, corrected_r};
    // Subtract the TOTAL background before clamping: summing four clamped
    // channels would turn ordinary zero-mean noise into a positive signal.
    wire [9:0] sample_sum = {2'b0, sample_u} + {2'b0, sample_d} +
                           {2'b0, sample_l} + {2'b0, i2c_rdata};
    wire [9:0] background_sum = {2'b0, base_u[13:6]} + {2'b0, base_d[13:6]} +
                               {2'b0, base_l[13:6]} + {2'b0, base_r[13:6]};
    wire [9:0] signal_excess = sample_sum > background_sum ? sample_sum - background_sum : 10'd0;
    // Brighter backgrounds in the captured logs also have larger fluctuations.
    // Keep a proportional noise margin there, while using the lower configured
    // thresholds on the now-dark idle readings (typically only a few counts).
    wire [9:0] noise_start_margin = background_sum >> 2;
    wire [9:0] noise_release_margin = background_sum >> 3;
    wire [9:0] start_margin = SIGNAL_SUM > noise_start_margin ? SIGNAL_SUM : noise_start_margin;
    wire [9:0] release_margin = RELEASE_SUM > noise_release_margin ? RELEASE_SUM : noise_release_margin;
    wire sample_present = baseline_ready &&
        signal_excess >= (event_active ? release_margin : start_margin);
    wire received_signal = state == S_WAIT_FIFO && i2c_rvalid &&
                           byte_phase == 2'd3 && sample_present;

    // Empty FIFO does not necessarily mean the hand has left: at the faster
    // polling rate we can read between two optical conversions. Require an
    // elapsed-time guard as well as multiple quiet polls. Refresh on clipped
    // data too, since those samples still prove that a hand is present.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) silence_cycles <= 0;
        else if (!event_active || received_signal) silence_cycles <= 0;
        else if (silence_cycles < RELEASE_HOLD_CYCLES)
            silence_cycles <= silence_cycles + 1'b1;
    end

    assign dbg_gstatus = gstatus_reg;
    assign dbg_gflvl   = gflvl_reg;

    // Cross products compare changes in (U-D)/(U+D) and (L-R)/(L+R).
    // A 25% change is required; brightness changes alone do not imply motion.
    reg signed [19:0] delta_ud, delta_lr;
    wire [19:0] abs_ud = delta_ud[19] ? -delta_ud : delta_ud;
    wire [19:0] abs_lr = delta_lr[19] ? -delta_lr : delta_lr;
    reg [19:0] scale_ud, scale_lr;
    wire ud_motion = scale_ud != 0 && {abs_ud, 2'b00} >= {2'b00, scale_ud};
    wire lr_motion = scale_lr != 0 && {abs_lr, 2'b00} >= {2'b00, scale_lr};
    reg [39:0] ud_strength, lr_strength;
    reg [2:0] start_dir_c, end_dir_c;

    always @(*) begin
        start_dir_c = 3'd0;
        end_dir_c = 3'd0;
        if (event_samples >= 8'd4 && !event_bad) begin
            if (ud_motion && (!lr_motion || ud_strength >= lr_strength)) begin
                start_dir_c = delta_ud[19] ? 3'd1 : 3'd2;
                end_dir_c = delta_ud[19] ? 3'd2 : 3'd1;
            end else if (lr_motion) begin
                start_dir_c = delta_lr[19] ? 3'd3 : 3'd4;
                end_dir_c = delta_lr[19] ? 3'd4 : 3'd3;
            end
        end
    end

    // ================= 主状态机 =================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INIT_DELAY; init_step <= 4'd0; init_done <= 1'b0;
            i2c_start <= 1'b0; i2c_addr <= DEV_ADDR;
            i2c_reg <= 8'd0; i2c_rw <= 1'b0; i2c_wdata <= 8'd0; i2c_rdlen <= 8'd1;
            delay_cnt <= 24'd0; gstatus_reg <= 8'd0; gflvl_reg <= 8'd0;
            byte_phase <= 2'd0; dataset_cnt <= 8'd0;
            gesture_valid <= 1'b0;
            raw_u <= 8'd0; raw_d <= 8'd0; raw_l <= 8'd0; raw_r <= 8'd0;
            start_dir <= 3'd0; end_dir <= 3'd0;
            acc_u <= 16'd0; acc_d <= 16'd0; acc_l <= 16'd0; acc_r <= 16'd0;
            sample_u <= 0; sample_d <= 0; sample_l <= 0;
            read_seen <= 0; batch_signal <= 0; batch_overflow <= 0;
            dbg_id <= 0; dbg_enable <= 0; dbg_proximity <= 0; dbg_error <= 0;
            dbg_nack_count <= 0; dbg_nack_reg <= 0;
            dbg_gconf2 <= 0; dbg_gpulse <= 0;
            dbg_peak <= 0; dir_evaluated <= 0; batch_peak <= 0;
            event_active <= 0; event_bad <= 0; event_samples <= 0; quiet_polls <= 0;
            baseline_ready <= !ENABLE_BASELINE; calibration_polls <= 0;
            cal_u <= 0; cal_d <= 0; cal_l <= 0; cal_r <= 0;
            base_u <= 0; base_d <= 0; base_l <= 0; base_r <= 0;
            first_ud <= 0; first_lr <= 0; last_ud <= 0; last_lr <= 0;
            first_ud_sum <= 0; first_lr_sum <= 0;
            last_ud_sum <= 0; last_lr_sum <= 0;
            delta_ud <= 0; delta_lr <= 0; scale_ud <= 0; scale_lr <= 0;
            ud_strength <= 0; lr_strength <= 0;
        end else begin
            gesture_valid <= 1'b0;
            i2c_start <= 1'b0;
            // Count transactions, not cycles: nack stays asserted until the
            // next command. Preserve this history across successful retries.
            if (i2c_done && i2c_nack) begin
                if (dbg_nack_count != 8'hFF) dbg_nack_count <= dbg_nack_count + 1'b1;
                dbg_nack_reg <= i2c_reg;
            end

            case (state)
            S_INIT_DELAY: begin
                if (delay_cnt >= DELAY_INIT) begin delay_cnt <= 24'd0; state <= S_RD_ID; end
                else delay_cnt <= delay_cnt + 1'b1;
            end

            S_RD_ID: begin
                if (!i2c_busy) begin
                    i2c_addr <= DEV_ADDR; i2c_reg <= R_ID; i2c_rw <= 1'b1;
                    i2c_rdlen <= 8'd1; i2c_start <= 1'b1; read_seen <= 0;
                    state <= S_WAIT_ID;
                end
            end

            S_WAIT_ID: begin
                if (i2c_rvalid) begin dbg_id <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        state <= S_INIT_DELAY;
                    // Compatible IDs also accepted by ESPHome's APDS9960 driver.
                    end else if (read_value != 8'hAB && read_value != 8'h9C &&
                                 read_value != 8'hA8 && read_value != 8'h9E) begin
                        dbg_error <= dbg_error | ERR_ID; state <= S_INIT_DELAY;
                    end else begin
                        init_step <= 0; state <= S_INIT_WR;
                    end
                end
            end

            S_INIT_WR: begin
                if (!i2c_busy) begin
                    i2c_addr <= DEV_ADDR; i2c_reg <= init_reg; i2c_rw <= 1'b0;
                    i2c_wdata <= init_val; i2c_rdlen <= 8'd1; i2c_start <= 1'b1;
                    state <= S_INIT_WAIT;
                end
            end

            S_INIT_WAIT: begin
                if (i2c_done) begin
                    if (i2c_nack) begin
                        dbg_error <= dbg_error | ERR_NACK; state <= S_INIT_DELAY;
                    end
                    else if (init_step == 4'd12) state <= S_RD_ENABLE;
                    else begin init_step <= init_step + 1'b1; state <= S_INIT_WR; end
                end
            end

            S_RD_ENABLE: begin
                if (!i2c_busy) begin
                    i2c_reg <= R_ENABLE; i2c_rw <= 1'b1; i2c_rdlen <= 1;
                    i2c_start <= 1; read_seen <= 0; state <= S_WAIT_ENABLE;
                end
            end

            S_WAIT_ENABLE: begin
                if (i2c_rvalid) begin dbg_enable <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        state <= S_INIT_DELAY;
                    end else if (read_value != 8'h45) begin
                        dbg_error <= dbg_error | ERR_ENABLE; state <= S_INIT_DELAY;
                    end else begin
                        state <= S_RD_GCONF2;
                    end
                end
            end

            S_RD_GCONF2: begin
                if (!i2c_busy) begin
                    i2c_reg <= R_GCONF2; i2c_rw <= 1; i2c_rdlen <= 1;
                    i2c_start <= 1; read_seen <= 0; state <= S_WAIT_GCONF2;
                end
            end

            S_WAIT_GCONF2: begin
                if (i2c_rvalid) begin dbg_gconf2 <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        state <= S_INIT_DELAY;
                    end else if (read_value != GESTURE_CONFIG2) begin
                        dbg_error <= dbg_error | ERR_CONFIG;
                        state <= S_INIT_DELAY;
                    end else state <= S_RD_GPULSE;
                end
            end

            S_RD_GPULSE: begin
                if (!i2c_busy) begin
                    i2c_reg <= R_GPULSE; i2c_rw <= 1; i2c_rdlen <= 1;
                    i2c_start <= 1; read_seen <= 0; state <= S_WAIT_GPULSE;
                end
            end

            S_WAIT_GPULSE: begin
                if (i2c_rvalid) begin dbg_gpulse <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        state <= S_INIT_DELAY;
                    end else if (read_value != GESTURE_PULSE) begin
                        dbg_error <= dbg_error | ERR_CONFIG;
                        state <= S_INIT_DELAY;
                    end else begin
                        init_done <= 1; state <= S_POLL_DELAY;
                    end
                end
            end

            S_POLL_DELAY: begin
                if (delay_cnt >= (event_active ? DELAY_ACTIVE : DELAY_POLL)) begin
                    delay_cnt <= 24'd0;
                    state <= S_RD_STATUS;
                end
                else delay_cnt <= delay_cnt + 1'b1;
            end

            S_RD_STATUS: begin
                i2c_addr <= DEV_ADDR; i2c_reg <= R_GSTATUS; i2c_rw <= 1'b1;
                i2c_rdlen <= 8'd1; i2c_start <= 1'b1; state <= S_WAIT_STATUS;
                read_seen <= 0; batch_signal <= 0; batch_peak <= 8'd0;
            end

            S_WAIT_STATUS: begin
                if (i2c_rvalid) begin gstatus_reg <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        event_bad <= 1; event_active <= 0; event_samples <= 0;
                        state <= S_POLL_DELAY;
                    end else begin
                        batch_overflow <= read_value[1];
                        if (read_value[1]) begin
                            dbg_error <= dbg_error | ERR_OVERFLOW;
                            event_bad <= 1;
                        end
                        state <= S_RD_PROX;
                    end
                end
            end

            S_RD_PROX: begin
                i2c_reg <= R_PDATA; i2c_rw <= 1; i2c_rdlen <= 1;
                i2c_start <= 1; read_seen <= 0; state <= S_WAIT_PROX;
            end

            S_WAIT_PROX: begin
                if (i2c_rvalid) begin dbg_proximity <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        event_bad <= 1; event_active <= 0; event_samples <= 0;
                        state <= S_POLL_DELAY;
                    end else state <= S_RD_GFLVL;
                end
            end

            S_RD_GFLVL: begin
                i2c_addr <= DEV_ADDR; i2c_reg <= R_GFLVL; i2c_rw <= 1'b1;
                i2c_rdlen <= 8'd1; i2c_start <= 1'b1; state <= S_WAIT_GFLVL;
                read_seen <= 0;
            end

            S_WAIT_GFLVL: begin
                if (i2c_rvalid) begin gflvl_reg <= i2c_rdata; read_seen <= 1; end
                if (i2c_done) begin
                    if (i2c_nack || !(read_seen || i2c_rvalid)) begin
                        dbg_error <= dbg_error | (i2c_nack ? ERR_NACK : ERR_SHORT);
                        event_bad <= 1; event_active <= 0; event_samples <= 0;
                        state <= S_POLL_DELAY;
                    end else if (read_value > 8'd32) begin
                        dbg_error <= dbg_error | ERR_LEVEL;
                        event_bad <= 1; event_active <= 0; event_samples <= 0;
                        state <= S_POLL_DELAY;
                    end else if (read_value != 8'd0) begin
                        dataset_cnt <= 8'd0;
                        byte_phase <= 2'd0;
                        acc_u <= 0; acc_d <= 0; acc_l <= 0; acc_r <= 0;
                        state <= S_RD_FIFO;
                    end else begin
                        state <= S_FINISH_POLL;
                    end
                end
            end

            S_RD_FIFO: begin
                i2c_addr <= DEV_ADDR; i2c_reg <= R_GFIFO; i2c_rw <= 1'b1;
                i2c_rdlen <= {gflvl_reg[5:0], 2'b00};
                i2c_start <= 1'b1; state <= S_WAIT_FIFO;
            end

            S_WAIT_FIFO: begin
                if (i2c_rvalid) begin
                    if (i2c_rdata > batch_peak) batch_peak <= i2c_rdata;
                    case (byte_phase)
                    2'd0: begin acc_u <= acc_u + i2c_rdata; sample_u <= i2c_rdata; end
                    2'd1: begin acc_d <= acc_d + i2c_rdata; sample_d <= i2c_rdata; end
                    2'd2: begin acc_l <= acc_l + i2c_rdata; sample_l <= i2c_rdata; end
                    2'd3: begin
                        acc_r <= acc_r + i2c_rdata;
                        if (sample_present) begin
                            batch_signal <= 1;
                            if (!batch_overflow) begin
                                event_active <= 1;
                                // Clipped samples keep the event alive, but
                                // cannot become its directional endpoints.
                                if (!sample_saturated && sample_ud_sum >= 8 && sample_lr_sum >= 8) begin
                                    if (event_samples == 0) begin
                                        first_ud <= sample_ud; first_lr <= sample_lr;
                                        first_ud_sum <= sample_ud_sum;
                                        first_lr_sum <= sample_lr_sum;
                                        event_samples <= 1;
                                    end else if (event_samples != 8'hFF)
                                        event_samples <= event_samples + 1'b1;
                                    last_ud <= sample_ud; last_lr <= sample_lr;
                                    last_ud_sum <= sample_ud_sum;
                                    last_lr_sum <= sample_lr_sum;
                                end
                            end
                        end
                    end
                    endcase
                    if (byte_phase == 2'd3) begin
                        byte_phase <= 2'd0;
                        dataset_cnt <= dataset_cnt + 1'b1;
                    end else begin
                        byte_phase <= byte_phase + 1'b1;
                    end
                end
                if (i2c_done) begin
                    if (i2c_nack) begin
                        dbg_error <= dbg_error | ERR_NACK;
                        event_bad <= 1; event_active <= 0; event_samples <= 0;
                        state <= S_POLL_DELAY;
                    end else state <= S_REPORT;
                end
            end

            S_REPORT: begin
                if (dataset_cnt == gflvl_reg && byte_phase == 0) begin
                    raw_u <= 0; raw_d <= 0; raw_l <= 0; raw_r <= 0;
                    state <= S_AVERAGE;
                end else begin
                    dbg_error <= dbg_error | ERR_SHORT;
                    event_bad <= 1; event_active <= 0; event_samples <= 0;
                    state <= S_POLL_DELAY;
                end
            end

            S_AVERAGE: begin
                // At most 255 subtractions (5.1 us), avoiding a long divider.
                if (acc_u >= {8'd0, gflvl_reg}) begin
                    acc_u <= acc_u - {8'd0, gflvl_reg}; raw_u <= raw_u + 1'b1;
                end
                if (acc_d >= {8'd0, gflvl_reg}) begin
                    acc_d <= acc_d - {8'd0, gflvl_reg}; raw_d <= raw_d + 1'b1;
                end
                if (acc_l >= {8'd0, gflvl_reg}) begin
                    acc_l <= acc_l - {8'd0, gflvl_reg}; raw_l <= raw_l + 1'b1;
                end
                if (acc_r >= {8'd0, gflvl_reg}) begin
                    acc_r <= acc_r - {8'd0, gflvl_reg}; raw_r <= raw_r + 1'b1;
                end
                if (acc_u < {8'd0, gflvl_reg} && acc_d < {8'd0, gflvl_reg} &&
                    acc_l < {8'd0, gflvl_reg} && acc_r < {8'd0, gflvl_reg}) begin
                    start_dir <= 0; end_dir <= 0; dir_evaluated <= 1'b0;
                    dbg_peak <= batch_peak;
                    // Publish only batches above the calibrated presence gate.
                    // Heartbeat PK remains available while the gate is closed.
                    if (batch_signal) gesture_valid <= 1;
                    state <= S_FINISH_POLL;
                end
            end

            S_FINISH_POLL: begin
                state <= S_POLL_DELAY;
                // Calibrate from 32 complete polls (empty FIFO counts as zero).
                // At 50 MHz this takes about 0.4 seconds; allow 2 s at boot.
                if (!baseline_ready && !batch_overflow) begin
                    cal_u <= cal_u + poll_u; cal_d <= cal_d + poll_d;
                    cal_l <= cal_l + poll_l; cal_r <= cal_r + poll_r;
                    if (calibration_polls == 31) begin
                        base_u <= ({1'b0, cal_u} + {6'd0, poll_u}) << 1;
                        base_d <= ({1'b0, cal_d} + {6'd0, poll_d}) << 1;
                        base_l <= ({1'b0, cal_l} + {6'd0, poll_l}) << 1;
                        base_r <= ({1'b0, cal_r} + {6'd0, poll_r}) << 1;
                        baseline_ready <= 1;
                    end else calibration_polls <= calibration_polls + 1'b1;
                end else if (ENABLE_BASELINE && !event_active && !batch_signal &&
                             gflvl_reg != 0 && !batch_overflow) begin
                    base_u <= base_u - (base_u >> 6) + {6'd0, raw_u};
                    base_d <= base_d - (base_d >> 6) + {6'd0, raw_d};
                    base_l <= base_l - (base_l >> 6) + {6'd0, raw_l};
                    base_r <= base_r - (base_r >> 6) + {6'd0, raw_r};
                end
                if (batch_signal) quiet_polls <= 0;
                else if (quiet_polls >= QUIET_POLLS - 1'b1) begin
                    // Saturate the poll counter until the real-time absence
                    // guard has elapsed. Never wrap during conversion gaps.
                    if (!event_active || silence_cycles >= RELEASE_HOLD_CYCLES) begin
                        if (event_active && !event_bad) begin
                            state <= S_DIR_DELTA;
                        end else begin
                            event_active <= 0; event_bad <= 0; event_samples <= 0;
                        end
                        quiet_polls <= 0;
                    end
                end else quiet_polls <= quiet_polls + 1'b1;
            end

            S_DIR_DELTA: begin
                delta_ud <= last_ud * $signed({1'b0, first_ud_sum}) -
                    first_ud * $signed({1'b0, last_ud_sum});
                delta_lr <= last_lr * $signed({1'b0, first_lr_sum}) -
                    first_lr * $signed({1'b0, last_lr_sum});
                scale_ud <= first_ud_sum * last_ud_sum;
                scale_lr <= first_lr_sum * last_lr_sum;
                state <= S_DIR_STRENGTH;
            end

            S_DIR_STRENGTH: begin
                ud_strength <= abs_ud * scale_lr;
                lr_strength <= abs_lr * scale_ud;
                state <= S_DIR_REPORT;
            end

            S_DIR_REPORT: begin
                start_dir <= start_dir_c; end_dir <= end_dir_c;
                dir_evaluated <= 1'b1;
                gesture_valid <= 1;
                event_active <= 0; event_bad <= 0; event_samples <= 0;
                state <= S_POLL_DELAY;
            end

            default: state <= S_POLL_DELAY;
            endcase
        end
    end

endmodule

