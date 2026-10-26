"""Add assessment tests without changing frozen production or reference models."""
from pathlib import Path
import hashlib,json

here=Path(__file__).resolve().parent
project=here.parent.parent
fixed=here/'fixed16/pcm5102_pam8403'
source=(fixed/'sim/tb_top_touch16.v').read_text(encoding='utf-8-sig')
changes={
    'module tb_top_touch16;':'module tb_top_fixed16;',
    'if(tscl!==1 || dut.touch_mode16)$fatal(1,"Default direct mode");':
        'if(dut.touch_mode16!==1\'b1)$fatal(1,"Default fixed serial mode");',
    'transact("TOUCH,8\\n",8,{"ERR,BUSY",8\'d13,"\\n"});':
        'transact("TOUCH,8\\n",8,{"ERR,RANGE",8\'d13,"\\n"});\n'
        '        if(!dut.touch_mode16 || dut.touch_keys!=16\'hffff)$fatal(1,"Rejected TOUCH8 changed active serial notes");',
    '''        transact("TOUCH,8\\n",8,{"OK",8'd13,"\\n"});wait(dut.touch_ready);frames(4);
        if(tscl!==1 || dut.extended_active || dut.touch_keys)$fatal(1,"Return to GPIO left serial state");
        pads=1;wait(dut.touch_keys==1);frames(20);
        if(!dut.touch_active[0] || dut.extended_active)$fatal(1,"GPIO did not recover");
        pads=0;wait(dut.touch_keys==0);frames(30);''':
        '''        transact("TOUCH,8\\n",8,{"ERR,RANGE",8'd13,"\\n"});frames(4);
        if(!dut.touch_mode16 || dut.extended_active || dut.touch_keys)$fatal(1,"Idle TOUCH8 changed serial state");
        pads=255;frames(30);
        if(dut.touch_keys || dut.touch_active || dut.extended_active)$fatal(1,"Removed GPIO path became active");
        pads=0;frames(4);''',
    'PASS 8/16 integration: real UART and TTP serial pins, all 16 pitches in decoded I2S, GPIO isolation, busy rejection, hold/panic, K16/pressure, return to GPIO':
        'PASS fixed16 integration: serial startup, real UART and TTP pins, all 16 pitches in decoded I2S, GPIO isolation, TOUCH8 rejected held and idle, hold/panic, K16/pressure, both polarities',
}
for a,b in changes.items():
    assert source.count(a)==1,repr(a)
    source=source.replace(a,b)
assert not (fixed/'sim/tb_top_fixed16.v').exists()
(fixed/'sim/tb_top_fixed16.v').write_text(source,encoding='utf-8')

fx=here/'fx_fixed16/pcm5102_pam8403'
prior=project/'reports/fx_delivery_20261025/fx_apds/pcm5102_pam8403'
frame=(prior/'sim/tb_fx_proto_frame_guarded.v').read_text(encoding='utf-8-sig')
frame=frame.replace('tb_fx_proto_frame_guarded','tb_fx_fixed16_frame')
frame=frame.replace('fx_proto_frame_guarded.csv','fx_fixed16_frame.csv')
frame=frame.replace('wait(dut.touch_ready);frames(3);',
    'wait(dut.touch_ready);frames(3);\n        if(dut.touch_mode16!==1\'b1)$fatal(1,"Fixed16 startup");')
assert not (fx/'sim/tb_fx_fixed16_frame.v').exists()
(fx/'sim/tb_fx_fixed16_frame.v').write_text(frame,encoding='utf-8')
runner=fx/'tools/run_sim.ps1'
text=runner.read_text(encoding='utf-8-sig')
needle="$rtl += @('sim/i2s_pcm_monitor.v')"
assert text.count(needle)==1
runner.write_text(text.replace(needle,"$rtl += @('sim/i2s_pcm_monitor.v','src/audio_fx_minproto.v')"),encoding='utf-8-sig')

items=[]
for path in [fixed/'sim/tb_top_fixed16.v',fx/'sim/tb_fx_fixed16_frame.v',runner]:
    items.append({'path':path.relative_to(here).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper()})
(here/'test_inputs.json').write_text(json.dumps(items,indent=2)+'\n',encoding='utf-8')
print('Prepared fixed16 pin/UART/I2S integration and combined same-frame assessment tests')
