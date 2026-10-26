from pathlib import Path
H=Path(__file__).resolve().parent
S=H/'chain/pcm5102_pam8403/sim'
old=(H.parent/'fx_delivery_20261025/fx_apds/pcm5102_pam8403/sim/tb_fx_proto_frame_guarded.v').read_text()
x=old.replace('tb_fx_proto_frame_guarded','tb_fx3_frame_take').replace('fx_proto_frame_guarded.csv','fx3_frame_take.csv')
x=x.replace('.FSR_ENABLE(0)', '.FSR_ENABLE(1),.SLIDER_STARTUP_MS(1),.SLIDER_POLL_MS(1)')
x=x.replace('.HC05_BAUD(500000)', '.TOUCH_SERIAL_HALF_CYCLES(50),.TOUCH_SERIAL_GAP_CYCLES(2500),.TOUCH_SERIAL_QUIET_CYCLES(100),.HC05_BAUD(500000)')
x=x.replace('ttp229_model chip(', 'ttp229_model #(.TIMEOUT_NS(40000)) chip(')
x=x.replace('tri1 scl,sda;', 'tri1 scl,sda,ads_scl,ads_sda;\n    reg [15:0] slider_code=32767;\n    ads1115_model slider(.clk(clk),.scl(ads_scl),.sda(ads_sda),.present(1\'b1),.code(slider_code));')
x=x.replace('.flash_miso(1\'b1),.scl(scl),.sda(sda));', '.flash_miso(1\'b1),.scl(scl),.sda(sda),.slider_scl(ads_scl),.slider_sda(ads_sda));')
x=x.replace('dut.tuning_ratio[2:0]','dut.fx_applied_mask').replace('max_fx_latency!=37','max_fx_latency!=49')
x=x.replace('command("TOUCH,16\\n",9);wait(dut.touch_ready);frames(4);','command("TOUCH,16\\n",9);wait(dut.touch_ready);frames(4);\n        command("ANALOG,1\\n",9);wait(dut.analog_available);')
x=x.replace('command("PITCH,,,256,16391\\n",18);','dut.u_fsr_adc.adc_inst.sim_value=14\'d1200;\n        command("PITCH,,,256\\n",13);')
x=x.replace('command("EFFECT,1,8\\n",11);', 'command("EFFECT,3,7,239,2148\\n",20);')
x=x.replace('command("EFFECT2,3\\n",10);frames(32);','frames(32);')
x=x.replace('command("EFFECT,2,8\\n",11);frames(32);','frames(32);')
x=x.replace('command("EFFECT,0,8\\n",11);frames(16);','frames(16);')
x=x.replace('isolated C+D+R prototype','C+D+R and pressure/ADS1115')
x=x.replace('        $fclose(csv);$finish;', '''        keys=0;wait(dut.touch_keys==0);frames(24);
        command("STOP\\n",5);frames(8);
        if(!dut.analog_available || dut.u_fsr_adc.adc_inst.conversions<2)$fatal(1,"Missing dual ADC activity");
        command("ANALOG,4\\n",9);frames(8);
        command("EFFECT,3,7,82,1092\\n",19);
        frames(8);expected_mix=dut.fx_live_mix;
        command("TAKE_REC\\n",9);frames(80);
        keys=16'h0885;wait(dut.touch_keys==16'h0885);frames(40);
        command("EFFECT,3,5,239,582\\n",19);frames(100);
        keys=0;wait(dut.touch_keys==0);frames(32);
        command("TAKE_STOP\\n",10);wait(!dut.perf_recording);frames(8);
        if(!dut.perf_available || dut.perf_full)$fatal(1,"TAKE not captured count=%0d",dut.perf_count);
        command("EFFECT,3,2,0,0\\n",15);
        slider_code=0;wait(dut.fx_live_mix==0);frames(8);
        command("TAKE_PLAY\\n",10);wait(dut.perf_playing);wait(!dut.perf_playing);frames(16);
        if(replay_a<20 || replay_b<20)$fatal(1,"Missing replay snapshots A=%0d B=%0d",replay_a,replay_b);
        if(dut.touch_active || dut.audio_sample!==0 || dut.u_effects.rev_hold!==0 || dut.u_effects.delay_hold!==0 || kill_clears==0)$fatal(1,"TAKE end did not clear effect tails");
        $display("PASS FX3 actual UART/TTP/dual ADC/TAKE playback: states A=%0d B=%0d events=%0d, stored wet overrides changed live slider",replay_a,replay_b,dut.perf_count);
        $fclose(csv);$finish;''')
x=x.replace('    time ', '    time ')
x=x.replace('    initial begin\n        csv=', '''    integer replay_a=0,replay_b=0,kill_clears=0;
    reg [11:0] expected_mix;
    reg kill_d=0;
    always @(posedge clk)kill_d<=dut.perf_kill;
    always @(negedge clk)if(dut.resetn && kill_d)begin
        if(dut.u_effects.cf!==0 || dut.u_effects.df!==0 || dut.u_effects.age!==0 || dut.u_effects.state!==0)$fatal(1,"Kill did not synchronously invalidate histories");
        kill_clears=kill_clears+1;
    end
    always @(posedge clk)if(dut.resetn && dut.frame_ce && dut.perf_replay)begin
        if(!dut.perf_state[511] || dut.fx_applied_mix!==expected_mix)$fatal(1,"TAKE version/mix mismatch");
        if(dut.fx_applied_mask==7 && dut.fx_applied_settings==8'h52)replay_a=replay_a+1;
        else if(dut.fx_applied_mask==5 && dut.fx_applied_settings==8'hef)replay_b=replay_b+1;
        else $fatal(1,"Torn/unrecorded FX state mask=%d settings=%h",dut.fx_applied_mask,dut.fx_applied_settings);
    end
    initial begin
        csv=''')
# Byte lengths are checked here, avoiding truncation of packed UART messages.
import re
x=re.sub(r'command\("([^"\n]*)",(\d+)\)',lambda m:'command("'+m[1]+'",'+str(len(m[1].replace('\\n','\n')))+')',x)
for text,n in re.findall(r'command\("([^"\n]*)",(\d+)\)',x):
    assert len(text.replace('\\n','\n'))==int(n),(text,n,len(text.replace('\\n','\n')))
(S/'tb_fx3_frame_take.v').write_text(x)

decode='''`timescale 1ns/1ps
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
'''
(S/'tb_fx3_replay_decode.v').write_text(decode)
print('Created real-pin FX stress/TAKE and targeted old/new snapshot decode tests')
