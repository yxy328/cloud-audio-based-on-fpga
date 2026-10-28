`timescale 1ns/1ps
module tb_control12_pitch;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,ce=0,wr=0,rst=0;
    reg [3:0] key=0;
    reg [15:0] ratio=65535,bend=16384;
    localparam [383:0] BASE={32'd43442435,32'd41004198,32'd38702809,32'd36530588,32'd34480283,32'd32545054,32'd30718440,32'd28994347,32'd27367019,32'd25831026,32'd24381242,32'd23012828};
    reg [95:0] mapping={8'd71,8'd70,8'd69,8'd68,8'd67,8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60};
    wire [415:0] steps;
    reg [415:0] previous;
    reg [47:0] expected;
    integer i,j;
    fsr_pitch_scaler #(.CONTROL_KEYS(12),.MAP_ROM(1),.PER_VOICE_BEND(1)) dut(.score_ratio(16'd0),.score_keys(12'd0),.bend_min(16'd8192),.bend_max(16'd32768),.bend_slew(16'd4096),.clk(clk),.resetn(resetn),.sample_ce(ce),
        .pitch_ratio(ratio),.note_increments(BASE),.note_map(mapping),.bend_write(wr),.bend_reset(rst),
        .bend_index(key),.bend_ratio(bend),.phase_increments(steps));
    task frame;
        begin @(negedge clk);ce=1;@(negedge clk);ce=0;repeat(90)@(negedge clk);end
    endtask
    task write_bend;
        input [3:0] k;input [15:0] r;
        begin key=k;bend=r;wr=1;@(negedge clk);wr=0;end
    endtask
    task check_key;
        input integer k;input [15:0] r;
        reg [47:0] a,b;
        begin
            a=BASE[k*32 +:32]*ratio;
            b=((ratio==65535)?BASE[k*32 +:32]:a[47:16])*r;
            if(steps[k*32 +:32]!==b[45:14])$fatal(1,"key%0d ratio%0d expected%0d got%0d",k,r,b[45:14],steps[k*32+:32]);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;repeat(20)@(negedge clk);frame;
        for(i=0;i<12;i=i+1)check_key(i,16384);
        write_bend(2,32768);
        previous=steps;repeat(100)@(negedge clk);
        if(steps!==previous)$fatal(1,"Pitch changed without audio frame");
        for(j=1;j<=1024;j=j+1)begin
            frame;check_key(2,16384+j*16);
            for(i=0;i<12;i=i+1)if(i!=2)check_key(i,16384);
        end
        write_bend(0,8192);write_bend(11,24576);
        for(j=0;j<512;j=j+1)frame;
        check_key(0,8192);check_key(2,32768);check_key(11,24576);
        ratio=32768;frame;
        check_key(0,8192);check_key(2,32768);check_key(11,24576);
        for(i=1;i<12;i=i+1)if(i!=2 && i!=11)check_key(i,16384);
        write_bend(12,20000);write_bend(1,8191);write_bend(3,32769);frame;
        check_key(1,16384);check_key(3,16384);
        rst=1;@(negedge clk);rst=0;repeat(20)@(negedge clk);
        previous=steps;frame;
        if(steps[95:64]>=previous[95:64] || steps[31:0]<=previous[31:0])$fatal(1,"Reset must slew toward unity");
        for(j=0;j<1024;j=j+1)frame;
        for(i=0;i<12;i=i+1)check_key(i,16384);
        ratio=65535;frame;for(i=0;i<12;i=i+1)check_key(i,16384);
        if(steps[415:384]!==0)$fatal(1,"Unused thirteenth slot");
        $display("PASS per-voice bend: exact unity/bounds, 1024 monotonic steps, independent twelve keys and merged MIDI ROM, FSR stacking, invalid guards, smooth reset, audio-frame timing");$finish;
    end
    initial begin #15000000;$fatal(1,"Bend timeout");end
endmodule
