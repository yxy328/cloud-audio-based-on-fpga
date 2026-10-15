`timescale 1ns/1ps
// ============================================================================
//  i2c_master.v —— 通用 I2C 主机控制器 (标准模式 100kHz)
//  用于驱动 APDS-9960 (从机地址 0x39)
//  - 支持: 写单字节、读单/多字节 (含"写寄存器地址 + 重复起始 + 读"组合格式)
//  - SDA/SCL 均按开漏方式驱动 (oe=1 拉低, oe=0 释放靠上拉)
// ============================================================================

module i2c_master #(
    parameter CLK_FREQ = 50_000_000,   // 输入时钟
    parameter I2C_FREQ = 100_000       // I2C 速率
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 命令接口 (一次事务) ----
    input  wire        cmd_start,      // 启动脉冲 (1 clk)
    input  wire [6:0]  cmd_addr,       // 从机地址 7bit
    input  wire [7:0]  cmd_reg,        // 寄存器地址
    input  wire        cmd_rw,         // 0=写 1=读
    input  wire [7:0]  cmd_wdata,      // 写数据 (cmd_rw=0 时有效)
    input  wire [7:0]  cmd_rdlen,      // 读字节数 (cmd_rw=1 时有效, 1~255)
    output reg         busy,
    output reg         done,           // 事务完成脉冲
    output reg         nack,           // 收到 NACK (done 同时有效)
    output reg  [7:0]  rdata,          // 读回数据
    output reg         rvalid,         // 读数据有效脉冲 (每字节)

    // ---- I2C 总线 (开漏) ----
    inout  wire        scl,
    inout  wire        sda
);

    // ---- SCL 相位分频: 每个 SCL 周期 4 段, 每段 SEG 个时钟 ----
    localparam SEG   = CLK_FREQ / (4 * I2C_FREQ);   // 125
    localparam SEG_W = $clog2(SEG + 1);

    reg [SEG_W-1:0] seg_cnt;
    wire seg_tick = (seg_cnt == SEG - 1);

    reg seg_rst;   // 段/段内计数器复位 (IDLE 时有效)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           seg_cnt <= 0;
        else if (seg_rst)     seg_cnt <= 0;
        else if (seg_tick)    seg_cnt <= 0;
        else                  seg_cnt <= seg_cnt + 1'b1;
    end

    // ---- 开漏驱动: oe=1 拉低, oe=0 释放(高) ----
    reg scl_oe;
    reg sda_oe;
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;
    wire sda_in = sda;

    // ---- 状态机 ----
    localparam [3:0]
        S_IDLE   = 4'd0,
        S_START  = 4'd1,
        S_BYTE   = 4'd2,   // 发送 1 字节
        S_ACK    = 4'd3,   // 接收 ACK
        S_RBYTE  = 4'd4,   // 接收 1 字节
        S_SACK   = 4'd5,   // 发送 ACK/NACK
        S_RSTART = 4'd6,
        S_STOP   = 4'd7;

    reg  [3:0] state;

    reg  [1:0] seg;          // 段号 0..3
    reg  [3:0] bit_idx;      // 位计数器 0..7
    reg  [7:0] shift_reg;    // 发送移位寄存器
    reg  [7:0] byte_remain;  // 读模式剩余字节数
    reg  [1:0] tx_kind;      // 0=地址 1=寄存器 2=写数据 3=读地址后

    wire last_byte = (byte_remain == 8'd1);

    // ---- 段推进 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg <= 2'd0;
        end else if (seg_rst) begin
            seg <= 2'd0;
        end else if (seg_tick) begin
            seg <= (seg == 2'd3) ? 2'd0 : seg + 1'b1;
        end
    end

    // ---- 主状态机 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            scl_oe      <= 1'b0;
            sda_oe      <= 1'b0;
            bit_idx     <= 4'd0;
            shift_reg   <= 8'd0;
            byte_remain <= 8'd0;
            tx_kind     <= 2'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
            nack        <= 1'b0;
            rdata       <= 8'd0;
            rvalid      <= 1'b0;
            seg_rst     <= 1'b1;
        end else begin
            // 默认脉冲清零
            done    <= 1'b0;
            rvalid  <= 1'b0;
            seg_rst <= 1'b0;

            case (state)

            S_IDLE: begin
                seg_rst <= 1'b1;   // IDLE 期间段计数器保持 0
                if (cmd_start) begin
                    busy        <= 1'b1;
                    nack        <= 1'b0;
                    tx_kind     <= 2'd0;                  // 先发地址字节
                    byte_remain <= cmd_rw ? cmd_rdlen : 8'd0;
                    state       <= S_START;
                end
            end

            // ---- 起始条件: SCL=高 时 SDA 下降 ----
            S_START: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b0; sda_oe <= 1'b0; end  // SCL高 SDA高
                    2'd1: begin scl_oe <= 1'b0; sda_oe <= 1'b1; end  // SDA 下降 (START)
                    2'd2: begin scl_oe <= 1'b1; sda_oe <= 1'b1; end  // SCL 拉低
                    2'd3: begin
                        shift_reg <= {cmd_addr, 1'b0};   // 第一步始终发"写地址"
                        bit_idx   <= 4'd7;
                        state     <= S_BYTE;
                    end
                    endcase
                end
            end

            // ---- 发送 1 字节 (MSB 先) ----
            S_BYTE: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b1; sda_oe <= ~shift_reg[7]; end  // SCL低 数据建立
                    2'd1: begin scl_oe <= 1'b0; sda_oe <= ~shift_reg[7]; end  // SCL高
                    2'd2: begin /* 保持 */ end
                    2'd3: begin
                        scl_oe <= 1'b1;                     // SCL 下降
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_idx == 4'd0) begin
                            state  <= S_ACK;
                        end else begin
                            bit_idx <= bit_idx - 1'b1;
                        end
                    end
                    endcase
                end
            end

            // ---- 接收 ACK ----
            S_ACK: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b0; end  // SCL低 释放SDA
                    2'd1: begin scl_oe <= 1'b0; end                   // SCL高
                    2'd2: begin /* 保持 */ end
                    2'd3: begin
                        scl_oe <= 1'b1;                  // SCL 下降
                        if (sda_in == 1'b1) begin
                            // NACK: 从机无应答 -> 结束
                            nack  <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            case (tx_kind)
                            2'd0: begin                       // 地址已发 -> 发寄存器
                                tx_kind   <= 2'd1;
                                shift_reg <= cmd_reg;
                                bit_idx   <= 4'd7;
                                state     <= S_BYTE;
                            end
                            2'd1: begin
                                if (cmd_rw == 1'b0) begin     // 写模式 -> 发写数据
                                    tx_kind   <= 2'd2;
                                    shift_reg <= cmd_wdata;
                                    bit_idx   <= 4'd7;
                                    state     <= S_BYTE;
                                end else begin                 // 读模式 -> 重复起始
                                    state <= S_RSTART;
                                end
                            end
                            2'd2: begin                       // 写数据已发 -> 停止
                                state <= S_STOP;
                            end
                            2'd3: begin                       // 读地址已发 -> 收数据
                                bit_idx <= 4'd7;
                                state   <= S_RBYTE;
                            end
                            endcase
                        end
                    end
                    endcase
                end
            end

            // ---- 重复起始 ----
            S_RSTART: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b0; end  // SCL低 SDA高
                    2'd1: begin scl_oe <= 1'b0; sda_oe <= 1'b0; end  // SCL高 SDA高
                    2'd2: begin scl_oe <= 1'b0; sda_oe <= 1'b1; end  // SDA 下降 (repeated START)
                    2'd3: begin
                        scl_oe <= 1'b1;
                        shift_reg <= {cmd_addr, 1'b1};   // 读地址
                        bit_idx   <= 4'd7;
                        tx_kind   <= 2'd3;
                        state     <= S_BYTE;
                    end
                    endcase
                end
            end

            // ---- 接收 1 字节 ----
            S_RBYTE: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b0; end  // SCL低 释放SDA
                    2'd1: begin scl_oe <= 1'b0; end                   // SCL高
                    2'd2: begin /* 保持 */ end
                    2'd3: begin
                        scl_oe <= 1'b1;                  // SCL 下降
                        rdata  <= {rdata[6:0], sda_in};  // 采样数据位 (SCL高时)
                        if (bit_idx == 4'd0) begin
                            rvalid <= 1'b1;              // 一字节读完
                            state  <= S_SACK;
                        end else begin
                            bit_idx <= bit_idx - 1'b1;
                        end
                    end
                    endcase
                end
            end

            // ---- 发送 ACK / NACK ----
            S_SACK: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b1; sda_oe <= ~last_byte; end  // ACK=拉低 NACK=释放
                    2'd1: begin scl_oe <= 1'b0; end
                    2'd2: begin /* 保持 */ end
                    2'd3: begin
                        scl_oe <= 1'b1;
                        if (last_byte) begin
                            state <= S_STOP;
                        end else begin
                            byte_remain <= byte_remain - 1'b1;
                            bit_idx     <= 4'd7;
                            state       <= S_RBYTE;
                        end
                    end
                    endcase
                end
            end

            // ---- 停止条件: SCL=高 时 SDA 上升 ----
            S_STOP: begin
                if (seg_tick) begin
                    case (seg)
                    2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b1; end  // SCL低 SDA低
                    2'd1: begin scl_oe <= 1'b0; sda_oe <= 1'b1; end  // SCL高 SDA低
                    2'd2: begin scl_oe <= 1'b0; sda_oe <= 1'b0; end  // SDA 上升 (STOP)
                    2'd3: begin
                        scl_oe <= 1'b0;
                        sda_oe <= 1'b0;
                        busy   <= 1'b0;
                        done   <= 1'b1;
                        state  <= S_IDLE;
                    end
                    endcase
                end
            end

            default: state <= S_IDLE;

            endcase
        end
    end

endmodule

