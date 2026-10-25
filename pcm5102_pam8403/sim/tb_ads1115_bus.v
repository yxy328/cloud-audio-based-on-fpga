`timescale 1ns/1ps
// ADS1115 slider reader on its own I2C bus.
// Checks: configuration write, 16->10-bit mapping, continuous updates,
// timeout when the converter stops answering, and recovery afterwards.
module tb_ads1115_bus;
    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0;

    tri1 scl, sda;

    wire [15:0] ads_raw;
    wire [9:0] ads_sample;
    wire ads_valid, ads_timeout;

    reg present = 1;
    reg [15:0] model_code = 16'h4000;

    ads1115_ctrl #(
        .STARTUP_MS(1), .POLL_MS(1), .TIMEOUT_MS(5)
    ) u_ads (
        .clk(clk), .resetn(resetn), .scl(scl), .sda(sda),
        .raw(ads_raw), .sample(ads_sample),
        .sample_valid(ads_valid), .timeout(ads_timeout)
    );

    ads1115_model u_model (
        .clk(clk), .scl(scl), .sda(sda), .present(present), .code(model_code)
    );

    integer valid_count = 0;
    always @(posedge clk) begin
        if (resetn && ads_valid) valid_count = valid_count + 1;
        if (resetn && ads_valid && ((^ads_sample) === 1'bx))
            $fatal(1, "Unknown slider sample reached the control path");
    end

    task wait_valid;
        input integer limit;
        integer n;
        begin
            n = 0;
            while (valid_count == 0 && n < limit) begin
                @(posedge clk);
                n = n + 1;
            end
            if (valid_count == 0) $fatal(1, "No ADS1115 sample within limit");
        end
    endtask

    task expect_sample;
        input [9:0] want;
        input integer limit;
        integer n;
        begin
            n = 0;
            while ((ads_sample !== want) && n < limit) begin
                @(posedge clk);
                n = n + 1;
            end
            if (ads_sample !== want)
                $fatal(1, "Slider sample %0d, wanted %0d", ads_sample, want);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        resetn = 1;

        // First conversion, mapping and configuration bytes.
        wait_valid(600000);
        if (ads_sample !== model_code[14:5])
            $fatal(1, "Slider mapping %0d != %0d", ads_sample, model_code[14:5]);
        if (ads_timeout !== 1'b0) $fatal(1, "Timeout still set after a good sample");
        if (u_model.cfg !== {8'hD2, 8'h83})
            $fatal(1, "Configuration register %04x", u_model.cfg);

        // A moving slider is followed by later conversions.
        model_code = 16'h7FFF;
        expect_sample(10'h3FF, 400000);
        model_code = 16'h0000;
        expect_sample(10'd0, 400000);

        // Converter disappears: keep the last value but raise the fallback.
        present = 0;
        @(negedge clk);
        wait (ads_timeout === 1'b1);

        // Converter returns with a new position and clears the fallback.
        present = 1;
        model_code = 16'h2000;
        expect_sample(10'd256, 800000);
        if (ads_timeout !== 1'b0) $fatal(1, "Fallback did not clear after recovery");

        $display("PASS [ADS1115 bus]: config D283 written, 16->10-bit mapping, continuous updates, timeout hold and recovery; %0d conversions", valid_count);
        $finish;
    end

    initial begin
        #40000000;
        $fatal(1, "ADS1115 bus test timeout");
    end
endmodule
