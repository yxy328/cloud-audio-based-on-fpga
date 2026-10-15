`timescale 1ns/1ps
module tb_gowin_fsr_adc;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;
    wire [13:0] raw;
    wire [9:0] code;
    wire valid,busy,timeout;
    gowin_fsr_adc dut(.clk(clk),.resetn(resetn),.raw_value(raw),
        .adc_sample(code),.sample_valid(valid),.busy(busy),.timeout(timeout));
    integer received=0;
    time previous_clock=0,request_time=0,previous_request=0;
    reg previous_valid=0;
    always @(posedge dut.adc_clk) begin
        if(previous_clock!=0 && $time-previous_clock!=400)
            $fatal(1,"ADC clock is not 2.5MHz");
        previous_clock=$time;
    end
    always @(posedge dut.adc_request) begin
        if(previous_request!=0 && $time-previous_request!=1000000)
            $fatal(1,"ADC request cadence is not 1kHz");
        previous_request=$time;request_time=$time;
    end
    always @(negedge dut.adc_request)
        if(resetn && request_time!=0 && $time-request_time!=1280)
            $fatal(1,"ADC request pulse is not 1.28us");
    always @(negedge clk) begin
        if(valid) begin
            if(previous_valid || busy || timeout || $time-request_time<417600)
                $fatal(1,"ADC completion pulse/timing/flags incorrect");
            received=received+1;
        end
        previous_valid=valid;
    end
    task read_value;
        input [13:0] value;
        input [9:0] expected;
        integer before;
        begin
            @(negedge clk);dut.adc_inst.sim_value=value;before=received;
            wait(received>before);@(negedge clk);
            if(raw!==value || code!==expected) $fatal(1,"ADC raw/normalization mismatch");
        end
    endtask
    initial begin
        #100;@(negedge clk);resetn=1;
        read_value(0,0);read_value(2,1);read_value(1024,512);
        read_value(2046,1023);read_value(3000,1023);
        if(dut.adc_inst.conversions!=5) $fatal(1,"Missing ADC conversions");
        $display("PASS [on-chip ADC]: 2.5MHz clock, 1kHz requests, 1.28us request hold, 1024-cycle conversion model, five raw/normalized boundary codes, valid pulse");
        $finish;
    end
    initial begin #6500000;$fatal(1,"On-chip ADC test timeout");end
endmodule
