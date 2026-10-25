`timescale 1ns/1ps
// NOT USED BY THE CURRENT BUILD.
// The slider converter now has its own SCL/SDA pins (K10/L10) with a local
// master inside ads1115_ctrl, so the APDS-9960 bus needs no arbitration.
// This module is kept only for a shared-bus variant; it is excluded from
// PCM5102_UNIFIED.gprj and from tools/run_sim.ps1.
//
// Two clients share one I2C bus.
//
// The physical pins are driven by exactly one tri-state master inside this
// module; the clients only supply transaction descriptors. The sensor client
// (A) keeps priority because its controller has no bus timeout, while the
// ADS1115 client (B) is polled slowly and can wait for one sensor transaction.
// Both clients see BUSY from the moment their request is latched until their
// own transaction completes, so neither can issue a second START early.
module i2c_arbiter #(
    parameter CLK_FREQ = 50_000_000,
    parameter I2C_FREQ = 100_000
)(
    input  wire       clk,
    input  wire       rst_n,

    // Client A: APDS-9960 gesture controller (one-byte register writes).
    input  wire       a_start,
    input  wire [6:0] a_addr,
    input  wire [7:0] a_reg,
    input  wire       a_rw,
    input  wire [7:0] a_wdata,
    input  wire [7:0] a_rdlen,
    output wire       a_busy,
    output wire       a_done,
    output wire       a_nack,
    output wire [7:0] a_rdata,
    output wire       a_rvalid,

    // Client B: ADS1115 reader (two-byte register writes supported).
    input  wire       b_start,
    input  wire [6:0] b_addr,
    input  wire [7:0] b_reg,
    input  wire       b_rw,
    input  wire [7:0] b_wdata,
    input  wire [7:0] b_wdata1,
    input  wire       b_wlen,
    input  wire [7:0] b_rdlen,
    output wire       b_busy,
    output wire       b_done,
    output wire       b_nack,
    output wire [7:0] b_rdata,
    output wire       b_rvalid,

    inout  wire       scl,
    inout  wire       sda
);

    wire       m_busy, m_done, m_nack, m_rvalid;
    wire [7:0] m_rdata;
    reg        m_start;
    reg [6:0]  m_addr;
    reg [7:0]  m_reg, m_wdata, m_wdata1, m_rdlen;
    reg        m_rw, m_wlen;

    i2c_master #(.CLK_FREQ(CLK_FREQ), .I2C_FREQ(I2C_FREQ)) u_master (
        .clk(clk), .rst_n(rst_n),
        .cmd_start(m_start), .cmd_addr(m_addr), .cmd_reg(m_reg), .cmd_rw(m_rw),
        .cmd_wdata(m_wdata), .cmd_wdata1(m_wdata1), .cmd_wlen(m_wlen),
        .cmd_rdlen(m_rdlen),
        .busy(m_busy), .done(m_done), .nack(m_nack),
        .rdata(m_rdata), .rvalid(m_rvalid),
        .scl(scl), .sda(sda)
    );

    reg pend_a, pend_b, active_a, active_b;
    // A has priority: B starts only when A is neither waiting nor running.
    wire grant_a = pend_a && !m_busy;
    wire grant_b = pend_b && !m_busy && !pend_a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_a <= 1'b0; pend_b <= 1'b0;
            active_a <= 1'b0; active_b <= 1'b0;
            m_start <= 1'b0;
            m_addr <= 7'd0; m_reg <= 8'd0; m_rw <= 1'b0;
            m_wdata <= 8'd0; m_wdata1 <= 8'd0; m_wlen <= 1'b0; m_rdlen <= 8'd0;
        end else begin
            m_start <= 1'b0;
            // Latch a client request. A client may only start while it is idle.
            if (a_start && !a_busy) pend_a <= 1'b1;
            if (b_start && !b_busy) pend_b <= 1'b1;
            if (grant_a) begin
                m_addr    <= a_addr;
                m_reg     <= a_reg;
                m_rw      <= a_rw;
                m_wdata   <= a_wdata;
                m_wdata1  <= 8'd0;
                m_wlen    <= 1'b0;
                m_rdlen   <= a_rdlen;
                m_start   <= 1'b1;
                pend_a    <= 1'b0;
                active_a  <= 1'b1;
                active_b  <= 1'b0;
            end else if (grant_b) begin
                m_addr    <= b_addr;
                m_reg     <= b_reg;
                m_rw      <= b_rw;
                m_wdata   <= b_wdata;
                m_wdata1  <= b_wdata1;
                m_wlen    <= b_wlen;
                m_rdlen   <= b_rdlen;
                m_start   <= 1'b1;
                pend_b    <= 1'b0;
                active_b  <= 1'b1;
                active_a  <= 1'b0;
            end
            // A transaction may finish in the same cycle the other client is
            // granted the bus; only clear ownership when nothing was granted.
            if (m_done && !grant_a && !grant_b) begin
                active_a <= 1'b0;
                active_b <= 1'b0;
            end
        end
    end

    assign a_busy   = pend_a || active_a;
    assign b_busy   = pend_b || active_b;
    assign a_done   = m_done && !active_b;
    assign b_done   = m_done &&  active_b;
    assign a_rvalid = m_rvalid && !active_b;
    assign b_rvalid = m_rvalid &&  active_b;
    assign a_nack   = m_nack;
    assign b_nack   = m_nack;
    assign a_rdata  = m_rdata;
    assign b_rdata  = m_rdata;

endmodule
