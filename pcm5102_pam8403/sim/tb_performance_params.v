`timescale 1ns/1ps
module tb_performance_params;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,sample_ce=0,bend_write=0,bend_reset=0;
    reg [2:0] bend_index=0;
    reg [15:0] pitch_ratio=65535,bend_ratio=16384;
    reg [15:0] bend_min=8192,bend_max=32768,bend_slew=4096;
    localparam [223:0] note_increments={32'd43442435,32'd38702809,32'd34480283,
        32'd30718440,32'd28994347,32'd25831026,32'd23012828};
    wire [255:0] phase_increments,expected;
    reg compare_default=1;
    integer i,frames,qstep,target,elapsed,ideal,expected_current;
    reg [47:0] expected_product;
    voice_pitch_scaler dut(.score_ratio(16'd0),.score_keys(7'd0),.note_increments(note_increments),.*);
    voice_pitch_scaler_reference reference(
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.pitch_ratio(pitch_ratio),
        .bend_write(bend_write),.bend_reset(bend_reset),.bend_index(bend_index),
        .bend_ratio(bend_ratio),.note_increments(note_increments),.phase_increments(expected));
    always @(posedge clk)begin
        #1;if(resetn && compare_default && phase_increments!==expected)
            $fatal(1,"Default phase increments differ from frozen RTL");
    end
    task frame;
        begin sample_ce=1;@(negedge clk);sample_ce=0;repeat(55)@(negedge clk);end
    endtask
    task restart;
        begin resetn=0;repeat(4)@(negedge clk);resetn=1;repeat(12)@(negedge clk);end
    endtask
    task glide;
        input integer ms;
        begin
            restart;
            target=18390;
            ideal=(ms*50000+512)/1024;
            qstep=((target-16384)*256+ideal/2)/ideal;
            bend_slew=qstep;bend_ratio=target;bend_index=0;bend_write=1;
            @(negedge clk);bend_write=0;
            frames=((target-16384)*256+qstep-1)/qstep;
            for(elapsed=1;elapsed<=frames;elapsed=elapsed+1)begin
                frame;
                expected_current=16384+(elapsed*qstep)/256;
                if(expected_current>target)expected_current=target;
                expected_product=32'd23012828*expected_current;
                if(phase_increments[31:0]!==expected_product[45:14])
                    $fatal(1,"Fractional glide ms=%0d frame=%0d",ms,elapsed);
            end
            if(frames*1024<ms*49000 || frames*1024>ms*51000)
                $fatal(1,"Glide quantization exceeds 2 percent for +200 cents");
            $display("+200 cents: requested=%0dms actual=%0.5fms frames=%0d stepQ8.8=%0d",
                ms,frames*0.02048,frames,qstep);
        end
    endtask
    initial begin
        restart;
        for(i=0;i<2100;i=i+1)begin
            bend_write=i%37==0;bend_index=i%7;
            bend_ratio=(i%3==0) ? 8192 : (i%3==1) ? 32768 : 16384;
            if(i%53==0)pitch_ratio=65535-i;
            frame;
        end
        compare_default=0;bend_write=0;pitch_ratio=65535;
        glide(5);glide(60);glide(200);glide(500);
        bend_min=15918;bend_max=16864;frame;
        expected_product=32'd23012828*16864;
        if(phase_increments[31:0]!==expected_product[45:14])$fatal(1,"New bounds not applied");
        $display("PASS performance parameters: every-clock frozen default comparison, fractional 5/60/200/500ms glide, new bounds");
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Performance parameter timeout");end
endmodule
