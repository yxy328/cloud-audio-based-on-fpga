`timescale 1ns/1ps
module tb_runtime_adsr;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,req=0,restore=0,profile=0;
    reg [15:0] a=0,d=0,s=0,r=0;
    wire done;
    wire [63:0] tc;
    wire [129:0] sc;
    adsr_config cfg(.clk(clk),.resetn(resetn),.request(req),.restore(restore),.profile(profile),
        .attack_ms(a),.decay_ms(d),.sustain_percent(s),.release_ms(r),
        .done(done),.touch_config(tc),.sensor_config(sc));
    reg gate=0,ce=0;
    reg [63:0] live={16'd8,16'd4,16'd32768,16'd16};
    wire [15:0] gain;
    wire [2:0] state;
    adsr_env #(.RUNTIME_ADSR(1)) env(.clk(clk),.resetn(resetn),.sample_ce(ce),.gate(gate),
        .adsr_config(live),.gain(gain),.state(state),.active());
    integer i,ticks,level;
    reg [129:0] before_sensor;
    task update;
        begin @(negedge clk);req=1;@(negedge clk);req=0;wait(done);@(negedge clk);end
    endtask
    task tick;
        begin @(negedge clk);ce=1;@(negedge clk);ce=0;repeat(20) @(negedge clk);end
    endtask
    task gate_to;
        input value;begin @(negedge clk);gate=value;repeat(20) @(negedge clk);end
    endtask
    initial begin
        repeat(4) @(negedge clk);resetn=1;
        if(tc!=={16'd98,16'd3906,16'd39321,16'd488} || sc!==0) $fatal(1,"Profile reset");
        profile=1;
        for(i=0;i<=1000;i=i+1) begin
            a=i;d=i;r=i;s=i%101;before_sensor=sc;update;
            ticks=(i*3125+32)/64;if(ticks==0)ticks=1;
            level=(s*65535)/100;
            if(sc[128:113]!=ticks || sc[112:97]!=ticks || sc[96:81]!=ticks ||
                sc[80:72]!=((level+128)>>8) || !sc[129]) $fatal(1,"Sensor conversion ms=%0d",i);
            if(sc[71:48]!==((ticks==1)?24'hffffff:16777216/ticks)) $fatal(1,"Reciprocal coefficient %0d",i);
        end
        restore=1;update;if(sc!==0) $fatal(1,"Sensor restore");restore=0;
        profile=0;a=2;d=80;s=60;r=10;update;
        if(tc!=={16'd98,16'd3906,16'd39321,16'd488}) $fatal(1,"Touch ms conversion");
        gate_to(1);
        for(i=1;i<=4;i=i+1) begin tick;if(gain!=(65535*i)/8) $fatal(1,"Touch attack %0d",i);end
        live={16'd1,16'd1,16'd0,16'd1};
        for(i=5;i<=8;i=i+1) begin tick;if(gain!=(65535*i)/8) $fatal(1,"Live config changed held attack");end
        for(i=1;i<=4;i=i+1) begin tick;if(gain!=65535-(32767*i)/4) $fatal(1,"Held decay changed");end
        if(state!=3 || gain!=32768) $fatal(1,"Sustain snapshot");
        gate_to(0);for(i=1;i<=16;i=i+1) begin tick;if(gain!=32768-(32768*i)/16) $fatal(1,"Release snapshot");end
        gate_to(1);tick;if(gain!=65535) $fatal(1,"New note ignored new A");
        tick;if(gain!=0 || state!=3) $fatal(1,"New S=0");gate_to(0);
        live={16'd8,16'd4,16'd32768,16'd16};gate_to(1);tick;tick;level=gain;gate_to(0);
        for(i=1;i<=16;i=i+1) begin tick;if(gain!=level-(level*i)/16) $fatal(1,"Early note off R slope");end
        $display("PASS runtime ADSR: all 1001 ms values, sustain mapping, profile reset/conversion, exact touch A/D/S/R, held snapshot/new note, mid-attack release");$finish;
    end
    initial begin #10000000;$fatal(1,"Runtime config timeout");end
endmodule
