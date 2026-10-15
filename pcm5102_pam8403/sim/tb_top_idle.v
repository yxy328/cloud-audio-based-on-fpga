`timescale 1ns/1ps
// Production-parameter pin-only smoke test, also usable with the live PNR netlist.
module tb_top_idle;
    reg clk=0;
    always #10 clk=~clk;
    reg s1=0,s2=0;
    wire bck,lrck,din,scl;
    top dut(.clk(clk),.key_s1(s1),.key_s2(s2),.touch_out(8'd0),
        .hc05_rx(1'b1),.hc05_tx(),.i2s_bck(bck),.i2s_lrck(lrck),
        .i2s_din(din),.touch_scl(scl));
    i2s_pcm_monitor monitor(.bck(bck),.lrck(lrck),.din(din));
    always @(negedge clk) if(scl!==1'b1) $fatal(1,"Direct touch SCL not held HIGH");
    integer i;
    initial begin
        #100000; s1=1;
        #1200000; s1=0;
        #100000; s2=1;
        #1200000; s2=0;
        #200000;
        for(i=0;i<monitor.pcm_count;i=i+1)
            if(monitor.pcm[i]!==0) $fatal(1,"No-touch live build generated audio");
        if(monitor.pair_count<100) $fatal(1,"I2S output clock missing");
        $display("PASS [live idle]: production parameters; S1/S2 produce no audio without touch, %0d stereo pairs",monitor.pair_count);
        $fclose(monitor.capture_file); $finish;
    end
    initial begin #5000000; $fatal(1,"Live idle timeout"); end
endmodule
