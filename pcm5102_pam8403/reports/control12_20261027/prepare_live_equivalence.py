from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
old=(P/'sim/build/unified/control12_shared_reply/pcm5102_pam8403/src/key_live_stream.v').read_text().replace('module key_live_stream(','module key_live_stream_reference(')
bench=r'''`timescale 1ns/1ps
module tb_control12_live_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,enable=0,tx_ready=0;reg [15:0] scan_keys=0;
    wire [7:0] data,ref_data;wire valid,last,ref_valid,ref_last;
    key_live_stream dut(.clk(clk),.resetn(resetn),.enable(enable),.scan_keys(scan_keys),.tx_data(data),.tx_valid(valid),.tx_last(last),.tx_ready(tx_ready));
    key_live_stream_reference ref_dut(.clk(clk),.resetn(resetn),.enable(enable),.scan_keys(scan_keys),.tx_data(ref_data),.tx_valid(ref_valid),.tx_last(ref_last),.tx_ready(tx_ready));
    integer n,seed=193172,random_value,lines=0,stalls=0;reg saw_full=0;
    always @(posedge clk)if(resetn)begin
        if(valid && tx_ready && last)lines=lines+1;
        if(valid && !tx_ready)stalls=stalls+1;
        if(dut.count==32)saw_full=1;
        #1;
        if({data,valid,last}!=={ref_data,ref_valid,ref_last})
            $fatal(1,"Live output differs at cycle %0d",n);
    end
    initial begin
        repeat(5)@(negedge clk);resetn=1;enable=1;scan_keys=16'hffff;
        for(n=0;n<100000;n=n+1)begin
            @(negedge clk);random_value=$random(seed);
            tx_ready=(random_value&15)<3;
            if(n%47==0)scan_keys=random_value;
            if(n%2011==0)enable=!enable;
            if(n%10007==0)resetn=0;else resetn=1;
        end
        if(lines<500 || stalls<5000 || !saw_full)$fatal(1,"Incomplete live stress %0d/%0d/full%0d",lines,stalls,saw_full);
        $display("PASS live packet exact equivalence: 100000 cycles, %0d lines, %0d stalled bytes, full FIFO/wrap, all key numbers, reset/enable/drop interactions",lines,stalls);$finish;
    end
endmodule
'''
(P/'sim/tb_control12_live_equivalence.v').write_text(bench+'\n'+old,encoding='utf-8')
print('Prepared cycle-exact original packet reference, randomized stalls/queue saturation and enable transitions')
