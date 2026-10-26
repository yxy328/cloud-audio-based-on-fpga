"""Integrate the validated score target design with the current CLS baseline."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
REPO = PROJECT.parent
PRIOR = PROJECT / 'reports/performance_experience_20261026'
CLS = PROJECT / 'reports/hc05_cls_first_20261026'
GOWIN = Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
IVERILOG = Path('C:/iverilog/bin/iverilog.exe')
VVP = IVERILOG.with_name('vvp.exe')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def manifest(root):
    names = [p for folder in ('pcm5102_pam8403/src', 'pmod_hub75e/src', 'build_inputs')
             for p in sorted((root/folder).rglob('*')) if p.is_file()]
    names += [root/name for name in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj',
                                    'pcm5102_pam8403/tools/build_unified.tcl')]
    return [{'Path': p.relative_to(root).as_posix(), 'SHA256': sha(p)} for p in names]

def prepare():
    assert not (HERE/'baseline').exists(), 'Do not overwrite frozen evidence'
    record = json.loads((CLS/'integration.json').read_text(encoding='utf-8'))
    assert all(sha(REPO/r['Path']) == r['SHA256'] for r in record['production_inputs'])
    audit = json.loads((CLS/'reply_place1/audit.json').read_text(encoding='utf-8'))
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs') == audit['bitstream_sha256']
    assert all(sha(PROJECT/name) == value for name,value in audit['actual_build_file_hashes'].items())
    root = HERE/'baseline'
    for folder in ('src', 'tools', 'sim'):
        shutil.copytree(PROJECT/folder, root/PROJECT.name/folder,
                        ignore=shutil.ignore_patterns('build', '__pycache__'))
    shutil.copy2(PROJECT/'PCM5102_UNIFIED.gprj',root/PROJECT.name/'PCM5102_UNIFIED.gprj')
    shutil.copytree(REPO/'pmod_hub75e/src',root/'pmod_hub75e/src')
    shutil.copytree(CLS/'reply_place1/build_inputs',root/'build_inputs')
    save(root/'sources.json',manifest(root))
    backup=HERE/'production_before'
    shutil.copytree(PROJECT/'impl',backup/'impl')
    app=PROJECT/'android_app'
    for folder in ('app','core_test','third_party'):
        shutil.copytree(app/folder,HERE/'app_before'/folder)
    for name in ('test-core.ps1','build-apk.ps1'):
        shutil.copy2(app/name,HERE/'app_before'/name)
    shutil.copytree(HERE/'app_before',HERE/'app_stage')
    (HERE/'app_stage/tools').mkdir()
    shutil.copy2(app/'tools/debug.keystore',HERE/'app_stage/tools/debug.keystore')
    shutil.copy2(app/'dist/FPGA-Music-Unified.apk',backup/'rollback_app.apk')
    save(HERE/'freeze.json',{'production_inputs':record['production_inputs'],
         'baseline_audit':audit,'gowin_sha256':sha(GOWIN),
         'app_inputs':[{'Path':p.relative_to(HERE/'app_before').as_posix(),'SHA256':sha(p)}
                       for p in sorted((HERE/'app_before').rglob('*')) if p.is_file()],
         'rollback_apk_sha256':sha(backup/'rollback_app.apk')})
    target=HERE/'candidate'
    shutil.copytree(root,target,ignore=shutil.ignore_patterns('sources.json'))
    merge_feature()

def merge_feature():
    target=HERE/'candidate'
    merge_inputs=HERE/'merge_inputs'
    merge_inputs.mkdir(exist_ok=True)
    changes=[]
    # Merge only the prior D feature delta; keep the new reply mux and place1.
    for folder in ('src','tools'):
        for old in sorted((PRIOR/'base'/PROJECT.name/folder).rglob('*')):
            if not old.is_file(): continue
            relative=old.relative_to(PRIOR/'base')
            new=PRIOR/'score_bend_v1'/relative
            if not new.exists() or sha(old)==sha(new): continue
            current=target/relative
            inputs=[]
            for role,path in [('current',HERE/'baseline'/relative),('base',old),('feature',new)]:
                normalized=merge_inputs/(role+'_'+current.name)
                normalized.write_text(path.read_text(encoding='utf-8-sig'),encoding='utf-8',newline='\n')
                inputs.append(str(normalized))
            result=subprocess.run(['git','merge-file','-p',*inputs],capture_output=True)
            assert result.returncode==0,(str(relative),result.stderr.decode(errors='replace'))
            current.write_bytes(result.stdout)
            changes.append(relative.as_posix())
    # Keep ordinary legacy benches explicit about their disabled optional input.
    p=target/PROJECT.name
    for path in (p/'sim').rglob('*.v'):
        if path.name=='voice_pitch_scaler_reference.v': continue
        text=path.read_text(encoding='utf-8-sig')
        if 'downloadable_song #' in text and '.arg3(' not in text:
            text=text.replace('.arg0(',".arg3(16'd0),.score_min(16'd8192),.score_max(16'd32768),.arg0(")
        if re.search(r'\b(?:voice_pitch_scaler|fsr_pitch_scaler)\s+(?:#|\w+\s*\()',text):
            # Add ports to DUT instances, never the older reference module.
            text=re.sub(r'(\b(?:voice_pitch_scaler|fsr_pitch_scaler)\s+(?:#\([\s\S]*?\)\s*)?\w+\s*\()(?!\.score_ratio)',
                        lambda m:m[1]+".score_ratio(16'd0),.score_keys(7'd0),",text)
        if text!=path.read_text(encoding='utf-8-sig'):
            path.write_text(text,encoding='utf-8',newline='\n')
    for path in (PRIOR/'score_bend_v1'/PROJECT.name/'sim').glob('tb_score*.v'):
        if path.name=='tb_top_score_config.v':continue
        shutil.copy2(path,p/'sim'/path.name)
    # The current baseline already includes this corrected legacy contract.
    shutil.copy2(CLS/'baseline'/PROJECT.name/'sim/tb_hc05_download_current.v',p/'sim')
    save(target/'merge.json',{'feature_delta_from':'performance_experience_20261026/score_bend_v1',
                            'changed_production_files':changes,'physical_strategy':'place1/route0/fan23'})
    print('Frozen current 11387 CLS baseline; merged D files:',changes,flush=True)

def build(label):
    root=HERE/label
    assert not (root/'build.log').exists()
    before=manifest(root);save(root/'sources.json',before)
    with (root/'build.log').open('w',encoding='utf-8') as log:
        result=subprocess.run([str(GOWIN),str(root/PROJECT.name/'tools/build_unified.tcl')],
                              cwd=root/PROJECT.name,stdout=log,stderr=log)
    save(root/'exit.json',{'returncode':result.returncode,'inputs_unchanged':manifest(root)==before})
    print(label,'build exit',result.returncode,flush=True)

def audit(label):
    spec=importlib.util.spec_from_file_location('audit_fx',PROJECT/'tools/audit_fx_builds.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    base=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))['baseline_audit']
    root=HERE/label
    result=module.audit(root,module.sources(HERE/'baseline'),base['metrics'])
    log=(root/'build.log').read_text(encoding='utf-8',errors='replace')
    unplaced=re.search(r'(\d+) LUT\(s\).*?unPlaced',log)
    if unplaced:result['status']='placement_failed'
    result['unplaced_LUT_equivalents']=int(unplaced[1]) if unplaced else 0
    result['gowin_sha256']=sha(GOWIN)
    result['actual_build_file_hashes']={name:sha(root/PROJECT.name/name) for name in (
        'impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do','impl/pnr/device.cfg',
        'impl/pnr/PCM5102_UNIFIED.rpt.txt','impl/pnr/PCM5102_UNIFIED_tr_content.html',
        'impl/pnr/PCM5102_UNIFIED.timing_paths') if (root/PROJECT.name/name).exists()}
    result['cls_free']=result['metrics'].get('CLS',{}).get('capacity',0)-result['metrics'].get('CLS',{}).get('used',0)
    result['admitted_physical']=result['status']=='validated' and result['cls_free']>=35
    save(root/'audit.json',result)
    print(json.dumps({k:result[k] for k in ('status','metrics','delta_vs_baseline','cls_free','admitted_physical','timing')},indent=2))

def tests(label,names,run_name):
    p=HERE/label/PROJECT.name
    out=HERE/label/'tests'/run_name
    assert not out.exists();out.mkdir(parents=True)
    rtl=list((p/'src').glob('*.v'))+[HERE/label/'pmod_hub75e/src/ttp229_gpio_input.v']
    rtl+=list((p/'sim').glob('*model*.v'))+[p/'sim/i2s_pcm_monitor.v']
    rtl+=list((p/'sim/reference').glob('*.v'))
    results=[]
    for name in names:
        image=out/(name+'.vvp');log=out/(name+'.log')
        with log.open('w',encoding='utf-8') as stream:
            comp=subprocess.run([str(IVERILOG),'-g2001','-s',name,'-o',str(image),
                                 str(p/'sim'/(name+'.v')),*map(str,rtl)],cwd=p,stdout=stream,stderr=stream)
            code=comp.returncode
            if code==0:
                (p/'sim/build').mkdir(exist_ok=True)
                sim=subprocess.run([str(VVP),'-i',str(image),'+pcm_csv=sim/build/'+name+'.csv'],
                                   cwd=p,stdout=stream,stderr=stream,timeout=1800)
                code=sim.returncode
        text=log.read_text(encoding='utf-8',errors='replace')
        passed=code==0 and bool(re.search(r'^PASS',text,re.M)) and 'FATAL' not in text
        result={'test':name,'passed':passed,'exit_code':code,'log':str(log),'sha256':sha(log),
                'pass_lines':re.findall(r'^PASS[^\r\n]*',text,re.M)}
        results.append(result);save(out/'results.json',results)
        print(name,'PASS' if passed else 'FAILED',flush=True)
        if not passed:print(text[-3000:]);raise SystemExit(1)

if __name__=='__main__':
    command=sys.argv[1]
    if command=='prepare':prepare()
    elif command=='merge':merge_feature()
    elif command=='build':build(sys.argv[2])
    elif command=='audit':audit(sys.argv[2])
    elif command=='test':tests(sys.argv[2],sys.argv[4:],sys.argv[3])
