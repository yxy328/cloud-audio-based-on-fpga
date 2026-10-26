`timescale 1ns/1ps
module tb_audio_fx_chain;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,sample_valid=0;
    reg signed [15:0] dry=0;
    reg [2:0] mask=0;
    reg [7:0] settings=0;
    reg [11:0] wet_mix=0;
    wire signed [15:0] sample;
    wire valid,overrun;
    audio_fx_chain dut(.clk(clk),.resetn(resetn),.sample_valid(sample_valid),.dry(dry),
        .mask(mask),.settings(settings),.wet_mix(wet_mix),.sample(sample),.valid(valid),.overrun(overrun));
    reg [2047:0] vector_path,output_path;
    integer fd,out,status,reset_i,dry_i,mask_i,settings_i,mix_i,expected,frames=0,latency,max_latency=0;
    initial begin
        if(!$value$plusargs("vectors=%s",vector_path))$fatal(1,"Missing vectors");
        if(!$value$plusargs("outputs=%s",output_path))$fatal(1,"Missing outputs");
        fd=$fopen(vector_path,"r");out=$fopen(output_path,"w");
        if(!fd || !out)$fatal(1,"Cannot open vectors/outputs");
        repeat(3)@(negedge clk);resetn=1;
        while(!$feof(fd))begin
            status=$fscanf(fd,"%d %d %d %h %h %d\n",reset_i,dry_i,mask_i,settings_i,mix_i,expected);
            if(status!=6)$fatal(1,"Malformed vector %0d",frames);
            if(reset_i)begin resetn=0;repeat(2)@(negedge clk);resetn=1;end
            @(negedge clk);dry=dry_i;mask=mask_i;settings=settings_i;wet_mix=mix_i;sample_valid=1;
            @(negedge clk);sample_valid=0;latency=1;
            while(!valid)begin @(negedge clk);latency=latency+1;if(latency>100)$fatal(1,"Effect deadline");end
            if($signed(sample)!==expected)$fatal(1,"Sample %0d expected %0d got %0d mask=%0d settings=%h mix=%h",frames,expected,$signed(sample),mask,settings,wet_mix);
            if(overrun)$fatal(1,"Unexpected overrun");
            if(latency>max_latency)max_latency=latency;
            $fdisplay(out,"%0d,%0d,%0d",frames,$signed(sample),latency);frames=frames+1;
        end
        $display("PASS FX chain independent sample model frames=%0d max_latency=%0d",frames,max_latency);
        $fclose(fd);$fclose(out);$finish;
    end
endmodule
