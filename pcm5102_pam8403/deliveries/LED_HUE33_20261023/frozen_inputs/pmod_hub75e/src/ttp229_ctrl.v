//----------------------------------------------------------------------
// ttp229_ctrl.v
//
// TTP229-BSF（HW-136 / 8229BSF）电容触摸芯片 —— 2 线串口模式读取模块
//
// 信号方向（以 FPGA 为准）：
//   scl : FPGA -> 模块，串行时钟（FPGA 输出）
//   sdo : 模块 -> FPGA，串行数据（FPGA 输入）
//
// 时序：
//   默认低有效模式 SCL 空闲高、下降沿开始读位；高有效模式则空闲低、
//   上升沿开始读位。FPGA 在有效电平期间末尾采样 SDO，采完最后一位
//   后输出一个 touch_valid 脉冲，
//   同时把这一帧的结果锁存到 touch_keys。
//   默认 SCL 半周期 50us（约 10kHz），16 位读取耗时约 1.6ms。
//   每帧 valid 后保持 SCL 空闲 3ms，使 >2ms 无边沿超时能重新对齐。
//   复位后先保持空闲 600ms，覆盖芯片约 0.5s 的启动稳定期。
//
// 【硬件前提 - 很重要】
//   1) 模块 TP2 配置为低选择 16 键，可读全部 16 位或只读前 8 位；
//      TP2 默认高时选择 8 键。芯片的 8 键模式也支持 SCL/SDO 串口，
//      因此“未短接 TP2”本身不能证明 SDO 恒高或串口被禁用。
//   2) TP3 和 TP4 都短接 = 多键模式；不短接 = 单键模式（串口都能用）。
//   3) 改动跳线后必须【断电再上电】，option 只在开机瞬间锁存。
//   4) SDO 默认是低有效（TP0/TP1 不短接 = CMOS active-low）：
//      空闲高，按下为低。TP1 同时控制 SCL 和 SDO 的有效极性；
//      TP_ACTIVE_LOW 必须与模块 TP1 一致；它同时设置 SCL 波形和 SDO 译码。
//
// 移植时只需要三样东西：
//   1) 把本文件加进工程；
//   2) 顶层加 touch_scl / touch_sdo 两个端口并实例化；
//   3) 约束文件里给这两个端口分配管脚（SDO 建议配 PULL_MODE=UP）。
//   state_o / bit_cnt_o 只是给在线逻辑分析仪（GAO）观察用的，
//   不需要时可以在实例化时留空。
//----------------------------------------------------------------------

module ttp229_ctrl #(
    parameter CLK_FREQ       = 50_000_000, // 输入时钟频率 (Hz)
    parameter KEY_NUM        = 16,         // 静态读取位数/输出宽度；动态模式须为 16
    parameter TP_ACTIVE_LOW  = 1,          // 1: SDO 低有效（TTP229-BSF 默认）
    parameter SCL_HALF_US    = 50,         // SCL 半周期 (us)
    parameter VALID_PULSE_US = 20,         // touch_valid 脉冲宽度 (us)
    parameter FRAME_IDLE_US  = 3000,       // valid 后 SCL 空闲静置 (us)
    parameter STARTUP_US     = 600000,     // 复位后首次读帧等待 (us)
    parameter DYNAMIC_MODE   = 0,          // 1: KEY_NUM=16, mode_16 selects 8/16
    parameter ENABLE_CONTROL = 0          // 1: enable=0 keeps SCL idle
) (
    input  wire             clk,
    input  wire             resetn,        // 低有效复位

    input  wire             sdo,           // 模块串行数据输入
    output reg              scl,           // 串行时钟输出，空闲电平取决于极性

    output reg              touch_valid,   // 一帧读完成脉冲（宽 VALID_PULSE_US）
    output reg  [KEY_NUM-1:0] touch_keys,  // bit i 对应串口第 i+1 键，1 = 按下

    // 调试观测信号（GAO 用，可悬空）
    output wire [2:0]       state_o,
    output wire [3:0]       bit_cnt_o,
    input wire             mode_16,       // synchronized/debounced by caller
    input wire             enable
);

    //------------------------------------------------------------------
    // 定时参数换算
    //------------------------------------------------------------------
    localparam TICKS_PER_US   = CLK_FREQ / 1_000_000;
    localparam SCL_HALF_TICKS = SCL_HALF_US    * TICKS_PER_US;
    localparam VALID_TICKS    = VALID_PULSE_US * TICKS_PER_US;
    localparam FRAME_IDLE_TICKS = FRAME_IDLE_US * TICKS_PER_US;
    localparam STARTUP_TICKS = STARTUP_US * TICKS_PER_US;
    localparam SCL_IDLE_LEVEL = TP_ACTIVE_LOW ? 1'b1 : 1'b0;
    localparam SCL_ACTIVE_LEVEL = TP_ACTIVE_LOW ? 1'b0 : 1'b1;

    //------------------------------------------------------------------
    // 状态定义
    //------------------------------------------------------------------
    localparam [2:0] S_IDLE    = 3'd0;   // SCL 空闲，等待开始下一位
    localparam [2:0] S_ACTIVE  = 3'd1;   // SCL 有效，有效电平末采样 SDO
    localparam [2:0] S_VALID    = 3'd2;   // 一帧结束，输出 valid 脉冲
    localparam [2:0] S_REARM    = 3'd3;   // 模式切换后重新对齐串口
    localparam [2:0] S_OFF      = 3'd4;   // GPIO 直读时禁止串口时钟

    localparam [3:0] LAST_BIT = KEY_NUM - 1;   // 最后一位的序号

    reg [1:0]            sdo_sync;   // SDO 打两拍，消除跨时钟域亚稳态
    reg [2:0]            state;
    reg [31:0]           timer;
    reg [3:0]            bit_cnt;
    reg [KEY_NUM-1:0]    shift;      // 串转并移位寄存器
    reg mode_latched;
    reg started; // Mode changes cannot shorten the cold-start wait.
    wire read_enabled = ENABLE_CONTROL ? enable : 1'b1;
    wire selected_mode = DYNAMIC_MODE ? mode_16 : (KEY_NUM == 16);
    wire [3:0] last_bit = DYNAMIC_MODE ? (mode_latched ? 4'd15 : 4'd7) : LAST_BIT;
    wire sdo_now    = sdo_sync[1];
    wire timer_done = (timer == 32'd0);
    // 低有效时按下为 0，取反后 1 表示按下；active-high 时原样使用
    wire bit_pressed = TP_ACTIVE_LOW ? ~sdo_now : sdo_now;
    reg [KEY_NUM-1:0] sampled_keys;
    always @* begin
        sampled_keys = shift;
        sampled_keys[bit_cnt] = bit_pressed;
    end

    assign state_o   = state;
    assign bit_cnt_o = bit_cnt;

    // SDO 同步：空闲电平按有效极性给，避免刚上电时误判
    always @(posedge clk) begin
        if (!resetn)
            sdo_sync <= {2{TP_ACTIVE_LOW ? 1'b1 : 1'b0}};
        else
            sdo_sync <= {sdo_sync[0], sdo};
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state       <= S_IDLE;
            scl         <= SCL_IDLE_LEVEL;
            touch_valid <= 1'b0;
            touch_keys  <= {KEY_NUM{1'b0}};
            // The chip does not share FPGA reset. Keep SCL idle long
            // enough to reset its serial index even after a short S1 press.
            timer       <= STARTUP_TICKS - 1;
            bit_cnt     <= 4'd0;
            shift       <= {KEY_NUM{1'b0}};
            mode_latched <= selected_mode;
            started     <= 1'b0;
        end
        else if (!read_enabled) begin
            state       <= S_OFF;
            scl         <= SCL_IDLE_LEVEL;
            touch_valid <= 1'b0;
            touch_keys  <= {KEY_NUM{1'b0}};
            shift       <= {KEY_NUM{1'b0}};
            bit_cnt     <= 4'd0;
            mode_latched <= selected_mode;
            timer       <= FRAME_IDLE_TICKS - 1;
        end
        else if (selected_mode != mode_latched) begin
            mode_latched <= selected_mode;
            scl         <= SCL_IDLE_LEVEL;
            touch_valid <= 1'b0;
            touch_keys  <= {KEY_NUM{1'b0}};
            shift       <= {KEY_NUM{1'b0}};
            bit_cnt     <= 4'd0;
            if (started) begin
                timer <= FRAME_IDLE_TICKS - 1;
                state <= S_REARM;
            end else if (!timer_done)
                timer <= timer - 1'b1;
        end
        else begin
            case (state)

                // 从空闲电平切换到有效电平，开始读一位。
                S_IDLE: begin
                    if (timer_done) begin
                        scl   <= SCL_ACTIVE_LEVEL;
                        timer <= SCL_HALF_TICKS - 1;
                        state <= S_ACTIVE;
                        started <= 1'b1;
                        if (bit_cnt == 0)
                            shift <= {KEY_NUM{1'b0}};
                    end
                    else
                        timer <= timer - 1'b1;
                end

                // 有效电平末采样，再恢复到空闲电平。
                S_ACTIVE: begin
                    if (timer_done) begin
                        scl <= SCL_IDLE_LEVEL;
                        if (bit_cnt == last_bit) begin
                            // K1 first. Indexed writes also zero K9..K16 in 8-key mode.
                            touch_keys  <= sampled_keys;
                            touch_valid <= 1'b1;
                            bit_cnt     <= 4'd0;
                            timer       <= VALID_TICKS - 1;
                            state       <= S_VALID;
                        end
                        else begin
                            shift       <= sampled_keys;
                            bit_cnt     <= bit_cnt + 1'b1;
                            timer       <= SCL_HALF_TICKS - 1;
                            state       <= S_IDLE;
                        end
                    end
                    else
                        timer <= timer - 1'b1;
                end

                S_REARM: begin
                    if (timer_done) begin
                        scl <= SCL_ACTIVE_LEVEL;
                        timer <= SCL_HALF_TICKS - 1;
                        state <= S_ACTIVE;
                        started <= 1'b1;
                    end else
                        timer <= timer - 1'b1;
                end

                S_OFF: begin
                    // Enabling starts a fresh >2ms quiet period.
                    timer <= FRAME_IDLE_TICKS - 1;
                    state <= S_REARM;
                end

                // 保持 valid 脉冲，再进入 >2ms 无边沿的帧间静置。
                S_VALID: begin
                    if (timer_done) begin
                        touch_valid <= 1'b0;
                        scl         <= SCL_IDLE_LEVEL;
                        timer       <= FRAME_IDLE_TICKS - 1;
                        state       <= S_IDLE;
                    end
                    else
                        timer <= timer - 1'b1;
                end

                default: begin
                    state       <= S_IDLE;
                    scl         <= SCL_IDLE_LEVEL;
                    touch_valid <= 1'b0;
                    bit_cnt     <= 4'd0;
                    shift       <= {KEY_NUM{1'b0}};
                    timer       <= FRAME_IDLE_TICKS - 1;
                end
            endcase
        end
    end

endmodule
