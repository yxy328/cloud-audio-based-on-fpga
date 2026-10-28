`timescale 1ns/1ps
`include "sim/reference/audio_spectrum_score256_reference.v"
module tb_audio_spectrum;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0;
    reg signed [15:0] sample=0;
    wire [79:0] levels;
    wire valid,done;
    wire [7:0] peak;
    wire [16:0] magnitude;
    integer scenario=0,n=0,ticks=0,k,output_file;
    integer captured[0:255];
    real value;
    audio_spectrum dut (.clk(clk),.resetn(resetn),.sample_ce(ce),.sample(sample),
        .levels(levels),.valid(valid),.done(done),.peak_bin(peak),.peak_magnitude(magnitude));
    wire [79:0] reference_levels;
    wire reference_valid,reference_done;
    wire [7:0] reference_peak;
    wire [16:0] reference_magnitude;
    audio_spectrum_score256_reference reference_dut(.clk(clk),.resetn(resetn),.sample_ce(ce),.sample(sample),
        .levels(reference_levels),.valid(reference_valid),.done(reference_done),
        .peak_bin(reference_peak),.peak_magnitude(reference_magnitude));
    always @(negedge clk)if(resetn)begin
        if({levels,valid,done,peak,magnitude}!=={reference_levels,reference_valid,reference_done,reference_peak,reference_magnitude} ||
           dut.working_levels!==reference_dut.working_levels)
            $fatal(1,"spectrum timing optimization changed a cycle or numerical output");
        if(dut.state==36 && dut.previous_height!==reference_dut.working_levels[reference_dut.band*5+:5])
            $fatal(1,"registered previous height differs at accumulation");
    end
    always @(negedge clk) begin
        ce=0;
        if(!resetn) begin ticks=0;n=0;sample=0;end
        else if(ticks==63) begin
            ticks=0;ce=1;
            case(scenario)
                0:value=0;
                1:value=12000.0*$sin(6.283185307179586*11*n/2048.0);
                2:value=9000.0*$sin(6.283185307179586*11*n/2048.0)+6000.0*$sin(6.283185307179586*35*n/2048.0);
                3:value=12000.0*$sin(6.283185307179586*267*n/2048.0);
            endcase
            sample=$rtoi(value);n=n+1;
        end else ticks=ticks+1;
    end
    always @(posedge clk) if(resetn && dut.state==4)
        captured[dut.capture_index]=$signed(dut.product) >>> 15;
    initial begin
        output_file=$fopen("sim/build/audio_spectrum_numeric.csv","w");
        if(!output_file)$fatal(1,"Cannot write FFT numerical evidence");
        $fdisplay(output_file,"scenario,index,input,real,imag");
        for(scenario=0;scenario<4;scenario=scenario+1) begin
            @(posedge clk);resetn=0;
            repeat(4) @(posedge clk);#1;resetn=1;
            wait(done);#1;
            if(!valid)$fatal(1,"FFT publish invalid");
            if(scenario==0 && (levels || magnitude)) $fatal(1,"Silence produced spectrum");
            if((scenario==1 || scenario==2) && peak!=11) $fatal(1,"Tone peak=%0d expected 11",peak);
            if(scenario==1 && (magnitude<2500 || magnitude>4200)) $fatal(1,"Unexpected tone amplitude %0d",magnitude);
            if(scenario==2 && (levels[4*5+:5]==0 || levels[11*5+:5]==0)) $fatal(1,"Two-tone bands missing");
            if(scenario==3 && magnitude>10) $fatal(1,"CIC failed to reject alias image: %0d",magnitude);
            for(k=0;k<256;k=k+1)
                $fdisplay(output_file,"%0d,%0d,%0d,%0d,%0d",scenario,k,captured[k],
                    $signed(dut.memory[k*2]),$signed(dut.memory[k*2+1]));
            $display("FFT scenario %0d peak=%0d magnitude=%0d levels=%h",scenario,peak,magnitude,levels);
            @(posedge clk);#1;
        end
        $fclose(output_file);
        $display("PASS audio spectrum: silence, single/two tones, CIC alias rejection, full complex FFT dump, cycle-exact reference including every accumulation band");$finish;
    end
    initial begin #50000000;$fatal(1,"FFT timeout state=%0d index=%0d",dut.state,dut.capture_index);end
endmodule
