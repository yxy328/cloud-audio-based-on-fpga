`timescale 1ns/1ps
module tb_vibrato_params;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,sample_ce=0,enabled=1,vibrato_update=0;
    reg [31:0] vibrato_inc=527766;
    reg [9:0] vibrato_depth=256;
    reg [15:0] vibrato_delay=0;
    wire [31:0] phase_inc,expected;
    reg compare_default=1;
    integer i;
    reg [31:0] low=46025656,high=46025656;
    vibrato dut(.nominal_inc(32'd46025656),.*);
    vibrato_fixed_reference reference(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),
        .enabled(enabled),.nominal_inc(32'd46025656),.phase_inc(expected));
    always @(posedge clk)begin
        #1;if(resetn && compare_default && phase_inc!==expected)$fatal(1,"Default vibrato differs from frozen RTL");
    end
    task frame;
        begin sample_ce=1;@(negedge clk);sample_ce=0;repeat(20)@(negedge clk);end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;
        for(i=0;i<2100;i=i+1)frame;
        compare_default=0;vibrato_inc=703687;vibrato_depth=1023;
        for(i=0;i<14000;i=i+1)begin
            frame;
            if(phase_inc<low)low=phase_inc;
            if(phase_inc>high)high=phase_inc;
            if(phase_inc<41423090 || phase_inc>50628222)$fatal(1,"Deep vibrato wrapped or reversed sign");
        end
        if(low>43724373 || high<48326938)$fatal(1,"Deep vibrato did not exceed +/-5 percent");
        enabled=0;repeat(1024)frame;
        if(dut.depth!==0)$fatal(1,"Disable did not release depth");
        vibrato_delay=9766;vibrato_update=1;@(negedge clk);vibrato_update=0;enabled=1;
        repeat(9766)begin frame;if(dut.depth!==0)$fatal(1,"Vibrato started during onset wait");end
        frame;if(dut.depth!==1)$fatal(1,"Vibrato did not start after onset wait");
        $display("PASS vibrato parameters: every-clock frozen defaults, 8Hz/depth1023 without intermediate wrap, 9766-frame global onset; pitch bounds %0d..%0d",low,high);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Vibrato parameter timeout");end
endmodule
