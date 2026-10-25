`timescale 1ns/1ps
module tb_apds_width;
    reg clk=0, rst_n=0;
    apds9960_ctrl candidate(.clk(clk),.rst_n(rst_n),.i2c_busy(1'b0),
        .i2c_done(1'b0),.i2c_nack(1'b0),.i2c_rdata(8'd0),.i2c_rvalid(1'b0));
    apds9960_ctrl_reference reference(.clk(clk),.rst_n(rst_n),.i2c_busy(1'b0),
        .i2c_done(1'b0),.i2c_nack(1'b0),.i2c_rdata(8'd0),.i2c_rvalid(1'b0));
    reg [31:0] first_sample,last_sample,rng=32'hb7651293;
    integer i,k,count=0;
    function [31:0] next_random;
        input [31:0] x;
        reg [31:0] y;
        begin y=x^(x<<13); y=y^(y>>17); next_random=y^(y<<5); end
    endfunction
    task tick;
        begin #5;clk=1;#5;clk=0;end
    endtask
    task check;
        begin
            candidate.first_ud=$signed({1'b0,first_sample[7:0]})-$signed({1'b0,first_sample[15:8]});
            candidate.first_lr=$signed({1'b0,first_sample[23:16]})-$signed({1'b0,first_sample[31:24]});
            candidate.last_ud=$signed({1'b0,last_sample[7:0]})-$signed({1'b0,last_sample[15:8]});
            candidate.last_lr=$signed({1'b0,last_sample[23:16]})-$signed({1'b0,last_sample[31:24]});
            candidate.first_ud_sum={1'b0,first_sample[7:0]}+{1'b0,first_sample[15:8]};
            candidate.first_lr_sum={1'b0,first_sample[23:16]}+{1'b0,first_sample[31:24]};
            candidate.last_ud_sum={1'b0,last_sample[7:0]}+{1'b0,last_sample[15:8]};
            candidate.last_lr_sum={1'b0,last_sample[23:16]}+{1'b0,last_sample[31:24]};
            reference.first_ud=candidate.first_ud;reference.first_lr=candidate.first_lr;
            reference.last_ud=candidate.last_ud;reference.last_lr=candidate.last_lr;
            reference.first_ud_sum=candidate.first_ud_sum;reference.first_lr_sum=candidate.first_lr_sum;
            reference.last_ud_sum=candidate.last_ud_sum;reference.last_lr_sum=candidate.last_lr_sum;
            candidate.state=19;reference.state=19;
            candidate.event_samples=4;reference.event_samples=4;
            candidate.event_bad=0;reference.event_bad=0;
            tick;
            if($signed(candidate.delta_ud)!==$signed(reference.delta_ud) ||
               $signed(candidate.delta_lr)!==$signed(reference.delta_lr) ||
               candidate.scale_ud!==reference.scale_ud || candidate.scale_lr!==reference.scale_lr)
                $fatal(1,"delta/scale mismatch first=%h last=%h",first_sample,last_sample);
            tick;
            if(candidate.ud_strength!==reference.ud_strength || candidate.lr_strength!==reference.lr_strength ||
               candidate.start_dir_c!==reference.start_dir_c || candidate.end_dir_c!==reference.end_dir_c)
                $fatal(1,"strength/direction mismatch first=%h last=%h",first_sample,last_sample);
            tick;
            if({candidate.gesture_valid,candidate.start_dir,candidate.end_dir,candidate.dir_evaluated} !==
               {reference.gesture_valid,reference.start_dir,reference.end_dir,reference.dir_evaluated})
                $fatal(1,"report mismatch");
            count=count+1;
        end
    endtask
    initial begin
        tick;tick;rst_n=1;
        // All 256 corners of eight independent byte intervals [0,255].
        for(i=0;i<256;i=i+1) begin
            for(k=0;k<4;k=k+1) begin
                first_sample[k*8 +: 8]=((i>>k)&1) ? 255:0;
                last_sample[k*8 +: 8]=((i>>(k+4))&1) ? 255:0;
            end
            check;
        end
        for(i=0;i<50000;i=i+1) begin
            rng=next_random(rng);first_sample=rng;
            rng=next_random(rng);last_sample=rng;check;
        end
        $display("PASS APDS width equivalence: %0d endpoint tuples; exact delta, scale, strength, direction and report cycle",count);
        $finish;
    end
endmodule
