`timescale 1ns/1ps
module tb_envelope_gain;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, sample_ce=0;
    reg signed [15:0] sample_in=0;
    reg [15:0] gain=0;
    wire signed [15:0] quiet_out, full_out;
    envelope_gain quiet(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),
        .sample_in(sample_in),.gain(gain),.sample_out(quiet_out));
    envelope_gain #(.VOLUME_SHIFT(0)) full_gain(.clk(clk),.resetn(resetn),
        .sample_ce(sample_ce),.sample_in(sample_in),.gain(gain),.sample_out(full_out));
    integer j, seed=197812, product, previous_quiet, previous_full, checks=0;
    task apply_sample;
        input integer value, level;
        begin
            @(negedge clk); sample_in=value; gain=level; sample_ce=1;
            product=value*level;
            @(posedge clk); #1;
            if(quiet_out != (product >>> 20) || full_out != (product >>> 16))
                $fatal(1,"Signed gain: in=%0d gain=%0d got=%0d/%0d expected=%0d/%0d",value,level,quiet_out,full_out,product>>>20,product>>>16);
            checks=checks+1;
            @(negedge clk); sample_ce=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        apply_sample(-32768,65535); apply_sample(32767,65535);
        apply_sample(-32768,32768); apply_sample(32767,32768);
        apply_sample(-32768,0); apply_sample(32767,0);
        apply_sample(-1,65535); apply_sample(1,65535);
        apply_sample(0,65535); apply_sample(-32768,1);
        for(j=0;j<1000;j=j+1) begin
            @(negedge clk); sample_in=$random(seed); gain=$random(seed);
            apply_sample($signed(sample_in),gain);
        end
        previous_quiet=quiet_out; previous_full=full_out;
        sample_in=1234; gain=12345;
        repeat(10) @(negedge clk);
        if(quiet_out!=previous_quiet || full_out!=previous_full) $fatal(1,"Gain ignored CE hold");
        resetn=0; repeat(3) @(negedge clk);
        if(quiet_out!=0 || full_out!=0) $fatal(1,"Gain reset");
        $display("PASS [gain]: %0d signed products; unsigned full-scale gain, negative extrema, zero/half/full gain, 1000 random pairs, CE hold, reset",checks);
        $finish;
    end
endmodule
