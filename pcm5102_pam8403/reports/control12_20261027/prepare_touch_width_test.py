from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
s=(R/'packed_step_tests/tb_control12_step_ram.v').read_text(encoding='utf-8')
s=s.replace('tb_control12_step_ram','tb_control12_touch_widths')
s=s.replace('parameter READ_MODE=0','parameter READ_MODE=0, GAIN_SHIFT=4')
s=s.replace('.RAM_STEPS(1),','.VOLUME_SHIFT(GAIN_SHIFT),')
s=s.replace('touch_control12_step_reference #(.CONTROL_KEYS(12),','touch_control12_step_reference #(.VOLUME_SHIFT(GAIN_SHIFT),.CONTROL_KEYS(12),')
s=s.replace('.low_steps(live_steps),.replay_steps(replay_steps),\n        .replay_select(replay),','.low_steps(replay ? replay_steps : live_steps),')
s=s.replace('{dut.contexts[i*16+7][15:0],dut.contexts[i*16+6][31:16]}','{dut.contexts[i*16+14],dut.contexts[i*16+13]}')
s=s.replace('PASS control12 step RAM:', 'PASS exact touch arithmetic:')
s=s.replace('live scanner/replay half-word races,','live/replay updates,')
s=s.replace('Step RAM test timeout','Touch arithmetic timeout')
(P/'sim/tb_control12_touch_widths.v').write_text(s,encoding='utf-8')
for name,params in [('fast','.READ_MODE(1)'),('loud','.GAIN_SHIFT(0)'),('quiet','.GAIN_SHIFT(18)')]:
 (P/f'sim/tb_control12_touch_widths_{name}.v').write_text(f'''`include "sim/tb_control12_touch_widths.v"
module tb_control12_touch_widths_{name};
    tb_control12_touch_widths #({params}) test();
endmodule
''',encoding='utf-8')
print('Prepared bit-exact comparisons against old arithmetic at shifts 0/4/18 and both RAM read schedules')
