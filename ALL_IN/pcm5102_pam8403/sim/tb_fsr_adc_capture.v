`timescale 1ns/1ps
module tb_fsr_adc_capture;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ready=1;
    reg [13:0] value=36;
    wire request,valid,busy,timeout;
    wire [13:0] raw;
    wire [9:0] code;
    fsr_adc_capture #(.CLK_FREQ(100000),.SAMPLE_HZ(1000),
        .REQUEST_CYCLES(8),.TIMEOUT_CYCLES(200)) dut(
        .clk(clk),.resetn(resetn),.adc_ready(ready),.adc_value(value),
        .adc_request(request),.raw_value(raw),.adc_sample(code),
        .sample_valid(valid),.busy(busy),.timeout(timeout));
    integer samples=0;
    always @(negedge clk) if(valid) samples=samples+1;
    initial begin
        #100;@(negedge clk);resetn=1;
        @(posedge request);#500;
        if(valid || raw!=0 || !busy) $fatal(1,"Reused stale ready-high value");
        ready=0;#137;value=1000;#463;ready=1;
        wait(samples==1);
        if(raw!==1000 || code!==500 || timeout) $fatal(1,"Qualified result capture failed");
        // No completion: timeout must preserve the last sample and allow retry.
        @(posedge request);ready=0;wait(timeout);#1;
        if(busy || raw!==1000 || valid) $fatal(1,"Timeout fabricated data or kept busy");
        @(posedge request);#177;value=600;#319;ready=1;
        wait(samples==2);
        if(timeout || raw!==600 || code!==300) $fatal(1,"Timeout recovery failed");
        @(negedge clk);resetn=0;#40;
        if(raw!==0 || valid || busy || request || timeout) $fatal(1,"Capture reset failed");
        $display("PASS [ADC capture]: stale-ready rejection, asynchronous ready and stable bus, single completion, timeout/sample hold, retry recovery, reset");
        $finish;
    end
    initial begin #20000;$fatal(1,"ADC capture test timeout");end
endmodule
