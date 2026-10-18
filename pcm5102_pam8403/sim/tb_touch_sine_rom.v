`timescale 1ns/1ps
module tb_touch_sine_rom;
    reg clk=0;always #10 clk=~clk;
    reg rst=0;
    reg [31:0] phase=0;
    wire signed [15:0] actual,expected;
    integer i,k;
    touch_sine_rom dut(.clk(clk),.phase(phase),.sample(actual));
    sine_rom reference(.address(phase[31:22]),.sample(expected));
    initial begin
        repeat(4)@(negedge clk);rst=1;
        for(i=0;i<1024;i=i+1)begin
            phase=i<<22;
            repeat(8)@(negedge clk);
            if(actual!==expected)$fatal(1,"Shared sine ROM mismatch %0d: %h != %h",i,actual,expected);
        end
        $display("PASS shared sine ROM: exact original waveform on all 1024 addresses, four independent phases");$finish;
    end
endmodule
