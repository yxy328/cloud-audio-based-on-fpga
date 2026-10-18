`timescale 1ns/1ps
// GW5A-25 on-chip delta-sigma ADC, external PAD on bus0.
// USE_ADC_SRC in the CST selects the analog pin pair; no digital AO port.
module gowin_fsr_adc #(
    parameter CLK_FREQ = 50_000_000,
    parameter SAMPLE_HZ = 1000
) (
    input wire clk,
    input wire resetn,
    output wire [13:0] raw_value,
    output wire [9:0] adc_sample,
    output wire sample_valid,
    output wire busy,
    output wire timeout
);
    reg [3:0] adc_clock_count;
    reg adc_clk;
    always @(posedge clk) begin
        if (!resetn) begin
            adc_clock_count <= 0;
            adc_clk <= 0;
        end else if (adc_clock_count == 9) begin
            adc_clock_count <= 0;
            adc_clk <= ~adc_clk;
        end else adc_clock_count <= adc_clock_count+1'b1;
    end
    wire adc_ready, adc_request;
    wire [13:0] adc_value;
    // User clock=2.5MHz, voltage mode, glo_left PAD; internal supply buffers OFF.
    ADC #(
        .CLK_SEL(1'b1), .DIV_CTL(2'd0), .BUF_EN(12'd0),
        .BUF_BK0_VREF_EN(1'b0), .BUF_BK1_VREF_EN(1'b0),
        .BUF_BK2_VREF_EN(1'b0), .BUF_BK3_VREF_EN(1'b0),
        .BUF_BK4_VREF_EN(1'b0), .BUF_BK5_VREF_EN(1'b0),
        .BUF_BK6_VREF_EN(1'b0), .BUF_BK7_VREF_EN(1'b0),
        .CSR_ADC_MODE(1'b1), .CSR_VSEN_CTRL(3'd0),
        .CSR_SAMPLE_CNT_SEL(3'd4), .CSR_RATE_CHANGE_CTRL(3'd4),
        .CSR_FSCAL(10'd653), .CSR_OFFSET(12'd0)
    ) adc_inst (
        .CLK(adc_clk), .VSENCTL(3'd0), .ADCMODE(1'b1), .DRSTN(resetn),
        .ADCREQI(adc_request), .ADCRDY(adc_ready), .ADCVALUE(adc_value),
        .ADCEN(resetn), .MDRP_CLK(adc_clk), .MDRP_WDATA(8'd0),
        .MDRP_A_INC(1'b0), .MDRP_OPCODE(2'd0), .MDRP_RDATA()
    );
    fsr_adc_capture #(.CLK_FREQ(CLK_FREQ), .SAMPLE_HZ(SAMPLE_HZ)) u_capture (
        .clk(clk), .resetn(resetn), .adc_ready(adc_ready), .adc_value(adc_value),
        .adc_request(adc_request), .raw_value(raw_value), .adc_sample(adc_sample),
        .sample_valid(sample_valid), .busy(busy), .timeout(timeout)
    );
endmodule

// Ready is synchronized; its result bus remains stable until the next request.
// First observe ready LOW, then HIGH, so a previous result cannot be reused.
module fsr_adc_capture #(
    parameter CLK_FREQ = 50_000_000,
    parameter SAMPLE_HZ = 1000,
    parameter REQUEST_CYCLES = 64,
    parameter TIMEOUT_CYCLES = 100_000
) (
    input wire clk,
    input wire resetn,
    input wire adc_ready,
    input wire [13:0] adc_value,
    output reg adc_request,
    output reg [13:0] raw_value,
    output wire [9:0] adc_sample,
    output reg sample_valid,
    output wire busy,
    output reg timeout
);
    localparam PERIOD_CYCLES = CLK_FREQ/SAMPLE_HZ;
    localparam PERIOD_BITS=PERIOD_CYCLES<2 ? 1 : $clog2(PERIOD_CYCLES);
    localparam REQUEST_BITS=REQUEST_CYCLES<1 ? 1 : $clog2(REQUEST_CYCLES+1);
    localparam TIMEOUT_BITS=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
    localparam IDLE=2'd0, WAIT_LOW=2'd1, WAIT_HIGH=2'd2;
    reg [1:0] state;
    reg ready_meta, ready_sync;
    reg [PERIOD_BITS-1:0] period_count;
    reg [REQUEST_BITS-1:0] request_left;
    reg [TIMEOUT_BITS-1:0] elapsed;
    assign busy = state != IDLE;
    // ADCVALUE/2048 is voltage in volts. Convert 0..1V to 0..1023.
    // Saturating this digital conversion does not protect the analog pin.
    assign adc_sample = raw_value >= 14'd2046 ? 10'd1023 : raw_value[10:1];
    always @(posedge clk) begin
        if (!resetn) begin ready_meta<=0;ready_sync<=0;end
        else begin ready_meta<=adc_ready;ready_sync<=ready_meta;end
    end
    always @(posedge clk) begin
        if (!resetn) begin
            state<=IDLE;period_count<=0;request_left<=0;elapsed<=0;
            adc_request<=0;raw_value<=0;sample_valid<=0;timeout<=0;
        end else begin
            sample_valid<=0;
            if(period_count==PERIOD_CYCLES-1) period_count<=0;
            else period_count<=period_count+1'b1;
            if(request_left!=0) begin
                request_left<=request_left-1'b1;
                if(request_left==1) adc_request<=0;
            end
            if(state==IDLE) begin
                if(period_count==PERIOD_CYCLES-1) begin
                    adc_request<=1;request_left<=REQUEST_CYCLES;
                    elapsed<=0;state<=WAIT_LOW;
                end
            end else if(elapsed==TIMEOUT_CYCLES-1) begin
                state<=IDLE;adc_request<=0;request_left<=0;timeout<=1;
            end else begin
                elapsed<=elapsed+1'b1;
                if(state==WAIT_LOW && !ready_sync) state<=WAIT_HIGH;
                else if(state==WAIT_HIGH && ready_sync) begin
                    raw_value<=adc_value;sample_valid<=1;
                    timeout<=0;state<=IDLE;
                end
            end
        end
    end
endmodule
