`timescale 1ns/1ps
// The older take-only reference has a different startup schedule; freeze the pre-parameterization production engine instead.
module tb_tdm_take_equivalence;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [9:0] divider=0;
    wire sample_ce=divider==1023;
    always @(posedge clk)if(!resetn)divider<=0;else divider<=divider+1'b1;
    reg event_valid=0,chord_valid=0,test_valid=0,vibrato_enabled=0;
    reg [31:0] event_inc=23012828;reg [2:0] event_timbre=0;
    reg [16:0] event_frames=200;
    reg [129:0] event_adsr={1'b1,16'd8,16'd16,16'd24,9'd170,24'd2097151,24'd1048575,24'd699050};
    wire [31:0] voice_active,reference_active;
    wire [5:0] voice_count,reference_count;
    wire signed [15:0] sample,reference_sample;
    wire overrun,busy,event_ready,reference_overrun,reference_busy,reference_ready;
    tdm_synth #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1),.CHORD_FRAMES(88),.TEST_FRAMES(130)) dut(.tuning_ratio(16'd16384),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),.*);
    tdm_synth_fixed_reference #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1),.CHORD_FRAMES(88),.TEST_FRAMES(130)) reference(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.event_valid(event_valid),.chord_valid(chord_valid),
        .test_valid(test_valid),.vibrato_enabled(vibrato_enabled),.event_inc(event_inc),.event_timbre(event_timbre),
        .event_frames(event_frames),.event_adsr(event_adsr),.voice_active(reference_active),.voice_count(reference_count),
        .sample(reference_sample),.overrun(reference_overrun),.busy(reference_busy),.event_ready(reference_ready));
    integer cycles=0,frames=0,nonzero=0,peak=0,f,j;
    always @(negedge clk)if(resetn)begin
        cycles=cycles+1;
        if({sample,voice_active,voice_count,overrun,busy,event_ready}!==
           {reference_sample,reference_active,reference_count,reference_overrun,reference_busy,reference_ready})
            $fatal(1,"TDM mismatch frame=%0d cycle=%0d sample=%0d reference=%0d",frames,cycles,sample,reference_sample);
        if((^sample)===1'bx || overrun)$fatal(1,"Unknown audio or missed frame");
        if(sample_ce)begin
            frames=frames+1;if(sample!=0)nonzero=nonzero+1;
            if(voice_count>peak)peak=voice_count;
        end
    end
    initial begin
        repeat(5)@(negedge clk);resetn=1;repeat(100)@(negedge clk);
        for(f=0;f<1536;f=f+1)begin
            wait(sample_ce);@(negedge clk);repeat(8)@(negedge clk);
            if(f<32 || (f<600 && f%13==0))begin
                for(j=0;j<(f<32 ? 2 : 5);j=j+1)begin
                    event_inc=32'd23012828+32'd1048576*((f+j)%32);event_timbre=(f+j)%8;
                    event_frames=150+(f%40);event_valid=1;@(negedge clk);event_valid=0;@(negedge clk);
                end
            end
            if(f==80 || f==300)begin chord_valid=1;@(negedge clk);chord_valid=0;end
            if(f==120 || f==450)begin test_valid=1;@(negedge clk);test_valid=0;end
            if(f%71==0)vibrato_enabled=!vibrato_enabled;
            if(f==700)begin
                resetn=0;repeat(5)@(negedge clk);resetn=1;repeat(100)@(negedge clk);
            end
        end
        if(nonzero<400 || peak!=32 || voice_count!=0)$fatal(1,"Insufficient audio/stealing/tail coverage");
        $display("PASS tb_tdm_take_equivalence: %0d cycles, %0d frames, %0d nonzero, peak %0d voices; all eight timbres",cycles,frames,nonzero,peak);$finish;
    end
    initial begin #50000000;$fatal(1,"Equivalence timeout");end
endmodule
