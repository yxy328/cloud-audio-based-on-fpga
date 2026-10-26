"""Preserve the failed polarity transition test; validate sensor reconfiguration."""
from pathlib import Path
import hashlib,json
here=Path(__file__).resolve().parent
p=here/'fixed16_clean/pcm5102_pam8403'
s=(p/'sim/tb_top_fixed16.v').read_text(encoding='utf-8')
s=s.replace('module tb_top_fixed16;','module tb_top_fixed16_controls;')
s=s.replace('reg model_high=0;','reg model_high=0;\n    reg sensor_reset=0;')
a='ttp229_model chip(.rst_n(dut.resetn),'
assert s.count(a)==1
s=s.replace(a,'ttp229_model chip(.rst_n(dut.resetn && !sensor_reset),')
start=s.index('        // End-to-end I2S spectrum:')
end=s.index('        transact("HOLD,1',start)
s=s[:start]+'''        // Spectrum was checked in the preceding 197.99781 ms run.
        // This focused controls/reconfiguration test does not repeat it.
'''+s[end:]
a='''        transact("SERIAL,1\\n",9,{"OK",8'd13,"\\n"});model_high=1;
        transact("TOUCH,16\\n",9,{"OK",8'd13,"\\n"});wait(dut.touch_ready);frames(4);'''
b='''        // Reconfigure/reset the external sensor model along with its polarity.
        // Keep it reset through UART acknowledgement, then release during the
        // reader's normal >2 ms GAP; do not invent a mid-frame sensor edge.
        sensor_reset=1;
        transact("SERIAL,1\\n",9,{"OK",8'd13,"\\n"});model_high=1;
        wait(dut.u_touch_serial.state==1);
        @(negedge clk);sensor_reset=0;
        transact("TOUCH,16\\n",9,{"OK",8'd13,"\\n"});wait(dut.touch_ready);frames(4);'''
assert s.count(a)==1
s=s.replace(a,b)
s=s.replace('PASS fixed16 integration: serial startup, real UART and TTP pins, all 16 pitches in decoded I2S, GPIO isolation, TOUCH8 rejected held and idle, hold/panic, K16/pressure, both polarities',
    'PASS fixed16 controls: serial startup, real UART and TTP pins, 16 note gates, GPIO isolation, TOUCH8 rejected held and idle, hold/panic, K16/pressure, sensor reset and reconfiguration to high-active polarity')
path=p/'sim/tb_top_fixed16_controls.v';assert not path.exists()
path.write_text(s,encoding='utf-8')
oldlog=here/'fixed16_clean_functional.log'
text=oldlog.read_text(encoding='utf-16' if oldlog.read_bytes().startswith(b'\xff\xfe') else 'utf-8-sig',errors='replace')
assert 'More than 16 clocks without serial timeout' in text
record={'failed_test':'tb_top_fixed16','failed_log':'fixed16_clean_functional.log',
    'failed_log_sha256':hashlib.sha256(oldlog.read_bytes()).hexdigest().upper(),
    'whole_test_passed':False,
    'failure':'Sensor model switched its clock polarity after UART acknowledgement while fixed16 reader was already scanning',
    'preceding_sequential_checks_completed':['startup16','GPIO ignored','16 active voices','TOUCH8 ERR,RANGE held',
        '8192-sample I2S spectrum all16 pitches','HOLD','PANIC','K16','PRESSURE','TOUCH8 ERR,RANGE idle'],
    'evidence_for_preceding_checks':'Linear initial sequence reached SERIAL1 near 197.998 ms without an earlier fatal; no final whole-test PASS claim',
    'followup':'tb_top_fixed16_controls validates controls without repeating spectrum, resets reconfigured sensor through UART and releases it in normal GAP',
    'does_not_validate':'Arbitrary live polarity flips of a connected sensor in the middle of a packet'}
(here/'polarity_test_diagnosis.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print('Prepared focused controls and externally reset sensor polarity test; original failure preserved')
