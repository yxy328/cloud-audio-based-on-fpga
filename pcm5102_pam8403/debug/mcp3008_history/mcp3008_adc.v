`timescale 1ns/1ps
// MCP3008 single-ended SPI mode 0, standard 24-clock transaction.
// At 50MHz: SCLK=500kHz, one CH0 conversion every 1ms.
// All logic uses clk; SCLK is a registered output, never an internal clock.
module mcp3008_adc #(
    parameter CLK_FREQ = 50_000_000,
    parameter SPI_CLK_HZ = 500_000,
    parameter SAMPLE_HZ = 1000,
    parameter [2:0] CHANNEL = 3'd0
) (
    input wire clk,
    input wire resetn,
    input wire miso,
    output reg cs_n,
    output reg sclk,
    output reg mosi,
    output reg [9:0] adc_sample,
    output reg sample_valid,
    output reg busy
);
    localparam HALF_CYCLES = CLK_FREQ / (2 * SPI_CLK_HZ);
    localparam SAMPLE_CYCLES = CLK_FREQ / SAMPLE_HZ;
    // Leading zeroes, start=1, single-ended=1, channel, don't-care zeroes.
    localparam [23:0] COMMAND = {7'd0, 1'b1, 1'b1, CHANNEL, 12'd0};
    reg [31:0] sample_count;
    reg [31:0] half_count;
    reg [4:0] bit_index;
    reg [9:0] receive_shift;
    reg miso_meta, miso_sync;

    always @(posedge clk) begin
        if (!resetn) begin
            miso_meta <= 1'b1;
            miso_sync <= 1'b1;
        end else begin
            miso_meta <= miso;
            miso_sync <= miso_meta;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            cs_n <= 1'b1;
            sclk <= 1'b0;
            mosi <= 1'b0;
            busy <= 1'b0;
            sample_valid <= 1'b0;
            adc_sample <= 10'd1023;
            sample_count <= 0;
            half_count <= 0;
            bit_index <= 5'd23;
            receive_shift <= 0;
        end else begin
            sample_valid <= 1'b0;
            if (sample_count == SAMPLE_CYCLES-1) begin
                sample_count <= 0;
                if (!busy) begin
                    cs_n <= 1'b0;
                    sclk <= 1'b0;
                    mosi <= COMMAND[23];
                    busy <= 1'b1;
                    bit_index <= 5'd23;
                    half_count <= 0;
                    receive_shift <= 0;
                end
            end else begin
                sample_count <= sample_count + 1'b1;
            end

            if (busy) begin
                if (half_count == HALF_CYCLES-1) begin
                    half_count <= 0;
                    if (!sclk) begin
                        sclk <= 1'b1;
                        // Null bit is clock 14; B9..B0 are clocks 15..24.
                        if (bit_index < 10)
                            receive_shift <= {receive_shift[8:0], miso_sync};
                    end else begin
                        sclk <= 1'b0;
                        if (bit_index == 0) begin
                            cs_n <= 1'b1;
                            mosi <= 1'b0;
                            busy <= 1'b0;
                            adc_sample <= receive_shift;
                            sample_valid <= 1'b1;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            mosi <= COMMAND[bit_index-1'b1];
                        end
                    end
                end else begin
                    half_count <= half_count + 1'b1;
                end
            end
        end
    end
endmodule
