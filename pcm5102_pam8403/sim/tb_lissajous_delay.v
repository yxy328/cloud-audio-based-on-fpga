`timescale 1ns/1ps
// Non-periodic steps distinguish the delayed Y channel from a copy of X.
module tb_lissajous_delay;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0,boundary=0;
    reg signed [15:0] sample=0;
    reg [5:0] x=0;
    reg [4:0] y=0;
    wire [14:0] upper,lower;
    integer n;
    audio_visualizer dut (.clk(clk),.resetn(resetn),.sample_ce(ce),.display_boundary(boundary),
        .service_ce(1'b1),.style_ce(1'b1),.visual_mode(2'd2),.mixed_sample(sample),
        .reference_ratio(2'd0),.reference_phase(2'd0),
        .touch0(16'sd0),.touch1(16'sd0),.sensor_sample(16'sd0),.guitar_sample(16'sd0),
        .pixel_x(x),.pixel_row(y),.upper_rgb(upper),.lower_rgb(lower));
    task tick;
        input signed [15:0] value;
        begin @(negedge clk);sample=value;ce=1;
            @(negedge clk);ce=0;repeat(6) @(negedge clk);end
    endtask
    task publish;
        begin wait(dut.capture_ready);@(negedge clk);boundary=1;
            @(negedge clk);boundary=0;wait(!dut.clearing);end
    endtask
    task inspect;
        input [5:0] px;input [4:0] py;input [14:0] expected;
        begin @(negedge clk);x=px;y=py;repeat(2) @(negedge clk);
            if(upper!==expected) $fatal(1,"XY %0d,%0d=%h expected %h",px,py,upper,expected);end
    endtask
    initial begin
        repeat(4) @(negedge clk);resetn=1;wait(!dut.clearing);
        for(n=0;n<32;n=n+1)tick(4096);
        for(n=0;n<32;n=n+1)tick(-4096);
        for(n=64;n<512;n=n+1)tick(0);
        publish;
        inspect(16,8,{5'd24,5'd4,5'd31}); // Current negative X, old positive Y.
        inspect(16,24,0); // A non-delayed copy would incorrectly draw here.
        inspect(32,24,{5'd24,5'd4,5'd31});
        for(n=0;n<512;n=n+1)tick(0);
        publish;
        inspect(16,8,0); // Old trajectory must clear from the next back bank.
        inspect(32,16,{5'd24,5'd4,5'd31});
        $display("PASS Lissajous: exact 32-sample delayed Y, signed step trajectory, zero signal center and cleared next frame");$finish;
    end
    initial begin #1000000;$fatal(1,"Lissajous timeout");end
endmodule
