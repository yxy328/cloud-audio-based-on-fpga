`timescale 1ns/1ps
module tb_audio_visualizer;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0, ce=0, boundary=0, service=1;
    reg signed [15:0] mixed=0,touch0=0,touch1=0,sensor=0,guitar=0;
    reg [5:0] x=0;
    reg [4:0] y=0;
    reg [1:0] mode=1;
    wire [14:0] upper,lower;
    integer n,col,phase,expected_min,expected_max;
    integer fft_frames=0,first_fft;
    always @(posedge clk) if(dut.spectrum_done) fft_frames=fft_frames+1;
    audio_visualizer dut (.clk(clk),.resetn(resetn),.sample_ce(ce),.display_boundary(boundary),
        .service_ce(service),.style_ce(service),.visual_mode(mode),.scope_fsr_gain(16'hffff),
        .reference_ratio(2'd0),.reference_phase(2'd0),
        .mixed_sample(mixed),.touch0(touch0),.touch1(touch1),.sensor_sample(sensor),.guitar_sample(guitar),
        .pixel_x(x),.pixel_row(y),.upper_rgb(upper),.lower_rgb(lower));
    task sample;
        input signed [15:0] value;
        begin @(negedge clk); mixed=value; ce=1;
            @(negedge clk); ce=0; repeat(6) @(negedge clk); end
    endtask
    task swap;
        begin @(negedge clk); boundary=1;
            @(negedge clk); boundary=0;
            repeat(2) @(negedge clk); wait(!dut.clearing); end
    endtask
    task pixel;
        input [5:0] px; input [4:0] py;
        input [14:0] expected_upper,expected_lower;
        begin @(negedge clk); service=0;x=px; y=py;
            repeat(2) @(negedge clk);
            if(upper!==expected_upper || lower!==expected_lower)
                $fatal(1,"Pixel %0d,%0d RGB=%h/%h expected %h/%h word=%h top=%0d bottom=%0d",px,py,upper,lower,expected_upper,expected_lower,dut.display_data,dut.u_scope.top_y,dut.u_scope.bottom_y);
            service=1;
        end
    endtask
    initial begin
        // Check coordinate quantization at every signed PCM value, including
        // negative fractions and both clamp boundaries, against floor division.
        for(n=-32768;n<32768;n=n+1) begin
            mixed=n; #1;
            expected_min=n>7680 ? 1 : n< -7680 ? 31 :
                16-(n>=0 ? n/512 : -((-n+511)/512));
            expected_max=n>7680 ? 62 : n< -7680 ? 2 :
                32+(n>=0 ? n/256 : -((-n+255)/256));
            if(dut.sample_y!==expected_min[4:0] || dut.sample_x!==expected_max[5:0])
                $fatal(1,"PCM %0d coordinate mismatch: %0d,%0d expected %0d,%0d",
                    n,dut.sample_x,dut.sample_y,expected_max,expected_min);
        end
        mixed=0;
        repeat(3) @(negedge clk); resetn=1;
        wait(!dut.clearing);
        pixel(8,8,0,0); // Uninitialized RAM must be hidden.
        // All 512 samples are retained in 48 bins: 11,11,10 repeated.
        // Asymmetric first/last extrema and connected preceding endpoints.
        touch0=-32768; touch1=-32768; sensor=-32768; guitar=1280;
        for(col=0;col<48;col=col+1) begin
            for(phase=0;phase<(col%3==2 ? 10 : 11);phase=phase+1) begin
                if(phase==0) sample(col[0] ? 16'sd32767 : 16'sd1024);
                else if(phase==(col%3==2 ? 9 : 10)) sample(col[0] ? -16'sd32768 : -16'sd1536);
                else sample(0);
            end
        end
        if(!dut.capture_ready || dut.display_valid) $fatal(1,"Incomplete bank was exposed");
        repeat(20) sample(0);
        swap;
        if(!dut.display_valid) $fatal(1,"Complete capture did not publish");
        for(col=0;col<48;col=col+1) begin
            x=col+16; repeat(2) @(negedge clk);
            expected_max=col[0] ? 511 : 16;
            expected_min=col==0 ? -24 : -512;
            if(dut.display_range!=={expected_max[9:0],expected_min[9:0]})
                $fatal(1,"Column %0d lost extrema: %h",col,dut.display_range);
        end
        pixel(17,12,{5'd31,5'd3,5'd3},0);
        pixel(16,26,0,{5'd11,5'd15,5'd14});
        pixel(16,27,{5'd31,5'd3,5'd3},{5'd11,5'd15,5'd14});
        mode=2;
        pixel(36,1,{5'd24,5'd4,5'd31},0);
        pixel(35,1,0,0);
        pixel(62,14,{5'd24,5'd4,5'd31},0);
        mode=1;
        // Back bank acquisition cannot alter the current front bank.
        touch0=0; touch1=0; sensor=0; guitar=0;
        for(n=0;n<512;n=n+1) sample(0);
        pixel(17,12,{5'd31,5'd3,5'd3},0);
        swap;
        pixel(17,12,0,0);
        pixel(17,27,{5'd8,5'd8,5'd8},0);
        // The three source meters still decay with their original scale.
        for(n=0;n<56*512;n=n+1) sample(0);
        swap;
        if(dut.shown_touch || dut.shown_sensor || dut.shown_guitar)
            $fatal(1,"Silence left a stuck amplitude bar");
        // Real sine samples feed the CIC/window/FFT; inspect its published
        // bar pixels, including a gap and an unrelated low-frequency band.
        first_fft=fft_frames;n=0;
        while(fft_frames<first_fft+3) begin
            sample($rtoi(12000.0*$sin(6.283185307179586*11*n/2048.0)));n=n+1;
            if(n>20000)$fatal(1,"Spectrum did not finish its windows");
        end
        swap;mode=3;
        pixel(16,30,{5'd0,5'd28,5'd6},0);
        pixel(19,30,0,0);
        pixel(0,20,0,0);
        $display("PASS audio visualizer: 65536 signed PCM coordinates, 48-bin whole-window extrema/buffering, signed peaks/decay, delayed-audio XY bitmap, real FFT bars/gaps/noise floor and pixel colors");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Visualizer timeout"); end
endmodule
