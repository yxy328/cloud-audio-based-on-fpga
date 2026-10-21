`timescale 1ns/1ps
module tb_tdm_harmonic_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,sample_ce=0,event_valid=0,chord_valid=0,test_valid=0,vibrato_enabled=0;
    reg [31:0] event_inc=23012828;
    reg [2:0] event_timbre=0;
    reg [16:0] event_frames=80;
    reg [129:0] event_adsr={1'b1,16'd5,16'd11,16'd13,9'd170,24'd3355443,24'd1525201,24'd1290555};
    wire signed [15:0] sample,reference_sample;
    wire [31:0] voice_active,reference_active;
    wire [5:0] voice_count,reference_count;
    wire busy,reference_busy,overrun,reference_overrun,event_ready;
    tdm_synth #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1)) dut(.tuning_ratio(16'd16384),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),.*);
    tdm_synth_parallel_reference #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1)) reference(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.event_valid(event_valid),.chord_valid(chord_valid),
        .test_valid(test_valid),.vibrato_enabled(vibrato_enabled),.event_inc(event_inc),.event_timbre(event_timbre),
        .event_frames(event_frames),.event_adsr(event_adsr),.sample(reference_sample),.voice_active(reference_active),
        .voice_count(reference_count),.busy(reference_busy),.overrun(reference_overrun));
    integer frame,n,cycles=0,checks=0,nonzero=0;
    always @(negedge clk)if(resetn)begin
        // The narrow RAM pipeline publishes earlier than the reference. Compare
        // observable audio at its 1024-clock consumer boundary, not mid-frame.
        if(overrun || reference_overrun)$fatal(1,"Harmonic deadline/FIFO overrun");
    end
    initial begin
        repeat(5)@(negedge clk);resetn=1;wait(!busy);@(negedge clk);
        for(n=0;n<64;n=n+1)begin event_valid=1;event_timbre=n%8;event_inc=23012828+n*983041;@(negedge clk);end
        event_valid=0;
        for(frame=0;frame<500;frame=frame+1)begin
            if(busy || reference_busy || sample!==reference_sample ||
               voice_active!==reference_active || voice_count!==reference_count)
                $fatal(1,"Harmonic frame-boundary mismatch frame=%0d PCM=%0d reference=%0d",frame,sample,reference_sample);
            checks=checks+1;
            sample_ce=1;@(negedge clk);sample_ce=0;
            for(n=1;n<1024;n=n+1)begin
                if(frame%9==0 && n>=100 && n<108)begin
                    event_valid=1;event_timbre=(n-100+frame)%8;event_inc=23012828+(frame%12)*983041;
                    event_frames=20+frame%70;event_adsr[129]=frame%3!=0;
                end else event_valid=0;
                if(frame%13==0 && n==300)vibrato_enabled=~vibrato_enabled;
                @(negedge clk);
            end
            if(sample!=0)nonzero=nonzero+1;
        end
        if(busy || reference_busy || sample!==reference_sample ||
           voice_active!==reference_active || voice_count!==reference_count)
            $fatal(1,"Final harmonic frame mismatch");
        if(nonzero<100)$fatal(1,"Insufficient audible coverage");
        $display("PASS TDM harmonic equivalence: %0d frame checks, 500 real 1024-clock frames, all eight timbres, full FIFO/32 voices, runtime ADSR and vibrato bit-exact",checks);$finish;
    end
    initial begin #20000000;$fatal(1,"Harmonic equivalence timeout");end
endmodule
