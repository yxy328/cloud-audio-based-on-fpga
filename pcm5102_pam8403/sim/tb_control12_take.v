`timescale 1ns/1ps
module tb_control12_take;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [2:0] command=0;reg [7:0] frame_div=0;
    wire frame_ce=&frame_div;
    always @(posedge clk)frame_div<=frame_div+1'b1;
    reg [687:0] live_state=0;reg [15:0] live_pulses=0;
    wire [687:0] play_state;wire [15:0] play_pulses;
    wire play_valid,legacy_playback,recording,playing,kill,available,saved,full;
    wire [3:0] error;wire [1:0] confirm;wire [23:0] elapsed_ms,duration_ms;
    wire [10:0] count;
    reg nv_busy=0,nv_boot_done=0,nv_valid=0,nv_done=0,nv_ok=0,nv_full=0;
    reg [3:0] nv_error=0;reg [10:0] nv_count=0;reg [23:0] nv_duration=0;
    wire nv_save,nv_delete;reg nv_we=0;reg [9:0] nv_address=0;
    reg [47:0] nv_data=0;wire [47:0] nv_q;
    performance_take #(.CLK_HZ(1000000),.WORDS(43),.GATE_WORD(32),.LEGACY_WORDS(33)) dut(.*);
    task cmd;input [2:0] c;begin @(negedge clk);command=c;@(negedge clk);command=0;end endtask
    task ticks;input integer n;integer j;begin
        for(j=0;j<n;j=j+1)begin wait(dut.tick);@(posedge clk);@(negedge clk);end
    end endtask
    integer k;reg [687:0] old_snapshot;
    task load;input integer fields;begin
        @(negedge clk);resetn=0;nv_valid=1;nv_count=fields+2;nv_duration=3;
        repeat(4)@(negedge clk);resetn=1;nv_busy=1;nv_we=1;
        for(k=0;k<fields;k=k+1)begin
            nv_address=k;nv_data={24'd0,k[7:0],16'd0};
            if(k==32)nv_data[15:0]=16'h0800;
            @(negedge clk);
        end
        nv_address=fields;nv_data={24'd0,8'hfe,16'd0};@(negedge clk);
        nv_address=fields+1;nv_data={24'd3,8'hff,16'd0};@(negedge clk);
        nv_we=0;nv_busy=0;nv_boot_done=1;@(negedge clk);nv_boot_done=0;repeat(3)@(negedge clk);
    end endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;nv_boot_done=1;@(negedge clk);nv_boot_done=0;
        live_state[512+:16]=16'h0800;live_state[528+:160]={32'd12345,32'd23456,32'd34567,32'd45678,32'd56789};
        old_snapshot=live_state;cmd(1);wait(dut.state==4);
        if(count!=44)$fatal(1,"12-control snapshot must be 43 fields + commit");
        ticks(2);live_state[656+:32]=32'h02ffffff;ticks(2);cmd(2);wait(!recording);
        if(!available || count>1024 || nv_save)$fatal(1,"RAM take failed");
        cmd(3);wait(play_valid);@(negedge clk);
        if(legacy_playback || play_state!==old_snapshot)$fatal(1,"Initial twelve-key snapshot not atomic");
        wait(play_state[656+:32]==32'h02ffffff);cmd(2);repeat(3)@(negedge clk);
        if(playing || play_state[512+:16]!=0)$fatal(1,"STOP must clear gate word32");
        load(33);cmd(3);wait(play_valid);@(negedge clk);
        if(!legacy_playback || play_state[512+:16]!=16'h0800)$fatal(1,"Legacy 33-field take rejected");
        wait(!playing);if(error!=0)$fatal(1,"Legacy END rejected");
        load(43);cmd(3);wait(play_valid);@(negedge clk);
        if(legacy_playback)$fatal(1,"Extended take misidentified as legacy");cmd(2);
        load(40);cmd(3);wait(!playing);if(error!=3)$fatal(1,"Partial extension must fail visibly");
        $display("PASS control12 TAKE: 43-field atomic capture/replay, changed K12 pitch, gate32, legacy33 recovery, extended recovery, malformed partial snapshot rejection; capacity 1024 unchanged");$finish;
    end
    initial begin #10000000;$fatal(1,"TAKE timeout");end
endmodule
