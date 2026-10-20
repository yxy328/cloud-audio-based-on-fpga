`timescale 1ns/1ps
module tb_tdm_geometry_equivalence #(parameter PRESET=0);
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,sample_ce=0,event_valid=0,chord_valid=0,test_valid=0,vibrato_enabled=0;
    reg [31:0] event_inc=23012828;
    reg [2:0] event_timbre=0;
    reg [16:0] event_frames=80;
    reg [129:0] event_adsr={1'b1,16'd5,16'd11,16'd13,9'd170,24'd3355443,24'd1525201,24'd1290555};
    function [16:0] preset_frames;
        input [2:0] timbre;
        begin case(timbre)
            1,5:preset_frames=58594;2,7:preset_frames=24414;
            3,6:preset_frames=34180;4:preset_frames=19531;
            default:preset_frames=14648;
        endcase end
    endfunction
    wire [16:0] incoming_frames=PRESET ? preset_frames(event_timbre) : event_frames;
    wire signed [15:0] sample,reference_sample;
    wire [31:0] voice_active,reference_active;
    wire [5:0] voice_count,reference_count;
    wire busy,reference_busy,overrun,reference_overrun,event_ready;
    tdm_synth #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1),.PRESET_FRAMES(PRESET)) dut(.event_frames(incoming_frames),.*);
    tdm_synth_parallel_reference #(.RUNTIME_ADSR(1),.EXTENDED_TIMBRES(1)) reference(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.event_valid(event_valid),.chord_valid(chord_valid),
        .test_valid(test_valid),.vibrato_enabled(vibrato_enabled),.event_inc(event_inc),.event_timbre(event_timbre),
        .event_frames(incoming_frames),.event_adsr(event_adsr),.sample(reference_sample),.voice_active(reference_active),
        .voice_count(reference_count),.busy(reference_busy),.overrun(reference_overrun));
    integer frame=-1,n,cycles=0,checks=0,nonzero=0,max_cycles=0,voice,word;
    reg [575:0] actual_context;
    reg [555:0] expected_context;
    always @(posedge clk)if(resetn && frame>=0)begin
        if(sample_ce)cycles=0;
        else if(busy)begin cycles=cycles+1;if(cycles>max_cycles)max_cycles=cycles;end
        if(overrun || reference_overrun)$fatal(1,"Geometry deadline/FIFO overrun frame=%0d state=%0d",frame,dut.state);
    end
    task check_frame;
        begin
            if(busy || reference_busy)$fatal(1,"Unfinished 1024-clock frame %0d state=%0d",frame,dut.state);
            if(sample!==reference_sample || voice_active!==reference_active || voice_count!==reference_count)
                $fatal(1,"PCM/voice mismatch frame=%0d sample=%0d expected=%0d voices=%h expected=%h",frame,sample,reference_sample,voice_active,reference_active);
            for(voice=0;voice<32;voice=voice+1)begin
                for(word=0;word<16;word=word+1)actual_context[word*36 +:36]=dut.contexts[voice*16+word];
                expected_context={reference.contexts[voice*2+1],reference.contexts[voice*2]};
                if(actual_context[555:0]!==expected_context)$fatal(1,"Context mismatch frame=%0d voice=%0d actual=%h expected=%h",frame,voice,actual_context[555:0],expected_context);
                checks=checks+1;
            end
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);resetn=1;wait(!busy);@(negedge clk);
        for(n=0;n<64;n=n+1)begin event_valid=1;event_timbre=n%8;event_inc=23012828+n*983041;@(negedge clk);end
        event_valid=0;
        for(frame=0;frame<800;frame=frame+1)begin
            check_frame;
            sample_ce=1;@(negedge clk);sample_ce=0;
            for(n=1;n<1024;n=n+1)begin
                if(frame%9==0 && n>=100 && n<108)begin
                    event_valid=1;event_timbre=(n-100+frame)%8;event_inc=23012828+(frame%12)*983041;
                    event_frames=20+frame%70;event_adsr[129]=frame%3!=0;
                end else event_valid=0;
                test_valid=(frame==121 || frame==331) && n==450;
                chord_valid=frame%79==7 && n==700;
                if(frame%13==0 && n==300)vibrato_enabled=~vibrato_enabled;
                @(negedge clk);
            end
            if(sample!=0)nonzero=nonzero+1;
        end
        check_frame;
        if(nonzero<100)$fatal(1,"Insufficient audible coverage: %0d frames",nonzero);
        $display("PASS TDM narrow-context equivalence: %0d full voice-context checks, 800 real 1024-clock frames, all eight timbres, full FIFO/32 voices, runtime ADSR/vibrato; max busy=%0d clocks",checks,max_cycles);$finish;
    end
    initial begin #20000000;$fatal(1,"Harmonic equivalence timeout");end
endmodule
