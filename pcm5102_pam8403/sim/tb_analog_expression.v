`timescale 1ns/1ps
// Two independent channels: pressure pitch is always the base, the slider
// adds volume / pitch / vibrato depth / wet amount when MODE selects it.
module tb_analog_expression;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,ce=0,av=0,timeout=0;
    reg [2:0] mode=0;
    reg [9:0] code=0,lo_code=0,hi_code=1023;
    reg [4:0] vol=16;
    reg [15:0] pressure=16'd40000;
    wire [15:0] ratio;wire [12:0] gain;wire [3:0] wet;wire [9:0] position;wire available;
    integer i,lo,hi;
    analog_expression dut(.clk(clk),.resetn(rst),.frame_ce(ce),.mode(mode),
        .adc_sample(code),.adc_min(lo_code),.adc_max(hi_code),.adc_valid(av),.adc_timeout(timeout),
        .pressure_pitch(pressure),.volume(vol),.wet(4'd4),
        .pitch_ratio(ratio),.master_gain(gain),.effect_wet(wet),
        .position(position),.available(available));
    task tick;begin @(negedge clk);ce=1;@(negedge clk);ce=0;end endtask
    task update;input [9:0] n;begin @(negedge clk);code=n;av=1;@(negedge clk);av=0;repeat(24)@(negedge clk);end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;#1;
        // MODE=0: slider idle, pressure pitch and manual controls pass through.
        if(ratio!=40000 || gain!=4096 || wet!=4 || available!==0)$fatal(1,"Idle slider passthrough");
        mode=1;update(0);if(gain!=0)$fatal(1,"Slider mute");
        update(1023);if(gain!=4096)$fatal(1,"Slider unity");
        vol=8;#1;if(gain!=2048)$fatal(1,"Manual volume cap");
        update(256);if(gain!=1024)$fatal(1,"Linear slider volume");
        if(ratio!=40000)$fatal(1,"Pressure pitch lost in slider volume mode");
        mode=2;update(0);if(ratio!=32768)$fatal(1,"Half pitch endpoint");
        update(1023);if(ratio!=65535)$fatal(1,"Exact unity endpoint");
        mode=4;
        for(i=0;i<1024;i=i+1)begin update(i);if(wet!=(i==1023 ? 8 : i/128))$fatal(1,"Wet mapping %0d",i);end
        if(ratio!=40000)$fatal(1,"Pressure pitch lost in wet mode");
        lo_code=50;hi_code=600;mode=2;update(50);if(ratio!=32768)$fatal(1,"Calibrated low endpoint");
        update(600);if(ratio!=65535)$fatal(1,"Calibrated high endpoint");
        update(325);if(ratio!=32768+511*32)$fatal(1,"Calibrated middle");
        lo_code=0;hi_code=1023;
        // Vibrato around the pressure base: unity base first.
        pressure=16'hffff;mode=3;update(1023);lo=65535;hi=0;
        for(i=0;i<8192;i=i+1)begin
            if(i%100==0)update(1023);tick;
            if(ratio<lo)lo=ratio;if(ratio>hi)hi=ratio;
        end
        if(lo>63500 || hi<65530)$fatal(1,"Vibrato depth / period %0d %0d",lo,hi);
        // Same slider depth with a pressure bend: vibrato subtracts from the base.
        pressure=16'd40000;lo=65535;hi=0;
        for(i=0;i<8192;i=i+1)begin
            if(i%100==0)update(1023);tick;
            if(ratio<lo)lo=ratio;if(ratio>hi)hi=ratio;
        end
        if(lo>38000 || hi<39900)$fatal(1,"Vibrato base %0d %0d",lo,hi);
        // Slider fault: pressure pitch, manual volume and wet fallback.
        timeout=1;#1;if(ratio!=40000 || gain!=2048 || wet!=4)$fatal(1,"Slider fault fallback");
        if(available!==0)$fatal(1,"Faulted slider must not report available");
        timeout=0;mode=1;update(0);repeat(4884)tick;
        if(gain!=2048)$fatal(1,"Stale slider must release its mute");
        if(available!==0)$fatal(1,"Stale slider must not report available");
        mode=0;update(800);
        if(available!==0)$fatal(1,"Idle mode exposed the slider as available");
        $display("PASS analog expression: pressure pitch as base, slider volume cap/endpoints, slider pitch, all wet codes, full vibrato period with bent base, fault and stale fallback");$finish;
    end
endmodule
