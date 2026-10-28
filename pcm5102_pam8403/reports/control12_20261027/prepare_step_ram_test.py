from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
old=(P/'sim/build/unified/control12_shared_reply/pcm5102_pam8403/src/touch_tdm_synth.v').read_text(encoding='utf-8').replace('module touch_tdm_synth #(', 'module touch_control12_step_reference #(')
bench=r'''`timescale 1ns/1ps
module tb_control12_step_ram;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [9:0] divider=0;
    wire ce=divider==0;
    always @(posedge clk)divider<=divider+1'b1;
    reg [15:0] gates=0,physical=0;
    reg [1:0] pedal=0;reg [4:0] poly=16;
    reg [63:0] cfg={16'd1,16'd1,16'd32768,16'd1};
    reg [15:0] ratio=65535;
    reg [383:0] live_steps=0,replay_steps=0;
    reg replay=0,legacy=0;
    wire signed [15:0] pcm,ref_pcm;
    wire [15:0] active,ref_active;
    wire [4:0] count,ref_count;
    wire clipped,ref_clipped,overrun,ref_overrun;
    integer i,n,frame=0,cycle=0,checks=0,max_busy=0,busy_cycles=0;
    touch_tdm_synth #(.CONTROL_KEYS(12),.RAM_STEPS(1),.FAST_READ(1),.EXTENDED_CONTROL(1)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.gates(gates),.physical_gates(physical),
        .pedal_mode(pedal),.poly_limit(poly),.low_steps(live_steps),.replay_steps(replay_steps),
        .replay_select(replay),.legacy_high_keys(legacy),.adsr_config(cfg),.pitch_ratio(ratio),
        .sample(pcm),.active(active),.voice_count(count),.clipped(clipped),.overrun(overrun));
    touch_control12_step_reference #(.CONTROL_KEYS(12),.FAST_READ(1),.EXTENDED_CONTROL(1)) reference(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.gates(gates),.physical_gates(physical),
        .pedal_mode(pedal),.poly_limit(poly),.low_steps(replay ? replay_steps : live_steps),
        .legacy_high_keys(legacy),.adsr_config(cfg),.pitch_ratio(ratio),
        .sample(ref_pcm),.active(ref_active),.voice_count(ref_count),.clipped(ref_clipped),.overrun(ref_overrun));
    always @(negedge clk)if(resetn)begin
        if(ce)begin
            frame=frame+1;cycle=0;
            if(frame>3)begin
                if(overrun || ref_overrun)$fatal(1,"Frame deadline exceeded");
                if({pcm,active,count,clipped}!=={ref_pcm,ref_active,ref_count,ref_clipped})
                    $fatal(1,"Frame %0d differs PCM %0d/%0d active %h/%h count %0d/%0d",frame,pcm,ref_pcm,active,ref_active,count,ref_count);
                if(dut.phases!==reference.phases || dut.gains!==reference.gains || dut.states!==reference.states)
                    $fatal(1,"Frame %0d differs in DDS phase/envelope",frame);
                for(i=0;i<16;i=i+1)begin
                    if({dut.contexts[i*32+14],dut.contexts[i*32+13]}!=={reference.contexts[i*16+14],reference.contexts[i*16+13]})
                        $fatal(1,"Age mismatch frame %0d voice %0d",frame,i);
                end
                checks=checks+1;
            end
        end else cycle=cycle+1;
        // Model the real pitch scaler: updates 6 cycles apart, beginning
        // after cycle 6. Each old 32-bit word must be captured beforehand.
        if(cycle>=6 && cycle<78 && ((cycle-6)%6)==0)
            live_steps[((cycle-6)/6)*32 +: 32]=32'h1020304*(frame+1)+((cycle-6)/6)*32'h1001001;
        // TAKE changes fields only after its frame guard. Deliberately
        // change the two halves on separate clocks to expose torn reads.
        if(cycle>=34 && cycle<58)
            replay_steps[(cycle-34)*16 +: 16]=16'h2101*frame+cycle;
        if(dut.state!=1 && dut.state!=0)busy_cycles=busy_cycles+1;
        else begin if(busy_cycles>max_busy)max_busy=busy_cycles;busy_cycles=0;end
    end
    task frames;input integer amount;integer end_frame;begin end_frame=frame+amount;wait(frame>=end_frame);@(negedge clk);end endtask
    initial begin
        for(n=0;n<12;n=n+1)begin live_steps[n*32+:32]=23012828+n*1000000;replay_steps[n*32+:32]=45000000+n*2000000;end
        repeat(5)@(negedge clk);resetn=1;frames(4);
        // Simultaneous starts/attack->decay/release exercise all 16 dividers.
        gates=16'hffff;physical=gates;frames(20);gates=0;physical=0;frames(12);
        replay=1;gates=16'hffff;physical=gates;ratio=32768;frames(20);
        legacy=1;frames(12);legacy=0;ratio=65535;frames(12);
        // Pedal tails, poly stealing and ages must remain bit-identical.
        replay=0;pedal=2;poly=8;cfg={16'd3,16'd2,16'd50000,16'd5};frames(5);
        physical=0;gates=0;frames(40);gates=16'h00ff;physical=gates;frames(10);
        physical=0;gates=0;frames(40);pedal=0;frames(20);
        if(checks<180 || max_busy>1023)$fatal(1,"Insufficient stress checks or deadline");
        $display("PASS control12 step RAM: %0d bit-exact frames, live scanner/replay half-word races, 16 DDS phases/ADSR/age/poly/tails/legacy fallback, PCM; worst busy %0d/1024 clocks",checks,max_busy);$finish;
    end
    initial begin #10000000;$fatal(1,"Step RAM test timeout");end
endmodule
'''
(P/'sim/tb_control12_step_ram.v').write_text(bench+'\n// Frozen shared_reply source for a frame-by-frame independent comparison.\n'+old,encoding='utf-8')
print('Prepared independent frame equivalence and race/deadline test')
