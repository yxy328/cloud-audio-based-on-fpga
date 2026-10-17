`timescale 1ns/1ps
module tb_lissajous_reference;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0,restart=0,boundary=0;
    reg [1:0] ratio=2,phase=0;
    wire [5:0] rx;
    wire [4:0] ry;
    reg [5:0] px=0;
    reg [4:0] py=0;
    wire [14:0] upper,lower;
    integer r,p,n,fx,fy,hits,dx,dy,rad;
    real ex,ey,err,max_error=0;
    lissajous_reference ref_dut(.clk(clk),.resetn(resetn),.restart(restart),.sample_ce(ce),
        .ratio(ratio),.phase(phase),.x(rx),.y(ry));
    audio_visualizer picture(.clk(clk),.resetn(resetn),.sample_ce(ce),.display_boundary(boundary),
        .service_ce(1'b1),.visual_mode(2'd2),.reference_ratio(ratio),.reference_phase(phase),
        .mixed_sample(16'sd0),.touch0(16'sd0),.touch1(16'sd0),.sensor_sample(16'sd0),.guitar_sample(16'sd0),
        .pixel_x(px),.pixel_row(py),.upper_rgb(upper),.lower_rgb(lower));
    task tick;
        begin @(negedge clk);ce=1;@(negedge clk);ce=0;repeat(6)@(negedge clk);end
    endtask
    task publish;
        begin wait(picture.capture_ready);@(negedge clk);boundary=1;
            @(negedge clk);boundary=0;wait(!picture.clearing);end
    endtask
    task pixel;
        input integer x,y;
        begin px=x;py=y;repeat(2)@(negedge clk);end
    endtask
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        // Independent real-valued sine oracle for every integer ratio/phase,
        // including complete-turn closure, sign and equal physical axis scale.
        for(r=1;r<=3;r=r+1) for(p=0;p<4;p=p+1) begin
            ratio=r;phase=p;restart=1;@(negedge clk);restart=0;
            fx=r==3 ? 2 : 1;fy=r==2 ? 2 : r==3 ? 3 : 1;
            for(n=0;n<256;n=n+1) begin
                ex=32+14*$sin(6.283185307179586*fx*n/256.0);
                ey=16-14*$sin(6.283185307179586*(fy*n/256.0+p/8.0));
                err=$itor(rx)-ex;if(err<0)err=-err;if(err>max_error)max_error=err;
                if(err>0.501)$fatal(1,"X sine error r=%0d p=%0d n=%0d actual=%0d expected=%f",r,p,n,rx,ex);
                err=$itor(ry)-ey;if(err<0)err=-err;if(err>max_error)max_error=err;
                if(err>0.501)$fatal(1,"Y sine error r=%0d p=%0d n=%0d actual=%0d expected=%f",r,p,n,ry,ey);
                if(rx<18 || rx>46 || ry<2 || ry>30)$fatal(1,"Point escaped plot");
                tick;
            end
            if(rx!=32)$fatal(1,"Curve failed to close");
        end
        // Fresh reset for bitmap checks. Initial live silence bank is harmless.
        resetn=0;repeat(3)@(negedge clk);resetn=1;ratio=2;phase=0;
        wait(!picture.clearing);repeat(512)tick;publish;
        if(picture.capture_ratio!=2 || picture.shown_ratio!=0)$fatal(1,"Capture configuration did not latch");
        repeat(100)tick;ratio=1;phase=2;
        if(picture.capture_ratio!=2)$fatal(1,"Mid-frame setting tore the capture");
        repeat(412)tick;publish;
        if(picture.shown_ratio!=2 || picture.shown_phase!=0)$fatal(1,"Published wrong configuration");
        pixel(32,16);if(upper!={5'd24,5'd4,5'd31})$fatal(1,"Eight lost its crossing");
        // Next whole frame is a circle. Validate every lit point geometrically.
        repeat(512)tick;publish;
        if(picture.shown_ratio!=1 || picture.shown_phase!=2)$fatal(1,"Circle setting missing");
        hits=0;
        for(dy=0;dy<32;dy=dy+1)for(dx=0;dx<64;dx=dx+1)begin
            pixel(dx,dy);
            if(upper=={5'd24,5'd4,5'd31})begin
                hits=hits+1;rad=(dx-32)*(dx-32)+(dy-16)*(dy-16);
                if(rad<150 || rad>240)$fatal(1,"Circle bitmap radius incorrect at %0d,%0d",dx,dy);
            end
        end
        if(hits<45)$fatal(1,"Circle has insufficient points");
        pixel(32,16);if(upper=={5'd24,5'd4,5'd31})$fatal(1,"Old eight crossing survived circle clear");
        pixel(4,0);if(lower!={5'd18,5'd18,5'd18})$fatal(1,"Reference label missing");
        $display("PASS reference XY: 12 ratio/phase combinations, 3072 sine points, max error %f pixels, atomic capture/publish, eight crossing, circle geometry/clear and REF label",max_error);
        $finish;
    end
    initial begin #20000000;$fatal(1,"Reference timeout");end
endmodule
