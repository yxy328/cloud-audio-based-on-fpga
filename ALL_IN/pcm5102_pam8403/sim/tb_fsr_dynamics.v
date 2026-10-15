`timescale 1ns/1ps
module tb_fsr_dynamics;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0,valid=0;
    reg [9:0] adc=1023;
    wire [9:0] pressure,forward_pressure;
    wire [15:0] target,gain,forward_target,forward_gain;
    fsr_dynamics dut(.clk(clk),.resetn(resetn),.sample_ce(ce),.expression_enable(1'b1),.adc_valid(valid),
        .adc_sample(adc),.pressure_code(pressure),.target_gain(target),.gain(gain));
    fsr_dynamics #(.ADC_INVERT(0),.GAIN_REVERSE(0),.MIN_GAIN(0)) forward(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.expression_enable(1'b1),.adc_valid(valid),.adc_sample(adc),
        .pressure_code(forward_pressure),.target_gain(forward_target),.gain(forward_gain));
    integer p,expected,forward_expected,previous_target=65535,error,old_gain,delta,n;
    reg sampled_ce;
    always @(posedge clk) begin
        old_gain=gain;sampled_ce=ce;#1;
        if(resetn) begin
            delta=gain-old_gain;if(delta<0) delta=-delta;
            if(delta>64 || (!sampled_ce && delta!=0)) $fatal(1,"FSR slew/clock-enable violated");
        end
    end
    task send_adc;
        input [9:0] value;
        begin
            @(negedge clk);adc=value;valid=1;
            @(negedge clk);valid=0;
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        #100;@(negedge clk);resetn=1;
        // Sweep EVERY ADC code against arithmetic independent of reciprocal.
        for(p=0;p<1024;p=p+1) begin
            send_adc(1023-p);
            if(p<=32) expected=65535;
            else if(p>=900) expected=16384;
            else expected=65535-(p-32)*49151/868;
            error=target-expected;if(error<0) error=-error;
            if(pressure!==p || error>1 || target>previous_target)
                $fatal(1,"FSR decreasing volume/calibration/monotonicity failed at %0d",p);
            previous_target=target;
            if(gain!==65535) $fatal(1,"FSR changed gain without audio CE");
            // Original gain direction remains selectable, independently of AO polarity.
            if(1023-p<=32) forward_expected=0;
            else if(1023-p>=900) forward_expected=65535;
            else forward_expected=(1023-p-32)*65535/868;
            error=forward_target-forward_expected;if(error<0) error=-error;
            if(forward_pressure!==1023-p || error>1)
                $fatal(1,"FSR forward AO/original gain direction failed at %0d",p);
        end
        if(forward_pressure!==0 || forward_target!==0) $fatal(1,"Forward polarity/zero minimum failed");
        ce=1;repeat(800) @(negedge clk);
        if(gain!==16384) $fatal(1,"Heavy force did not reach minimum gain");
        send_adc(1023);repeat(800) @(negedge clk);
        if(gain!==65535 || forward_target!==65535) $fatal(1,"Released force did not return to full gain");
        ce=0;old_gain=gain;repeat(20) @(negedge clk);
        if(gain!==65535 || target!==65535) $fatal(1,"FSR held value failed");
        resetn=0;@(negedge clk);
        if(gain!==65535 || target!==65535 || pressure!==0) $fatal(1,"FSR reset failed");
        $display("PASS [FSR dynamics]: all 1024 codes in both gain directions, heavy force lowers volume, <=1 gain-LSB error, independent AO polarity, zero floor, 64-LSB slew, CE hold and reset");
        $finish;
    end
endmodule
