`timescale 1ns/1ps
module tb_performance_take;
    wire legacy_playback;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [2:0] command=0;
    reg [5:0] frame_div=0;
    wire frame_ce=frame_div==63;
    always @(posedge clk)if(!resetn)frame_div<=0;else frame_div<=frame_div+1'b1;
    reg [63:0] live_state=0;reg [15:0] live_pulses=0;
    wire [63:0] play_state;wire [15:0] play_pulses;
    wire recording,playing,play_valid,kill,available,saved,full;
    wire [3:0] error;wire [1:0] confirm;
    wire [23:0] elapsed_ms,duration_ms;wire [6:0] count;
    reg nv_busy=0,nv_boot_done=0,nv_valid=0,nv_done=0,nv_ok=0,nv_full=0;
    reg [3:0] nv_error=0;reg [6:0] nv_count=0;reg [23:0] nv_duration=0;
    wire nv_save,nv_delete;reg nv_we=0;reg [5:0] nv_address=0;
    reg [47:0] nv_data=0;wire [47:0] nv_q;
    performance_take #(.CLK_HZ(100000),.WORDS(4),.DEPTH(64)) dut(.*);
    integer checks=0,pulse_count=0,kills=0;
    reg observe=0;
    reg [47:0] saved_words[0:63];integer saved_count=0;reg [23:0] saved_duration;
    task check;input condition;input [255:0] message;begin
        checks=checks+1;if(!condition)$fatal(1,"%0s",message);
    end endtask
    task cmd;input [2:0] c;begin @(negedge clk);command=c;@(negedge clk);command=0;end endtask
    task ticks;input integer n;integer j;begin
        for(j=0;j<n;j=j+1)begin wait(dut.tick);@(posedge clk);@(negedge clk);end
    end endtask
    task boot;begin
        repeat(3)@(negedge clk);resetn=1;@(negedge clk);nv_boot_done=1;
        @(negedge clk);nv_boot_done=0;repeat(2)@(negedge clk);
    end endtask
    // Mock adapter only: persistence tests below retain this model's storage
    // across DUT reset. They do not constitute SPI NOR or board verification.
    task commit;input success;integer j;begin
        wait(nv_save);@(negedge clk);nv_busy=1;
        saved_count=count;saved_duration=duration_ms;
        for(j=0;j<saved_count;j=j+1)begin
            nv_address=j;repeat(3)@(negedge clk);saved_words[j]=nv_q;
        end
        nv_ok=success;nv_error=success ? 0 : 8;nv_done=1;nv_busy=0;
        @(negedge clk);nv_done=0;repeat(2)@(negedge clk);
    end endtask
    always @(posedge clk)if(observe)begin
        if(play_pulses!=0)pulse_count=pulse_count+1;
        if(kill)kills=kills+1;
    end
    integer i;
    initial begin
        boot;
        $display("stage initial capture");
        cmd(3);check(error==4 && !playing,"empty replay rejected");
        live_state={16'h0000,16'h1000,16'hffff,16'h1234};cmd(1);
        wait(dut.state==4);check(recording && count==5,"initial full snapshot");
        cmd(1);cmd(7);check(recording && count==5 && !nv_save,"duplicate REC and SAVE during capture ignored");
        ticks(2);live_state[63:48]=16'h0001;
        ticks(3);live_state[63:48]=16'h0015;live_state[31:16]=16'h8000;
        @(negedge clk);live_pulses=16'h0105;@(negedge clk);live_pulses=0;
        ticks(2);live_state[63:48]=0;
        ticks(2);cmd(2);wait(!recording);repeat(2)@(negedge clk);
        check(available && !saved && !nv_save && dut.state==1,"STOP retains RAM without Flash");
        cmd(3);wait(play_state[63:48]!=0);cmd(2);
        check(available && !saved && !nv_save,"immediate unsaved RAM replay");
        fork cmd(7);commit(1);join
        check(available && saved && duration_ms>=9 && error==0,"committed take");
        cmd(7);check(saved && !nv_save,"duplicate SAVE does not rewrite Flash");
        check(saved_words[saved_count-1][23:16]==8'hff,"end marker retained");
        $display("stage playback count=%0d duration=%0d",count,duration_ms);
        cmd(1);check(confirm==1 && !recording && saved,"overwrite confirmation");
        cmd(6);check(confirm==0 && saved,"cancel keeps old take");
        pulse_count=0;kills=0;observe=1;cmd(3);
        wait(play_state[63:48]==16'h0001);check(play_state[15:0]==16'h1234,"pitch snapshot restored");
        wait(play_state[63:48]==16'h0015);check(play_state[31:16]==16'h8000,"chord and dynamics atomic");
        wait(!playing);repeat(3)@(negedge clk);observe=0;
        check(play_state[63:48]==0 && !play_valid && pulse_count==1 && kills==2,"one-shot and hard end");
        // Stop at a pending future event: no held gates or subsequent retrigger.
        cmd(3);wait(play_state[63:48]==1);cmd(4);
        repeat(2)@(negedge clk);check(!playing && !play_valid && play_state[63:48]==0,"K14 delete chord still stops playback");
        repeat(1000)@(negedge clk);check(!playing && play_pulses==0,"no events after stop");
        // Reinitialize DUT and load the mock adapter's committed image.
        $display("stage restart");
        resetn=0;nv_valid=1;nv_count=saved_count;nv_duration=saved_duration;nv_full=1;
        repeat(3)@(negedge clk);resetn=1;nv_busy=1;
        for(i=0;i<saved_count;i=i+1)begin
            nv_address=i;nv_data=saved_words[i];nv_we=1;@(negedge clk);
        end
        nv_we=0;nv_busy=0;nv_boot_done=1;@(negedge clk);nv_boot_done=0;
        repeat(2)@(negedge clk);check(saved && available && full,"mock restart recovery/full flag");
        cmd(3);wait(play_state[63:48]==16'h0015);cmd(2);
        // Failed adapter commit cannot display saved.
        $display("stage failed commit");
        cmd(1);cmd(5);wait(dut.state==4);live_state[63:48]=1;ticks(2);cmd(2);wait(!recording);
        fork cmd(7);commit(0);join
        check(available && !saved && error==8,"save failure remains unsaved");
        cmd(3);wait(play_state[63:48]!=0);cmd(2);
        check(available && !playing,"save failure still permits RAM replay");
        // Capacity must leave a complete final group and END, never wrap RAM.
        $display("stage capacity");
        cmd(1);cmd(5);wait(dut.state==4);
        while(recording)begin
            @(negedge clk);
            if(dut.tick)live_state=live_state+64'h0001000100010001;
        end
        repeat(2)@(negedge clk);check(full && available && !nv_save && count<=64,"capacity stops without auto-save");
        fork cmd(7);commit(1);join
        check(saved_words[saved_count-1][23:16]==8'hff,"full take is terminated");
        // Two identical impulses inside a tick are detected, never merged.
        cmd(1);cmd(5);wait(dut.state==4);
        kills=0;observe=1;
        @(negedge clk);live_pulses=1;@(negedge clk);live_pulses=0;
        @(negedge clk);live_pulses=1;@(negedge clk);live_pulses=0;
        repeat(2)@(negedge clk);observe=0;
        check(!recording && !saved && error==6 && kills==0,"record failure preserves live audio");
        cmd(1);check(confirm==1 && !recording,"old Flash take still needs confirmation");cmd(6);
        live_state[63:48]=0;cmd(1);cmd(5);ticks(3);cmd(2);wait(!recording);repeat(2)@(negedge clk);
        check(!available && count==0 && error==4 && !nv_save,"empty recording is not saved");
        cmd(7);check(!nv_save && error==4,"empty SAVE rejected");
        // Malformed full-depth image without END must stop at count, rather
        // than wrapping the read pointer and replaying forever.
        resetn=0;nv_count=64;nv_duration=0;nv_full=0;
        repeat(3)@(negedge clk);resetn=1;nv_busy=1;
        for(i=0;i<64;i=i+1)begin
            nv_address=i;nv_data={24'd0,8'd0,16'h1234};nv_we=1;@(negedge clk);
        end
        nv_we=0;nv_busy=0;nv_boot_done=1;@(negedge clk);nv_boot_done=0;
        repeat(2)@(negedge clk);cmd(3);wait(!playing);@(negedge clk);
        check(error==3 && !play_valid && play_state[63:48]==0,"malformed full image cannot loop");
        $display("PASS tb_performance_take: %0d checks, mock storage only",checks);$finish;
    end
        initial begin #3000000;$fatal(1,"timeout");end
endmodule
