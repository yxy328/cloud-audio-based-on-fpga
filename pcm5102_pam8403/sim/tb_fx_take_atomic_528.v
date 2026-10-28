`timescale 1ns/1ps
module tb_fx_take_atomic_528;
    wire legacy_playback;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [2:0] command=0;
    reg [9:0] frame_div=0;
    wire frame_ce=frame_div==1023;
    always @(posedge clk)if(!resetn)frame_div<=0;else frame_div<=frame_div+1'b1;
    localparam [527:0] OLD={16'h0001,{32{16'h1111}}},NEW={16'h0003,{32{16'habcd}}};
    reg [527:0] live_state=OLD;reg [15:0] live_pulses=0;
    wire [527:0] play_state;wire [15:0] play_pulses;
    wire recording,playing,play_valid,kill,available,saved,full;
    wire [3:0] error;wire [1:0] confirm;wire [23:0] elapsed_ms,duration_ms;wire [10:0] count;
    reg nv_busy=0,nv_boot_done=0,nv_valid=0,nv_done=0,nv_ok=0,nv_full=0;
    reg [3:0] nv_error=0;reg [10:0] nv_count=0;reg [23:0] nv_duration=0;
    wire nv_save,nv_delete;reg nv_we=0;reg [9:0] nv_address=0;reg [47:0] nv_data=0;wire [47:0] nv_q;
    performance_take #(.CLK_HZ(1000000),.WORDS(33),.DEPTH(1024)) dut(.*);
    integer old_seen=0,new_seen=0,i,checks=0;
    always @(posedge clk)if(play_valid && frame_ce)begin
        if(play_state===OLD)old_seen=old_seen+1;
        else if(play_state===NEW)new_seen=new_seen+1;
        else $fatal(1,"Torn playback control group: %h",play_state);
    end
    task cmd;input [2:0] value;begin
        @(negedge clk);command=value;@(negedge clk);command=0;
    end endtask
    initial begin
        repeat(3)@(negedge clk);resetn=1;nv_boot_done=1;
        @(negedge clk);nv_boot_done=0;repeat(2)@(negedge clk);
        cmd(1);live_state=NEW; // Deliberately change while the initial group is being serialized.
        wait(dut.state==4);@(negedge clk);
        for(i=0;i<33;i=i+1)begin
            checks=checks+1;
            if(dut.events[i][15:0]!==OLD[i*16 +: 16])$fatal(1,"Torn capture word %0d",i);
        end
        repeat(5000)@(negedge clk);cmd(2);wait(!recording);repeat(2)@(negedge clk);cmd(3);
        wait(!playing);repeat(2)@(negedge clk);
        checks=checks+1;
        if(old_seen==0 || new_seen==0 || error!=0)$fatal(1,"Missing atomic commits old=%0d new=%0d err=%0d",old_seen,new_seen,error);
        $display("PASS full528 FX atomic snapshot: %0d checks; complete capture and no mixed words at any audio frame",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"Atomic group timeout");end
endmodule
