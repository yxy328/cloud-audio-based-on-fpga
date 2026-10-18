`timescale 1ns/1ps
module tb_analog_expression;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,ce=0,av=0,timeout=0;
    reg [2:0] mode=0;
    reg [9:0] code=0,lo_code=0,hi_code=1023;
    reg [4:0] vol=16;
    wire [15:0] ratio;wire [12:0] gain;wire [3:0] wet;
    integer i,lo,hi;
    analog_expression dut(.clk(clk),.resetn(rst),.frame_ce(ce),.mode(mode),
        .adc_sample(code),.adc_min(lo_code),.adc_max(hi_code),.adc_valid(av),.adc_timeout(timeout),.fsr_ratio(16'd40000),
        .volume(vol),.wet(4'd4),.pitch_ratio(ratio),.master_gain(gain),.effect_wet(wet));
    task tick;begin @(negedge clk);ce=1;@(negedge clk);ce=0;end endtask
    task update;input [9:0] n;begin @(negedge clk);code=n;av=1;@(negedge clk);av=0;repeat(24)@(negedge clk);end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;#1;
        if(ratio!=40000 || gain!=4096 || wet!=4)$fatal(1,"Legacy FSR bypass");
        mode=1;update(0);if(gain!=0)$fatal(1,"Slider mute");
        update(1023);if(gain!=4096)$fatal(1,"Slider unity");
        vol=8;#1;if(gain!=2048)$fatal(1,"Manual volume cap");
        update(256);if(gain!=1024)$fatal(1,"Linear slider volume");
        mode=2;update(0);if(ratio!=32768)$fatal(1,"Half pitch endpoint");
        update(1023);if(ratio!=65535)$fatal(1,"Exact unity endpoint");
        mode=4;
        for(i=0;i<1024;i=i+1)begin update(i);if(wet!=(i==1023 ? 8 : i/128))$fatal(1,"Wet mapping %0d",i);end
        lo_code=50;hi_code=600;mode=2;update(50);if(ratio!=32768)$fatal(1,"Calibrated low endpoint");
        update(600);if(ratio!=65535)$fatal(1,"Calibrated high endpoint");
        update(325);if(ratio!=32768+511*32)$fatal(1,"Calibrated middle");
        lo_code=0;hi_code=1023;
        mode=3;update(1023);lo=65535;hi=0;
        for(i=0;i<8192;i=i+1)begin
            if(i%100==0)update(1023);tick;
            if(ratio<lo)lo=ratio;if(ratio>hi)hi=ratio;
        end
        if(lo>63500 || hi<65530)$fatal(1,"Vibrato depth / period %0d %0d",lo,hi);
        timeout=1;#1;if(ratio!=65535 || gain!=2048 || wet!=4)$fatal(1,"ADC fault fallback");
        timeout=0;mode=1;update(0);repeat(4884)tick;
        if(gain!=2048)$fatal(1,"Stale ADC must release slider mute");
        $display("PASS analog expression: FSR passthrough, volume cap/endpoints, pitch, all wet codes, full vibrato period, timeout/stale fallback");$finish;
    end
endmodule
