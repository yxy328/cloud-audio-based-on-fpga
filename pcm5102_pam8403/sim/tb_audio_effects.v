`timescale 1ns/1ps
module tb_audio_effects;
    reg clk=0,rst=0,ce=0;
    reg signed [15:0] dry=0;
    reg [1:0] mode=0;
    reg [3:0] wet=8;
    wire signed [15:0] pcm;
    wire valid;
    always #10 clk=~clk;
    audio_effects #(.ADDRESS_BITS(12)) dut(.clk(clk),.resetn(rst),.sample_valid(ce),.dry(dry),
        .mode(mode),.wet(wet),.sample(pcm),.valid(valid));
    integer memory[0:4095];
    integer pointer=0,filled=0,last_mode=0,lfo=0,i,j,tap,delay_n,expected,feedback,tri_n;
    integer tails=0,saturations=0;
    function integer sat(input integer n);
        begin sat=(n>32767) ? 32767 : (n< -32768) ? -32768 : n;end
    endfunction
    task step(input integer data,input integer m,input integer w);
        begin
            @(negedge clk);ce=1;dry=data;mode=m;wet=w;
            if(m!=last_mode) begin pointer=0;filled=0;end
            tri_n=(lfo&32767)>>7;if(lfo&32768) tri_n=255-tri_n;
            delay_n=(m==2) ? 1024+tri_n : 4096;
            tap=(filled>=delay_n) ? memory[(pointer-delay_n)&4095] : 0;
            expected=(m==0) ? data : sat(data+((tap*((w>8) ? 8 : w))>>>4));
            feedback=(m==1) ? sat((data>>>1)+(tap>>>1)) : data;
            memory[pointer]=feedback;pointer=(pointer+1)&4095;
            if(filled<4096) filled=filled+1;
            last_mode=m;lfo=(lfo+1)&65535;
            @(negedge clk);ce=0;j=0;
            while(!valid && j<9) begin @(negedge clk);j=j+1;end
            if(!valid || $signed(pcm)!==expected) $fatal(1,"FX i=%0d mode=%0d expected=%0d actual=%0d",i,m,expected,$signed(pcm));
            if(data==0 && pcm!=0) tails=tails+1;
            if(pcm==32767 || $signed(pcm)==-32768) saturations=saturations+1;
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        step(-32768,0,8);step(32767,0,8);
        for(i=0;i<25000;i=i+1) step((i==0) ? 30000 : 0,1,8);
        if(tails<3) $fatal(1,"Feedback echo must retain audible delayed tails");
        for(i=0;i<25000;i=i+1) step((i%4==0) ? -32768 : (i%4==1) ? 32767 : (i%97)*673-32000,2,i%10);
        for(i=0;i<9000;i=i+1) step(-30000,1,8);
        step(20000,0,8);step(-12000,1,8);step(32000,2,0);
        if(saturations<10) $fatal(1,"No clipping/overflow coverage");
        $display("PASS FX independent circular-buffer model: 59005 samples, exact dry/wet, echo feedback tails, chorus tap modulation, mode clears, signed saturation (%0d clipped)",saturations);
        $finish;
    end
    initial begin #30000000;$fatal(1,"FX timeout");end
endmodule
