`timescale 1ns/1ps
module tb_take_key_control;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ready=1,mode16=1;
    reg [3:0] keys=0;reg [1:0] confirm=0;
    wire [2:0] command;
    take_key_control dut(.*);
    integer pulses=0,last=0,checks=0;
    always @(negedge clk)if(command!=0)begin pulses=pulses+1;last=command;end
    task press;input [3:0] mask;input integer expected;integer before_count;begin
        before_count=pulses;@(negedge clk);keys=mask;
        repeat(8)@(negedge clk);keys=0;repeat(4)@(negedge clk);
        checks=checks+1;
        if(pulses-before_count!=(expected==0 ? 0 : 1) || (expected!=0 && last!=expected))
            $fatal(1,"keys=%h expected=%0d actual=%0d pulses=%0d",mask,expected,last,pulses-before_count);
    end endtask
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        press(1,3);press(2,2);press(4,1);press(8,7);
        confirm=1;press(4,5);press(2,2);
        confirm=0;press(10,4);confirm=2;press(8,5);
        mode16=0;press(4,0);mode16=1;ready=0;press(8,0);
        $display("PASS tb_take_key_control: %0d checks; held keys issue one command",checks);$finish;
    end
endmodule
