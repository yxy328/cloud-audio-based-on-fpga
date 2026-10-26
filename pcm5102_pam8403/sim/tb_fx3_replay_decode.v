`timescale 1ns/1ps
// Targeted mux wiring test: force only replay inputs, not behavioral audio results.
module tb_fx3_replay_decode;
reg clk=0;always #10 clk=~clk;
top #(.ENABLE_EVENT_TAKE(1),.EVENT_KEYS_ENABLE(0),.FSR_ENABLE(0)) dut(.clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(0),.touch_sdo(1'b1),.ir_beam(8'hff),.hc05_rx(1'b1),.audio_rec_cts_n(1'b1),.flash_miso(1'b1));
reg [527:0] snapshot=0;
integer m,w,k,checks=0;
initial begin
    force dut.perf_replay=1;force dut.perf_state=snapshot;
    force dut.echo_tap=2'd2;
    for(m=0;m<3;m=m+1)for(w=0;w<=8;w=w+1)begin
        snapshot=0;snapshot[485:484]=m;snapshot[483:480]=w;
        snapshot[464+:13]=13'd2048;snapshot[448+:16]=16'd54321;
        #1;
        if(dut.fx_applied_mask!==(m==1?3'd2:m==2?3'd1:3'd0) || dut.fx_applied_settings!==8'h5b || dut.fx_applied_mix!=={w[3:0],w[3:0],w[3:0]})$fatal(1,"Old TAKE decode");
        if(dut.u_master_volume.target_gain!==2048 || dut.u_touch_synth.pitch_ratio!==54321)$fatal(1,"Musical fields moved");
        checks=checks+1;
    end
    for(m=0;m<8;m=m+1)for(k=0;k<256;k=k+1)begin
        snapshot=0;snapshot[511]=1;snapshot[486:484]=m;snapshot[494:487]=k;snapshot[431:420]=12'h864;
        #1;
        if(dut.fx_applied_mask!==m[2:0] || dut.fx_applied_settings!==k[7:0] || dut.fx_applied_mix!==12'h864)$fatal(1,"New TAKE decode");
        checks=checks+1;
    end
    release dut.perf_state;release dut.perf_replay;release dut.echo_tap;
    $display("PASS FX3 replay old/new version and unchanged musical fields: %0d checks",checks);$finish;
end
endmodule
