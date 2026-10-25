`timescale 1ns/1ps
// ADS1115 slider reader on its own I2C bus (ADDR pin = GND, address 0x48).
//
// The slider owns dedicated SCL/SDA pins so the APDS-9960 gesture bus stays
// untouched: no arbitration, no shared transaction timing.
//
// Configuration: AIN1 single-ended, PGA +-4.096V, continuous conversion,
// 128 samples/s, comparator disabled. The slider wiper (0..3.3V) connects to
// AIN1 directly; no resistor divider is needed because the input is high-Z and
// the +-4.096V range covers the 3.3V rail.
//
// Timing is derived from one millisecond divider plus small millisecond
// counters, so the block stays cheap on a device that is already at 98% CLS.
// After each read the 16-bit conversion is mapped to the same 10-bit code range
// the previous on-chip-ADC slider used (raw[14:5]), so the existing calibration
// command and dynamics keep working.
//
// TIMEOUT stays asserted until the first known-good sample and returns
// whenever the converter stops answering. The expression path then falls back
// to neutral, exactly like the previous ADC timeout behaviour.
module ads1115_ctrl #(
    parameter CLK_FREQ = 50_000_000,
    parameter [6:0] ADDR = 7'h48,
    parameter [7:0] CONFIG_MSB = 8'hD2, // OS=1 MUX=AIN1 PGA=+-4.096V continuous
    parameter [7:0] CONFIG_LSB = 8'h83, // 128SPS, comparator disabled
    parameter integer STARTUP_MS = 25,
    parameter integer POLL_MS = 10,
    // First-result wait after the configuration write; one poll period covers
    // a 128SPS conversion.
    parameter integer SETTLE_MS = POLL_MS,
    parameter integer TIMEOUT_MS = 100
)(
    input  wire       clk,
    input  wire       resetn,

    // Dedicated open-drain I2C bus for the converter.
    inout  wire       scl,
    inout  wire       sda,

    // 16-bit conversion and 10-bit normalized position
    output reg  [15:0] raw,
    output reg  [9:0]  sample,
    output reg         sample_valid,
    output wire        timeout
);

    localparam integer MS_CYCLES = (CLK_FREQ + 999) / 1000;
    localparam integer MS_W      = (MS_CYCLES < 2) ? 1 : $clog2(MS_CYCLES);
    localparam integer POLL_W    = (POLL_MS    < 2) ? 1 : $clog2(POLL_MS + 1);
    localparam integer SETTLE_W  = (SETTLE_MS  < 2) ? 1 : $clog2(SETTLE_MS + 1);
    localparam integer AGE_W     = (TIMEOUT_MS < 2) ? 1 : $clog2(TIMEOUT_MS + 1);
    localparam integer START_W   = (STARTUP_MS < 2) ? 1 : $clog2(STARTUP_MS + 1);

    localparam [1:0] S_POWER = 2'd0,
                     S_IDLE  = 2'd1,
                     S_WAIT  = 2'd2;

    reg [1:0] state;
    reg [MS_W-1:0] ms_div;
    reg [START_W-1:0] startup_ms;
    reg [AGE_W-1:0]   stale_ms;
    reg [POLL_W-1:0]  poll_ms;
    reg [SETTLE_W-1:0] settle_ms;
    reg [7:0] hi_byte;
    reg       have_hi;
    reg       need_cfg;

    // Transaction control to the local master.
    reg        start;
    reg  [7:0] reg_addr;
    reg        rw;
    reg  [7:0] wdata, wdata1;
    reg        wlen;
    reg  [7:0] rdlen;
    wire       busy, done, nack, rvalid;
    wire [7:0] rdata;

    i2c_master #(.CLK_FREQ(CLK_FREQ), .I2C_FREQ(100_000)) u_i2c (
        .clk(clk), .rst_n(resetn),
        .cmd_start(start), .cmd_addr(ADDR), .cmd_reg(reg_addr),
        .cmd_rw(rw), .cmd_wdata(wdata), .cmd_wdata1(wdata1), .cmd_wlen(wlen),
        .cmd_rdlen(rdlen),
        .busy(busy), .done(done), .nack(nack),
        .rdata(rdata), .rvalid(rvalid),
        .scl(scl), .sda(sda)
    );

    assign timeout = (stale_ms >= TIMEOUT_MS);

    wire ms_tick = (ms_div == MS_CYCLES - 1) && (MS_CYCLES > 1);
    // The last read byte stays on RDATA until the next transaction, so the
    // second byte is sampled at DONE. Any unknown bit means a floating or
    // unresponsive bus, which must never reach the audio path.
    wire [15:0] raw_next  = {hi_byte, rdata};
    wire        raw_known = ((^raw_next) !== 1'bx);
    wire        idle_now  = (settle_ms == 0) && (poll_ms == 0) && !busy;

    always @(posedge clk) begin
        if (!resetn) begin
            state        <= S_POWER;
            start        <= 1'b0;
            ms_div       <= {MS_W{1'b0}};
            startup_ms   <= {START_W{1'b0}};
            // Start stale so the slider is neutral until the first good read.
            stale_ms     <= TIMEOUT_MS[AGE_W-1:0];
            poll_ms      <= POLL_MS[POLL_W-1:0];
            settle_ms    <= {SETTLE_W{1'b0}};
            reg_addr     <= 8'h01;
            rw           <= 1'b0;
            wdata        <= CONFIG_MSB;
            wdata1       <= CONFIG_LSB;
            wlen         <= 1'b1;
            rdlen        <= 8'd0;
            hi_byte      <= 8'd0;
            have_hi      <= 1'b0;
            need_cfg     <= 1'b1;
            raw          <= 16'd0;
            sample       <= 10'd0;
            sample_valid <= 1'b0;
        end else begin
            start        <= 1'b0;
            sample_valid <= 1'b0;

            ms_div <= ms_tick ? {MS_W{1'b0}} : (ms_div + 1'b1);
            if (ms_tick) begin
                if (startup_ms < STARTUP_MS) startup_ms <= startup_ms + 1'b1;
                if (stale_ms   < TIMEOUT_MS) stale_ms   <= stale_ms   + 1'b1;
                if (settle_ms != 0) settle_ms <= settle_ms - 1'b1;
                else if (poll_ms != 0) poll_ms <= poll_ms - 1'b1;
            end

            case (state)
            S_POWER: if (startup_ms >= STARTUP_MS) state <= S_IDLE;

            S_IDLE: if (idle_now) begin
                start <= 1'b1;
                poll_ms <= POLL_MS[POLL_W-1:0];
                if (need_cfg) begin
                    reg_addr <= 8'h01;
                    rw       <= 1'b0;
                    wdata    <= CONFIG_MSB;
                    wdata1   <= CONFIG_LSB;
                    wlen     <= 1'b1;
                    rdlen    <= 8'd0;
                end else begin
                    reg_addr <= 8'h00;
                    rw       <= 1'b1;
                    wlen     <= 1'b0;
                    rdlen    <= 8'd2;
                    have_hi  <= 1'b0;
                end
                state <= S_WAIT;
            end

            S_WAIT: begin
                if (rvalid && rw && !have_hi) begin
                    hi_byte <= rdata;
                    have_hi <= 1'b1;
                end
                if (done) begin
                    if (rw) begin
                        if (!nack && have_hi && raw_known) begin
                            raw          <= raw_next;
                            sample       <= raw_next[14:5];
                            sample_valid <= 1'b1;
                            stale_ms     <= {AGE_W{1'b0}};
                        end
                        // Missing device, NACK or a floating bus: keep the last
                        // good value and let the timeout fallback take over.
                    end else begin
                        // Retry the configuration only when the device NACKed.
                        need_cfg <= nack;
                        if (!nack) settle_ms <= SETTLE_MS[SETTLE_W-1:0];
                    end
                    state <= S_IDLE;
                end
            end

            default: state <= S_POWER;
            endcase
        end
    end

endmodule
