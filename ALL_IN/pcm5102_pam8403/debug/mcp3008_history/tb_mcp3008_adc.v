`timescale 1ns/1ps
module tb_mcp3008_adc;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;
    reg [9:0] code=0;
    tri1 miso;
    wire cs_n,sclk,mosi,valid,busy;
    wire [9:0] sample;
    mcp3008_adc #(.CHANNEL(3'd5)) dut(
        .clk(clk),.resetn(resetn),.miso(miso),.cs_n(cs_n),.sclk(sclk),
        .mosi(mosi),.adc_sample(sample),.sample_valid(valid),.busy(busy));
    mcp3008_model #(.EXPECT_CHANNEL(3'd5)) adc(
        .resetn(resetn),
        .cs_n(cs_n),.sclk(sclk),.mosi(mosi),.analog_code(code),.miso(miso));
    time previous_edge=0,previous_cs=0,previous_valid=0;
    integer received=0;
    reg previous_valid_level=0;
    always @(sclk) begin
        if(busy) begin
            if(previous_edge!=0 && $time-previous_edge!=1000)
                $fatal(1,"ADC SCLK half-period mismatch");
            previous_edge=$time;
        end else previous_edge=0;
    end
    always @(negedge cs_n) begin
        if(previous_cs!=0 && $time-previous_cs!=1000000)
            $fatal(1,"ADC sample interval mismatch");
        previous_cs=$time;
    end
    always @(negedge clk) begin
        if(resetn) begin
            if(valid && previous_valid_level) $fatal(1,"ADC valid is not a single clk pulse");
            previous_valid_level=valid;
            if(valid) begin
                if(sample!==code || busy || cs_n!==1 || sclk!==0)
                    $fatal(1,"ADC decoded value/end-of-transaction mismatch: %0d expected %0d",sample,code);
                if(previous_valid!=0 && $time-previous_valid!=1000000)
                    $fatal(1,"ADC valid interval mismatch");
                previous_valid=$time;received=received+1;
            end
        end
    end
    task read_code;
        input [9:0] value;
        integer old_count;
        begin
            @(negedge clk);code=value;old_count=received;
            wait(received>old_count);@(negedge clk);
        end
    endtask
    initial begin
        #100;
        if(cs_n!==1 || sclk!==0 || valid!==0) $fatal(1,"ADC reset idle failed");
        @(negedge clk);resetn=1;
        read_code(0);read_code(1);read_code(512);read_code(682);read_code(1023);
        // Reset in the middle of a conversion: no partial result may escape.
        wait(!cs_n);#10000;
        @(negedge clk);resetn=0;#100;
        if(cs_n!==1 || sclk!==0 || valid!==0 || busy!==0)
            $fatal(1,"ADC reset did not abort conversion");
        $display("PASS [MCP3008]: five 10-bit boundary/pattern codes, CH5 command, 500kHz mode 0, 1kHz cadence, valid pulse, reset abort");
        $finish;
    end
    initial begin #8000000;$fatal(1,"ADC test timeout");end
endmodule
