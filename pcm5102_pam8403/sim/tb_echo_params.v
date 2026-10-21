`timescale 1ns/1ps
module tb_echo_params;
    reg clk=0,resetn=0,ce=0,compare_default=1;
    reg signed [15:0] dry=0;
    reg [1:0] mode=0,echo_tap=0;
    reg [3:0] wet=8;
    wire signed [15:0] pcm,old_pcm;
    wire valid,old_valid;
    always #10 clk=~clk;
    audio_effects #(.ADDRESS_BITS(12)) dut(.clk(clk),.resetn(resetn),.sample_valid(ce),.dry(dry),
        .mode(mode),.wet(wet),.echo_tap(echo_tap),.sample(pcm),.valid(valid));
    audio_effects_fixed_reference #(.ADDRESS_BITS(12)) reference(.clk(clk),.resetn(resetn),.sample_valid(ce),
        .dry(dry),.mode(mode),.wet(wet),.sample(old_pcm),.valid(old_valid));
    integer i,t,n,first,tails,clocks,expected_phase;
    integer reference_memory[0:4095];
    integer pointer,filled,group_count,group_sum,last_tap,held_wet,tap_value,filtered,expected,difference;
    function integer sat(input integer value);
        begin sat=value>32767 ? 32767 : value< -32768 ? -32768 : value;end
    endfunction
    always @(negedge clk) if(resetn && compare_default)begin
        if(valid!==old_valid || pcm!==old_pcm)$fatal(1,"Default effects changed at clock %0t",$time);
    end
    task frame(input integer data);
        begin
            @(negedge clk);dry=data;ce=1;
            @(negedge clk);ce=0;clocks=0;
            while(!valid && clocks<8)begin @(negedge clk);clocks=clocks+1;end
            if(!valid)$fatal(1,"Missing full-rate output");
            repeat(2)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;
        for(i=0;i<70000;i=i+1)begin
            mode=i<100 ? 0 : i<11000 ? 1 : 2;wet=i%10;
            frame((i%7==0) ? -32768 : i%7==1 ? 32767 : (i*617)%65536-32768);
        end
        compare_default=0;wet=8;
        for(t=0;t<4;t=t+1)begin
            mode=0;frame(0);echo_tap=t;mode=1;
            n=t==0 ? 1 : t==1 ? 2 : t==2 ? 4 : 6;first=-1;tails=0;
            for(i=0;i<4096*n+n+12;i=i+1)begin
                frame(i==0 ? 30000 : 0);
                if(i>0 && pcm!=0)begin if(first<0)first=i;tails=tails+1;end
                if(i==0 && pcm!=30000)$fatal(1,"Dry impulse changed");
            end
            if(first!=4096*n+n-1)$fatal(1,"tap %0d impulse first %0d expected %0d",t,first,4096*n+n-1);
            if(tails<n)$fatal(1,"Wet hold missing");
            $display("PASS echo tap %0d: first wet at frame %0d, nominal %.5f ms, wet sample period %0d",t,first,4096.0*n*1000.0/48828.125,n);
            echo_tap=(t+1)%4;frame(0);
            if(pcm!=0)$fatal(1,"Direct tap change leaked stale tail");
            mode=0;frame(0);mode=1;echo_tap=(t+1)%4;frame(0);
            if(pcm!=0)$fatal(1,"Mode/tap change leaked stale tail");
        end
        mode=0;frame(0);mode=1;echo_tap=3;
        pointer=0;filled=0;group_count=0;filtered=0;held_wet=0;tap_value=0;
        for(i=0;i<60000;i=i+1)begin
            dry=(i*1597)%65536-32768;filtered=filtered+(($signed(dry)-filtered)>>>2);group_count=group_count+1;
            if(group_count==6)begin
                tap_value=filled==4096 ? reference_memory[pointer] : 0;
                held_wet=(tap_value*8)>>>4;
                reference_memory[pointer]=sat((filtered>>>1)+(tap_value>>>1));
                pointer=(pointer+1)&4095;if(filled<4096)filled=filled+1;
                group_count=0;
            end
            expected=sat($signed(dry)+held_wet);frame($signed(dry));
            difference=$signed(pcm)-expected;
            if(difference!=0)$fatal(1,"6:1 low-pass/decimation deviation %0d at %0d",difference,i);
        end
        $display("PASS effects runtime: 70000 default frames clock-exact; four impulse delays; 6:1 exact full-scale signed low-pass filtering; full-rate dry; fixed chorus/default phase wrap");$finish;
    end
    initial begin #100000000;$fatal(1,"Effects runtime timeout");end
endmodule
