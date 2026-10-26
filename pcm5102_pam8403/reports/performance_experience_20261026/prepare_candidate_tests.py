from work import *
root=HERE/'tremolo_v1';p=root/PROJECT.name
bench=(PROJECT/'sim/tb_fx_protocol.v').read_text(encoding='utf-8')
bench=bench.replace('module tb_fx_protocol;', 'module tb_tremolo_protocol;\n    wire [7:0] cfg_tremolo;')
bench=bench.replace('.clk(clk),','.tremolo_config(cfg_tremolo),.tremolo_applied(applied_override ? 8\'h38 : cfg_tremolo),.clk(clk),',1)
bench=bench.replace('integer m,trace;', 'integer m,trace,r,d;')
bench=bench.replace('transact("PING\\n",5,', '''transact("EFFECT,4,?\\n",11,{"TREM,00,00",8'd13,8'd10});
        for(r=0;r<=8;r=r+1)for(d=0;d<=8;d=d+1)begin
            $sformat(command_text,"EFFECT,4,%0d,%0d\\n",r,d);
            transact(command_text,length(command_text),{"OK",8'd13,8'd10});
            transact("EFFECT,4,?\\n",11,{"TREM,",digit(r),digit(d),",",digit(r),digit(d),8'd13,8'd10});
        end
        transact("EFFECT,4,9,8\\n",13,{"ERR,RANGE",8'd13,8'd10});
        transact("EFFECT,4,8,9\\n",13,{"ERR,RANGE",8'd13,8'd10});
        transact("EFFECT,4,8\\n",11,{"ERR,CMD",8'd13,8'd10});
        transact("EFFECT,4,8,8,0\\n",15,{"ERR,CMD",8'd13,8'd10});
        applied_override=1;
        transact("EFFECT,4,?\\n",11,{"TREM,88,38",8'd13,8'd10});
        applied_override=0;
        transact("PING\\n",5,''').replace('#100000000;', '#1000000000;')
# Prevent the old trace file from being confused with production fixtures.
bench=bench.replace('fx_protocol_replies.txt','tremolo_protocol_replies.txt')
(p/'sim/tb_tremolo_protocol.v').write_text(bench,encoding='utf-8')
decode=(PROJECT/'sim/tb_fx3_replay_decode.v').read_text(encoding='utf-8')
decode=decode.replace('tb_fx3_replay_decode','tb_tremolo_decode')
decode=decode.replace('$display("PASS FX3', '''for(m=0;m<=8;m=m+1)for(w=0;w<=8;w=w+1)begin
        force dut.perf_replay=1;force dut.perf_state=snapshot;
        snapshot=0;snapshot[511]=1;snapshot[508:501]={m[3:0],w[3:0]};#1;
        if(dut.tremolo_applied!=={m[3:0],w[3:0]})$fatal(1,"Tremolo TAKE bits");
        snapshot[511]=0;#1;if(dut.tremolo_applied!==0)$fatal(1,"Legacy TAKE tremolo must be off");
        checks=checks+2;
    end
    $display("PASS tremolo TAKE + FX3''')
(p/'sim/tb_tremolo_decode.v').write_text(decode,encoding='utf-8')

root=HERE/'source_volume_v2';p=root/PROJECT.name
bench=(PROJECT/'sim/tb_fx_protocol.v').read_text(encoding='utf-8')
bench=bench.replace('module tb_fx_protocol;', 'module tb_source_volume_protocol;\n    wire [3:0] source_volume;')
bench=bench.replace('.clk(clk),','.source_volume(source_volume),.source_volume_applied(source_volume),.clk(clk),',1)
bench=bench.replace('transact("PING\\n",5,', '''transact("VOLUME,?\\n",9,{"SRCVOL,F,F",8'd13,8'd10});
        transact("VOLUME,1,0\\n",11,{"OK",8'd13,8'd10});
        transact("VOLUME,?\\n",9,{"SRCVOL,C,C",8'd13,8'd10});
        transact("VOLUME,2,2\\n",11,{"OK",8'd13,8'd10});
        transact("VOLUME,16\\n",10,{"OK",8'd13,8'd10});
        transact("VOLUME,3,2\\n",11,{"ERR,RANGE",8'd13,8'd10});
        transact("VOLUME,2,4\\n",11,{"ERR,RANGE",8'd13,8'd10});
        transact("VOLUME,1,2,3\\n",13,{"ERR,CMD",8'd13,8'd10});
        transact("VOLUME,?\\n",9,{"SRCVOL,8,8",8'd13,8'd10});
        transact("PING\\n",5,''')
bench=bench.replace('fx_protocol_replies.txt','source_volume_protocol_replies.txt')
(p/'sim/tb_source_volume_protocol.v').write_text(bench,encoding='utf-8')
bench='''`timescale 1ns/1ps
module tb_source_volume_decode;
reg clk=0;always #10 clk=~clk;
top #(.ENABLE_EVENT_TAKE(1),.EVENT_KEYS_ENABLE(0),.FSR_ENABLE(0)) dut(.clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.touch_sdo(1'b1),.ir_beam(8'hff),.hc05_rx(1'b1),.audio_rec_cts_n(1'b1),.flash_miso(1'b1));
integer level,x,expected,k;
reg [527:0] snapshot;
initial begin
    for(level=0;level<4;level=level+1)for(x=-32768;x<=32767;x=x+1)begin
        expected=level==0 ? 0 : level==1 ? x/4 : level==2 ? x/2 : x;
        if($signed(dut.source_attenuate(x,level))!==expected)$fatal(1,"Static attenuation x=%d level=%d",x,level);
    end
    force dut.perf_replay=1;force dut.perf_state=snapshot;
    snapshot=0;#1;if(dut.source_volume_applied!==15)$fatal(1,"Old TAKE unity");
    for(k=0;k<16;k=k+1)begin snapshot=0;snapshot[495]=1;snapshot[510:507]=k;#1;
        if(dut.source_volume_applied!==k[3:0])$fatal(1,"New TAKE volume");end
    $display("PASS source volume: 262144 signed PCM/level pairs, legacy unity and 16 TAKE configs");$finish;
end
endmodule
'''
(p/'sim/tb_source_volume_decode.v').write_text(bench,encoding='utf-8')
print('Prepared isolated candidate protocol/TAKE/attenuation tests')
