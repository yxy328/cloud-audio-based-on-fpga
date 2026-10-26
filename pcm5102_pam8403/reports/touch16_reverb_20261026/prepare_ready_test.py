"""Preserve BUSY evidence and check the documented ready gate before retry."""
from pathlib import Path
import json,hashlib
here=Path(__file__).resolve().parent;p=here/'fixed16_clean/pcm5102_pam8403'
s=(p/'sim/tb_top_fixed16_controls.v').read_text(encoding='utf-8')
s=s.replace('module tb_top_fixed16_controls;','module tb_top_fixed16_controls_ready;')
a='''        @(negedge clk);sensor_reset=0;
        transact("TOUCH,16\\n",9,{"OK",8'd13,"\\n"});wait(dut.touch_ready);frames(4);'''
b='''        @(negedge clk);sensor_reset=0;
        // Reconfiguration clears reader readiness. The public edit command
        // must report BUSY during recovery, then accept the retry when ready.
        transact("TOUCH,16\\n",9,{"ERR,BUSY",8'd13,"\\n"});
        wait(dut.touch_ready);frames(4);
        transact("TOUCH,16\\n",9,{"OK",8'd13,"\\n"});frames(4);'''
assert s.count(a)==1;s=s.replace(a,b)
s=s.replace('sensor reset and reconfiguration to high-active polarity',
            'sensor reset, BUSY until ready and successful retry, high-active polarity')
dest=p/'sim/tb_top_fixed16_controls_ready.v';assert not dest.exists()
dest.write_text(s,encoding='utf-8')
runner=p/'tools/run_sim.ps1';text=runner.read_text(encoding='utf-8-sig')
a="        & $vvp '-i' $output"
assert text.count(a)==1
text=text.replace(a,"        if ($test -like 'tb_top_fixed16*') { $pcmFile = \"sim/build/decoded_pcm_$test.csv\" }\n"+a)
runner.write_text(text,encoding='utf-8-sig')
diagnosis=json.loads((here/'polarity_test_diagnosis.json').read_text(encoding='utf-8'))
log=here/'fixed16_controls_functional.log'
diagnosis['intermediate_followup']={'test':'tb_top_fixed16_controls','passed':False,
    'log':log.name,'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest().upper(),
    'failure':'Expected OK for TOUCH16 while reader was still calibrating; got legitimate ERR,BUSY',
    'final_followup':'tb_top_fixed16_controls_ready explicitly checks BUSY, waits for ready, then checks OK and actual high-active note gates'}
diagnosis['full_run_raw_pcm_retained']=False
diagnosis['full_run_raw_pcm_note']='Generic runner PCM filename was reused by focused followup; original test source, compiled VVP, log and sequential assertion evidence remain. Future fixed16 tests use distinct PCM paths.'
(here/'polarity_test_diagnosis.json').write_text(json.dumps(diagnosis,indent=2)+'\n',encoding='utf-8')
print('Prepared ready/BUSY contract test, preserving both failed logs and using a unique PCM output')
