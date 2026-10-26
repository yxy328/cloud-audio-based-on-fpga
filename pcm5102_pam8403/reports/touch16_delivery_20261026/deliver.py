"""Integrate the measured fixed16 candidate, preserving the previous release."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parent.parent
REPO=PROJECT.parent
ASSESS=PROJECT/'reports/touch16_reverb_20261026'
CANDIDATE=ASSESS/'fixed16_clean_sdc'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def save(name,obj):(HERE/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def prepare():
    assert not (HERE/'freeze.json').exists()
    prior=json.loads((PROJECT/'reports/fx_delivery_20261025/final_inputs.json').read_text(encoding='utf-8'))
    changed=[r['Path'] for r in prior if sha(REPO/r['Path'])!=r['SHA256']]
    assert not changed,changed
    for name,args in [('starting_status.txt',['status','--porcelain=v1']),('starting_diff.patch',['diff','--binary','HEAD'])]:
        with (HERE/name).open('wb') as f:subprocess.run(['git','-C',str(REPO),*args],stdout=f,check=True)
    shutil.copytree(PROJECT/'impl/pnr',HERE/'previous_default/pnr')
    shutil.copytree(PROJECT/'impl/gwsynthesis',HERE/'previous_default/gwsynthesis')
    shutil.copy2(PROJECT/'android_app/dist/FPGA-Music-Unified.apk',HERE/'previous_default/FPGA-Music-Unified-Code25.apk')
    original=[]
    for folder in ('src','sim','android_app/app/src','android_app/core_test'):
        for p in (PROJECT/folder).rglob('*'):
            if p.is_file() and 'build' not in p.relative_to(PROJECT).parts:
                original.append({'path':p.relative_to(PROJECT).as_posix(),'sha256':sha(p)})
    save('starting_inputs.json',original)
    save('freeze.json',{'date':'2026-10-26','git_head':subprocess.check_output(['git','-C',str(REPO),'rev-parse','HEAD'],text=True).strip(),
        'baseline_inputs_verified':len(prior),'candidate':'fixed16_clean_sdc',
        'old_default_sha256':sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs'),
        'old_apk_sha256':sha(PROJECT/'android_app/dist/FPGA-Music-Unified.apk'),
        'scope':'Production fixed16 RTL + matching App; existing effects retained; no hardware programming'})
    for name in ('src/hc05_keymap.v','src/top.v','src/PCM5102_UNIFIED.sdc'):
        shutil.copy2(CANDIDATE/'pcm5102_pam8403'/name,PROJECT/name)
    # Keep the full spectrum check; repair only the intentional mode changes
    # and model reconfiguration/ready handling diagnosed in the assessment.
    s=(ASSESS/'fixed16_clean/pcm5102_pam8403/sim/tb_top_fixed16.v').read_text(encoding='utf-8')
    s=s.replace('module tb_top_fixed16;','module tb_top_touch16;')
    s=s.replace('reg model_high=0;','reg model_high=0;\n    reg sensor_reset=0;')
    s=s.replace('ttp229_model chip(.rst_n(dut.resetn),','ttp229_model chip(.rst_n(dut.resetn && !sensor_reset),')
    old='''        transact("SERIAL,1\\n",9,{"OK",8'd13,"\\n"});model_high=1;
        transact("TOUCH,16\\n",9,{"OK",8'd13,"\\n"});wait(dut.touch_ready);frames(4);'''
    new='''        sensor_reset=1;
        transact("SERIAL,1\\n",9,{"OK",8'd13,"\\n"});model_high=1;
        wait(dut.u_touch_serial.state==1);
        @(negedge clk);sensor_reset=0;
        transact("TOUCH,16\\n",9,{"ERR,BUSY",8'd13,"\\n"});
        wait(dut.touch_ready);frames(4);
        transact("TOUCH,16\\n",9,{"OK",8'd13,"\\n"});frames(4);'''
    assert s.count(old)==1;s=s.replace(old,new)
    s=s.replace('start_sample=monitor.pcm_count;','start_sample=monitor.pcm_count;\n        $display("SPECTRUM_START sample=%0d",start_sample);')
    s=s.replace('amp=2*$sqrt(co*co+si*si)/weight;',
        'amp=2*$sqrt(co*co+si*si)/weight;\n            $display("KEY_SPECTRUM key=%0d amplitude=%f",j+1,amp);')
    s=s.replace('both polarities','sensor reset, BUSY until ready, both polarities')
    (PROJECT/'sim/tb_top_touch16.v').write_text(s,encoding='utf-8')
    print('Integrated measured three-file fixed16 candidate and full 8192-sample integration test')
def build():
    prior=json.loads((PROJECT/'reports/fx_delivery_20261025/final_inputs.json').read_text(encoding='utf-8'))
    inputs=[{'Path':r['Path'],'SHA256':sha(REPO/r['Path'])} for r in prior]
    changed=[r['Path'] for r,o in zip(inputs,prior) if r['SHA256']!=o['SHA256']]
    assert sorted(changed)==sorted('pcm5102_pam8403/'+s for s in ('src/hc05_keymap.v','src/top.v','src/PCM5102_UNIFIED.sdc')),changed
    for r in inputs:
        p=CANDIDATE/r['Path']
        if p.exists() and r['Path']!='pcm5102_pam8403/src/hc05_keymap.v':assert sha(p)==r['SHA256'],r['Path']
    save('production_inputs.json',inputs)
    log=HERE/'production_build.log';assert not log.exists()
    gowin='E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe'
    with log.open('w',encoding='utf-8') as f:
        result=subprocess.run([gowin,str(PROJECT/'tools/build_unified.tcl')],cwd=PROJECT,stdout=f,stderr=f)
    save('build_exit.json',{'returncode':result.returncode,'inputs_unchanged':all(sha(REPO/r['Path'])==r['SHA256'] for r in inputs)})
    print('Production build exit',result.returncode);sys.exit(result.returncode)
if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare()
    elif sys.argv[1]=='build':build()
