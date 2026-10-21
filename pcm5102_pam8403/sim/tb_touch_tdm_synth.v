`timescale 1ns/1ps
module tb_touch_tdm_synth;
    reg clk=0;always #10 clk=~clk;
    reg rst=0;
    reg [9:0] divider=0;
    wire ce=divider==0;
    always @(posedge clk)divider<=divider+1'b1;
    reg [15:0] gates=0;
    reg [63:0] cfg={16'd4,16'd3,16'd32768,16'd8};
    reg [15:0] ratio=65535;
    wire signed [15:0] pcm;
    wire [15:0] active;
    wire overrun;
    integer i,j,n,frame=0;
    real co,si,angle,amp,window,weight;
    reg [31:0] previous[0:15];
    integer samples[0:4095];
    reg [31:0] before_phase,after_phase;
    touch_tdm_synth dut(.clk(clk),.resetn(rst),.sample_ce(ce),.gates(gates),.low_steps({32'd32545054,32'd30718440,32'd28994347,32'd27367019,32'd25831026,32'd24381242,32'd23012828}),
        .adsr_config(cfg),.pitch_ratio(ratio),.sample(pcm),.active(active),.overrun(overrun));
    always @(negedge clk)if(rst && ce)begin frame=frame+1;if(overrun)$fatal(1,"Extended voice frame deadline");end
    task frames;input integer count;integer finish;begin finish=frame+count;wait(frame>=finish);@(negedge clk);end endtask
    function [31:0] expected_step;
        input integer key;integer note;real hz;
        begin
            if(key<12)note=60+key;
            else case(key)12:note=72;13:note=74;14:note=76;default:note=77;endcase
            hz=440.0*$pow(2.0,(note-69)/12.0);
            expected_step=$rtoi(hz*4294967296.0/48828.125+0.5);
        end
    endfunction
    function [31:0] step;input integer key;begin step=expected_step(key+7);end endfunction
    initial begin
        repeat(4)@(negedge clk);rst=1;frames(3);gates=16'hffff;frames(15);
        if(active!=16'hffff || overrun)$fatal(1,"Sixteen simultaneous envelope segments exceeded frame");
        for(n=0;n<32;n=n+1)begin
            for(i=0;i<16;i=i+1)previous[i]={dut.contexts[i*16+1],dut.contexts[i*16]};
            frames(1);
            for(i=0;i<16;i=i+1)if(({dut.contexts[i*16+1],dut.contexts[i*16]}-previous[i])!==expected_step(i))
                $fatal(1,"Chromatic phase increment K%0d: expected %0d",i+1,expected_step(i));
        end
        gates=16'hff80;frames(20);
        if(active!=16'hff80)$fatal(1,"Nine independent high voices not active");
        for(j=0;j<9;j=j+1)if(dut.contexts[(j+7)*16+3]!=32768 || dut.contexts[(j+7)*16+2][2:0]!=3)$fatal(1,"Independent ADSR sustain %0d",j);
        for(i=0;i<4096;i=i+1)begin frames(1);samples[i]=$signed(pcm);end
        for(j=0;j<9;j=j+1)begin
            co=0;si=0;weight=0;
            for(n=0;n<4096;n=n+1)begin window=0.5-0.5*$cos(6.283185307179586*n/4095.0);weight=weight+window;angle=6.283185307179586*step(j)*n/4294967296.0;co=co+window*samples[n]*$cos(angle);si=si+window*samples[n]*$sin(angle);end
            amp=2*$sqrt(co*co+si*si)/weight;
            if(amp<470 || amp>550)$fatal(1,"Missing / wrong independent G4..F5 voice %0d amplitude %f",j,amp);
        end
        cfg={16'd1,16'd1,16'd1000,16'd1};frames(2);
        if(dut.contexts[115]!=32768)$fatal(1,"Changed a held profile");
        gates=16'h8000;frames(15);if(active!=16'h8000)$fatal(1,"Independent note-off failed");
        ratio=32768;frames(3);before_phase={dut.contexts[241],dut.contexts[240]};
        frames(1);after_phase={dut.contexts[241],dut.contexts[240]};
        if(after_phase-before_phase!=(step(8)>>1))$fatal(1,"Pressure pitch reset phase or wrong ratio");
        gates=0;frames(15);if(active || pcm)$fatal(1,"Release did not silence");
        gates=16'h0080;frames(5);if(dut.contexts[115]!=1000)$fatal(1,"New note did not snapshot new ADSR");
        $display("PASS touch TDM: 16 chromatic/pedal phase increments x32 frames (zero error), 4096-sample spectrum G4..F5, independent ADSR/profile snapshots/releases, smooth shared pitch, deadline");$finish;
    end
    initial begin #150000000;$fatal(1,"Extended touch timeout");end
endmodule
