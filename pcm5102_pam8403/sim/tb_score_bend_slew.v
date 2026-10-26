`timescale 1ns/1ps
// Independent arithmetic oracle for score priority, glide, and manual restore.
module tb_score_bend_slew;
    reg clk=0,resetn=0,ce=0,write=0,clear=0;
    always #10 clk=~clk;
    reg [2:0] key=0;
    reg [15:0] value=16384,score=0,pressure=65535,lo=8192,hi=32768,slew=65535;
    reg [6:0] keys=0;
    wire [255:0] steps;
    localparam [223:0] BASE={7{32'd1048576}};
    fsr_pitch_scaler #(.PER_VOICE_BEND(1),.NOTE_INCREMENTS(BASE)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.pitch_ratio(pressure),.note_increments(BASE),
        .bend_write(write),.bend_reset(clear),.bend_index(key),.bend_ratio(value),
        .bend_min(lo),.bend_max(hi),.bend_slew(slew),.score_ratio(score),.score_keys(keys),
        .phase_increments(steps));
    integer expected[0:6],manual[0:6];
    integer fraction=0,checks=0,n,target,delta,frame_step;
    reg [63:0] product,pressure_base;
    task frame;
        begin
            @(negedge clk);ce=1;
            fraction=fraction+slew[7:0];frame_step=(slew>>8)+(fraction>>8);fraction=fraction&255;
            for(n=0;n<7;n=n+1)begin
                target=(score!=0 && keys[n])?score:manual[n];
                if(target>expected[n])begin delta=target-expected[n];expected[n]=expected[n]+(delta>frame_step?frame_step:delta);end
                else begin delta=expected[n]-target;expected[n]=expected[n]-(delta>frame_step?frame_step:delta);end
                if(expected[n]<lo)expected[n]=lo;if(expected[n]>hi)expected[n]=hi;
            end
            @(negedge clk);ce=0;repeat(60)@(negedge clk);
            if(dut.individual.u_bend.state!=1)$fatal(1,"Pitch frame missed original deadline");
            for(n=0;n<7;n=n+1)begin
                product=64'd1048576*pressure;pressure_base=pressure==65535?1048576:product>>16;
                product=pressure_base*expected[n];
                if(steps[n*32 +:32]!==product[45:14])$fatal(1,"Score glide mismatch key=%0d actual=%0d expected=%0d",n,steps[n*32 +:32],product>>14);
                checks=checks+1;
            end
        end
    endtask
    task set_manual;
        input [2:0] index;input [15:0] ratio;
        begin @(negedge clk);key=index;value=ratio;write=1;manual[index]=ratio;@(negedge clk);write=0;end
    endtask
    initial begin
        for(n=0;n<7;n=n+1)begin expected[n]=16384;manual[n]=16384;end
        repeat(3)@(negedge clk);resetn=1;repeat(12)@(negedge clk);
        frame;set_manual(0,18000);set_manual(2,22000);
        repeat(30)frame;
        score=20000;keys=7'b0000101;repeat(32)frame;
        // Manual changes are retained behind the temporary score override.
        set_manual(0,12000);repeat(4)frame;
        // Null target restores per-key manual values, including a later edit.
        score=0;repeat(40)frame;
        // Explicit zero cents is unity, represented by ratio 16384 (not null).
        score=16384;keys=7'b0000001;repeat(24)frame;
        score=32768;keys=7'b1000000;pressure=32768;repeat(72)frame;
        score=8192;repeat(108)frame;
        // Runtime range changes keep the applied value inside current bounds.
        lo=15000;hi=18000;repeat(12)frame;
        // STOP/rest/guide-only input is keys=0; existing manual targets return.
        keys=0;score=20000;pressure=65535;repeat(60)frame;
        lo=8192;hi=32768;slew=257;repeat(260)frame;
        $display("PASS score priority/glide/manual restore: %0d arithmetic checks, seven keys, null/unity, pressure, runtime clamp, fractional slew and original frame deadline",checks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"Score slew timeout");end
endmodule
