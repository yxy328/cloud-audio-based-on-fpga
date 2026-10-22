`timescale 1ns/1ps
module tb_audio_scope;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0,boundary=0,service=1;
    reg signed [15:0] pcm=0;
    reg [15:0] fsr=65535;
    reg [5:0] x=0;reg [4:0] y=0;
    wire [14:0] upper,lower;
    integer n,g,expected,preview,py,p,samples=0;
    reg [14:0] pixels[0:4095];
    audio_visualizer dut(.clk(clk),.resetn(resetn),.sample_ce(ce),.display_boundary(boundary),
        .service_ce(service),.style_ce(service),.visual_mode(2'd1),.scope_fsr_gain(fsr),
        .reference_ratio(2'd2),.reference_phase(2'd0),.mixed_sample(pcm),
        .touch0(pcm),.touch1(16'sd0),.sensor_sample(16'sd0),.guitar_sample(16'sd0),
        .pixel_x(x),.pixel_row(y),.upper_rgb(upper),.lower_rgb(lower));
    task sample;
        input signed [15:0] value;
        begin @(negedge clk);pcm=value;ce=1;@(negedge clk);ce=0;repeat(14)@(negedge clk);end
    endtask
    task publish;
        begin
            wait(dut.capture_ready);repeat(16)@(negedge clk);
            boundary=1;@(negedge clk);boundary=0;wait(!dut.clearing);
        end
    endtask
    task window;
        input integer amplitude;
        begin
            for(n=0;n<512;n=n+1)begin
                sample($rtoi(amplitude*$sin(6.283185307179586*n/192.0)));
                if(n<511 && dut.capture_full)$fatal(1,"Early capture truncates the time axis");
            end
            publish;
        end
    endtask
    task save;
        input [511:0] filename;
        begin
            service=0;
            for(py=0;py<32;py=py+1)for(p=0;p<64;p=p+1)begin
                @(negedge clk);x=p;y=py;repeat(3)@(negedge clk);
                pixels[py*64+p]=upper;pixels[(py+32)*64+p]=lower;
            end
            service=1;
            preview=$fopen(filename,"w");if(!preview)$fatal(1,"Cannot save scope image");
            $fdisplay(preview,"P3\n64 64\n31");
            for(p=0;p<4096;p=p+1)$fdisplay(preview,"%0d %0d %0d",pixels[p][14:10],pixels[p][9:5],pixels[p][4:0]);
            $fclose(preview);
        end
    endtask
    initial begin
        // Every signed coordinate that fits each of the six scales, independently
        // checked using mathematical floor division rather than signed shifts.
        for(g=0;g<6;g=g+1)begin
            force dut.shown_range=g;
            for(n=-(512>>g);n<(512>>g);n=n+1)begin
                force dut.display_data={n[9:0],n[9:0]};#1;
                expected=27-(n>=0 ? n/(32>>g) : -((-n+(32>>g)-1)/(32>>g)));
                if(dut.u_scope.top_y!==expected[6:0] || dut.u_scope.bottom_y!==expected[6:0])
                    $fatal(1,"Signed scope mapping range=%0d sample=%0d",g,n);
            end
        end
        release dut.display_data;release dut.shown_range;
        // Exhaust the conservative peak/range selector, including equality
        // at each widening threshold and silence, against min(fit, FSR).
        for(g=0;g<3;g=g+1)begin
            force dut.capture_range=g;
            for(n=0;n<=128;n=n+1)begin
                force dut.capture_peak=n;#1;
                expected=n>64 ? 0 : n>32 ? 1 : n>16 ? 2 : n>8 ? 3 : n>4 ? 4 : 5;
                if(expected>g+3)expected=g+3;
                if(dut.safe_range!==expected[2:0])$fatal(1,"FSR range mismatch at peak=%0d FSR=%0d",n,g);
            end
        end
        release dut.capture_range;release dut.capture_peak;
        for(n=-32768;n<32768;n=n+1)begin
            pcm=n;#1;expected=((n<0 ? -n : n)+255)/256;
            if(dut.sample_magnitude!==expected[7:0])$fatal(1,"Conservative peak code PCM=%0d",n);
        end
        pcm=0;
        repeat(4)@(negedge clk);resetn=1;wait(!dut.clearing);
        window(2048);
        if(dut.shown_range!=3 || dut.u_scope.peak_bcd!=12'h006)
            $fatal(1,"Unity range/percent incorrect: %h",dut.u_scope.peak_bcd);
        if(dut.u_scope.shown_color!={5'd31,5'd0,5'd0})$fatal(1,"Nominal loud palette");
        save("sim/build/scope_fsr100.ppm");
        fsr=32768;window(1024);window(1024);
        if(dut.shown_range!=4 || dut.u_scope.peak_bcd!=12'h003)
            $fatal(1,"FSR half-scale failed");
        if(dut.u_scope.shown_color!={5'd16,5'd0,5'd31})$fatal(1,"Nominal medium palette");
        save("sim/build/scope_fsr50.ppm");
        fsr=16384;window(512);window(512);
        if(dut.shown_range!=5 || dut.u_scope.peak_bcd!=12'h001)
            $fatal(1,"FSR quarter-scale failed");
        if(dut.u_scope.shown_color!={5'd0,5'd0,5'd31})$fatal(1,"Realistic weak signal must be saturated blue");
        save("sim/build/scope_fsr25.ppm");
        // The photographed ~2% signal now occupies 16 vertical intervals
        // at x32 instead of one interval, with the raw PK still at 2%.
        if(pixels[19*64+20]!=={5'd0,5'd0,5'd31})$fatal(1,"512-count wave is still too small");
        window(128);save("sim/build/scope_weak128.ppm");
        if(dut.u_scope.shown_color!={5'd0,5'd0,5'd24})$fatal(1,"Sub-percent signal is white");
        // FSR gain is unchanged while an unrelated source becomes loud.
        // Range widens at publication using the captured raw extrema.
        for(n=0;n<511;n=n+1)sample(-32768);
        if(dut.shown_range!=5 || dut.u_scope.peak_bcd!=12'h000)$fatal(1,"Scope metadata changed mid-frame");
        sample(-32768);publish;
        if(dut.shown_range!=0 || dut.u_scope.peak_bcd!=12'h100)
            $fatal(1,"Mixed source overflow did not widen range atomically");
        if(dut.u_scope.shown_color!={5'd31,5'd0,5'd0})$fatal(1,"Full scale palette");
        save("sim/build/scope_overrange.ppm");
        window(0);
        if(dut.u_scope.shown_color!={5'd8,5'd8,5'd8} || dut.u_scope.shown_level || dut.u_scope.peak_bcd)
            $fatal(1,"Silence is not a quiet white zero line");
        save("sim/build/scope_silence.ppm");
        // Hysteresis: hovering just above 25% must not alternate x2/x4.
        fsr=17000;window(512);window(512);
        if(dut.capture_range!=2)$fatal(1,"FSR range chatters at 25 percent");
        fsr=18000;window(512);window(512);
        if(dut.shown_range!=4)$fatal(1,"FSR hysteresis never releases");
        fsr=65535;window(512);window(512);
        if(dut.shown_range!=3 || dut.u_scope.shown_color!={5'd0,5'd0,5'd31} || dut.u_scope.peak_bcd!=12'h001)
            $fatal(1,"Same PCM changed color/peak when the FSR range changed");
        // Cover each widening threshold without clipping or changing FSR.
        fsr=16384;window(512);window(512);
        for(g=0;g<6;g=g+1)begin
            window(32768>>g);
            if(dut.shown_range!=g)$fatal(1,"Automatic range protection failed at %0d",g);
        end
        $display("PASS scope: 65536 magnitudes, 2016 signed mappings, 387 peak/FSR selections, real 128/512/1024/2048-count signals, x8/x16/x32 FSR, saturated colors independent of range, six overflow ranges, atomic metadata, hysteresis and six pixel exports");
        $finish;
    end
    initial begin #10000000;$fatal(1,"Scope timeout");end
endmodule
