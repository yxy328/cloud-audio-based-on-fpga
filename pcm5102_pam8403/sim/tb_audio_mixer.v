`timescale 1ns/1ps
module tb_audio_mixer;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, sample_ce=0;
    reg signed [15:0] a=0,b=0,c=0,d=0;
    wire signed [15:0] direct_sample,quarter_sample;
    wire direct_clip,quarter_clip;
    audio_mixer direct(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),
        .sample0(a),.sample1(b),.sample2(c),.sample3(d),
        .sample_out(direct_sample),.clipped(direct_clip));
    audio_mixer #(.MIX_SHIFT(2)) quarter(.clk(clk),.resetn(resetn),.sample_ce(sample_ce),
        .sample0(a),.sample1(b),.sample2(c),.sample3(d),
        .sample_out(quarter_sample),.clipped(quarter_clip));
    integer checks=0,seed=810723,j,total,divided,expected_direct,expected_quarter;
    integer saved_direct,saved_quarter;
    reg saved_direct_clip,saved_quarter_clip;
    function integer limited;
        input integer value;
        begin
            if(value>32767) limited=32767;
            else if(value< -32768) limited=-32768;
            else limited=value;
        end
    endfunction
    task check_mix;
        input integer va,vb,vc,vd;
        begin
            @(negedge clk); a=va;b=vb;c=vc;d=vd;sample_ce=1;
            total=va+vb+vc+vd;
            // Arithmetic division with floor, independent of HDL shift widths.
            divided=(total>=0)?total/4:-((-total+3)/4);
            expected_direct=limited(total);expected_quarter=limited(divided);
            @(posedge clk);#1;
            if(direct_sample!=expected_direct || quarter_sample!=expected_quarter)
                $fatal(1,"Mixer sum/sign/saturation: %0d/%0d expected %0d/%0d",direct_sample,quarter_sample,expected_direct,expected_quarter);
            if(direct_clip!=(total!=expected_direct) || quarter_clip!=(divided!=expected_quarter))
                $fatal(1,"Mixer clip flag");
            checks=checks+1;
            @(negedge clk);sample_ce=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);resetn=1;
        check_mix(32767,32767,32767,32767);
        check_mix(-32768,-32768,-32768,-32768);
        check_mix(32767,32767,-32768,-32768);
        check_mix(32767,1,0,0);check_mix(-32768,-1,0,0);
        check_mix(32767,0,0,0);check_mix(-32768,0,0,0);
        check_mix(-1,0,0,0);check_mix(-3,0,0,0);check_mix(0,0,0,0);
        check_mix(-2048,-2048,-2048,-2048);
        for(j=0;j<1000;j=j+1) begin
            @(negedge clk);a=$random(seed);b=$random(seed);c=$random(seed);d=$random(seed);
            check_mix($signed(a),$signed(b),$signed(c),$signed(d));
        end
        saved_direct=direct_sample;saved_quarter=quarter_sample;
        saved_direct_clip=direct_clip;saved_quarter_clip=quarter_clip;
        a=32767;b=32767;c=32767;d=32767;
        repeat(10) @(negedge clk);
        if(direct_sample!=saved_direct || quarter_sample!=saved_quarter ||
           direct_clip!=saved_direct_clip || quarter_clip!=saved_quarter_clip)
            $fatal(1,"Mixer changed without sample_ce");
        resetn=0;repeat(3) @(negedge clk);
        if(direct_sample!=0 || quarter_sample!=0 || direct_clip || quarter_clip)
            $fatal(1,"Mixer reset");
        $display("PASS [mixer]: %0d vectors; full-scale four-way sum, positive/negative clipping, cancellation, 1/4 scaling, 1000 random vectors, CE hold and reset",checks);
        $finish;
    end
endmodule
