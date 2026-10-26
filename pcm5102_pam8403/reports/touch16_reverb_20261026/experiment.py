"""Fixed-16 resource assessment; production RTL, App and bitstream stay untouched."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, shutil, subprocess, sys

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parent.parent
REPO=PROJECT.parent
PRIOR=PROJECT/'reports/fx_delivery_20261025'
GOWIN=Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def write_json(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def manifest(root):
    rows=[]
    for p in sorted(root.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(root).as_posix()
        if rel.startswith(('pcm5102_pam8403/src/','pmod_hub75e/src/','build_inputs/')) or rel in (
            'pcm5102_pam8403/PCM5102_UNIFIED.gprj','pcm5102_pam8403/tools/build_unified.tcl','pcm5102_pam8403/tools/pnr_only.tcl'):
            rows.append({'Path':rel,'SHA256':sha(p)})
    return rows

def prepare():
    current=json.loads((PRIOR/'final_inputs.json').read_text(encoding='utf-8'))
    differences=[r['Path'] for r in current if not (REPO/r['Path']).exists() or sha(REPO/r['Path'])!=r['SHA256']]
    assert not differences,differences
    prior_final=json.loads((PRIOR/'final_production_audit.json').read_text(encoding='utf-8'))
    assert prior_final['status']=='validated'
    assert sha(GOWIN)==json.loads((PRIOR/'freeze.json').read_text(encoding='utf-8'))['gowin_sha256']
    artifact_differences=[name for name,digest in prior_final['actual_build_file_hashes'].items()
        if not (PROJECT/name).exists() or sha(PROJECT/name)!=digest]
    assert not artifact_differences,artifact_differences
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==prior_final['bitstream_sha256']
    assert not (HERE/'base').exists()
    base=HERE/'base';p=base/PROJECT.name;p.mkdir(parents=True)
    for folder in ('src','tools','sim'):
        shutil.copytree(PROJECT/folder,p/folder,ignore=shutil.ignore_patterns('build','__pycache__'))
    shutil.copy2(PROJECT/'PCM5102_UNIFIED.gprj',p/'PCM5102_UNIFIED.gprj')
    shutil.copytree(REPO/'pmod_hub75e/src',base/'pmod_hub75e/src')
    shutil.copytree(REPO/'pmod_hub75e/sim',base/'pmod_hub75e/sim',ignore=shutil.ignore_patterns('build'))
    (base/'build_inputs').mkdir()
    for name in ('PCM5102_UNIFIED_process_config.json','project_process_config.json'):
        shutil.copy2(PROJECT/'impl'/name,base/'build_inputs'/name)
    (p/'impl').mkdir()
    shutil.copytree(PROJECT/'impl/pnr',p/'impl/pnr')
    shutil.copytree(PROJECT/'impl/gwsynthesis',p/'impl/gwsynthesis')
    write_json(base/'sources.json',manifest(base))
    for filename,args in [('starting_status.txt',['status','--porcelain=v1']),('starting_diff.patch',['diff','--binary','HEAD'])]:
        with (HERE/filename).open('wb') as f:subprocess.run(['git','-C',str(REPO),*args],stdout=f,check=True)
    for label in ('fixed16','fx_fixed16'):
        root=HERE/label
        shutil.copytree(base,root,ignore=shutil.ignore_patterns('impl','build','sources.json','*.gprj.user'))
        (root/PROJECT.name/'impl').mkdir()
        keymap=root/PROJECT.name/'src/hc05_keymap.v'
        s=keymap.read_text(encoding='utf-8-sig')
        replacements={
            'output reg touch_mode16,panic,serial_active_high,':'output wire touch_mode16,\n    output reg panic,serial_active_high,',
            'touch_mode16<=DEFAULT_TOUCH_MODE16!=0;serial_active_high<=0;':'serial_active_high<=0;',
            '1:if(accumulator!=8 && accumulator!=16)result(2);':'1:if(accumulator!=16)result(2);',
            'else begin touch_mode16<=accumulator==16;result(0);end':'else result(0);',
        }
        for a,b in replacements.items():
            assert s.count(a)==1,a
            s=s.replace(a,b)
        end=s.index(');')+2
        s=s[:end]+"\n    // Assessment candidate: only the serial sixteen-key interface exists.\n    assign touch_mode16=1'b1;\n"+s[end:]
        keymap.write_text(s,encoding='utf-8')
        if label=='fx_fixed16':
            proto=PRIOR/'fx_apds/pcm5102_pam8403/src/audio_fx_minproto.v'
            shutil.copy2(proto,root/PROJECT.name/'src/audio_fx_minproto.v')
            top=root/PROJECT.name/'src/top.v';s=top.read_text(encoding='utf-8-sig')
            a='audio_effects #(.ADDRESS_BITS(12)) u_effects ('
            assert s.count(a)==1
            s=s.replace(a,'audio_fx_minproto u_effects (\n        .mask(tuning_ratio[2:0]),.reverb_preset(gesture_timbre[1:0]),.overrun(),')
            a='        .mode(perf_replay ? perf_state[484 +: 2] : effect_mode),\n'
            assert s.count(a)==1;s=s.replace(a,'')
            a='((perf_replay ? perf_state[484 +: 2] : effect_mode)==0 ? dry_audio_sample : effect_sample)'
            assert s.count(a)==1;s=s.replace(a,'(tuning_ratio[2:0]==0 ? dry_audio_sample : effect_sample)')
            top.write_text(s,encoding='utf-8')
            prj=root/PROJECT.name/'PCM5102_UNIFIED.gprj'
            s=prj.read_text(encoding='utf-8-sig').replace('</FileList>',
                '<File path="src/audio_fx_minproto.v" type="file.verilog" enable="1"/></FileList>')
            prj.write_text(s,encoding='utf-8')
        write_json(root/'sources.json',manifest(root))
    write_json(HERE/'freeze.json',{
        'assessment_date':'2026-10-26','baseline_inputs_verified':len(current),
        'baseline_reuses_existing_complete_production_build':True,
        'baseline_report':str(PROJECT/'impl/pnr/PCM5102_UNIFIED.rpt.txt'),
        'prior_audit':str(PRIOR/'final_production_audit.json'),
        'all_prior_actual_build_artifact_hashes_match':True,
        'gowin_sha256':sha(GOWIN),'strategy':{'place':2,'route':0,'maxfan':23},
        'production_fs_sha256':sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs'),
        'production_keymap_sha256':sha(PROJECT/'src/hc05_keymap.v'),
        'production_rtl_modified':False,
        'candidate_changes':'hc05_keymap fixed wire mode16=1, reject TOUCH8, remove mode writes; FX variant adds previous unchanged minimum prototype',
        'eight_key_removal_does_not_remove_eight_synth_voices':True})
    print('Current baseline verified; prepared fixed16 and fx_fixed16 only in isolated directories')

def build(label,pnr_only=False):
    root=HERE/label;p=root/PROJECT.name
    assert not (root/'build.log').exists(),'Use a new label instead of overwriting evidence'
    assert manifest(root)==json.loads((root/'sources.json').read_text(encoding='utf-8'))
    with (root/'build.log').open('w',encoding='utf-8') as f:
        script='pnr_only.tcl' if pnr_only else 'build_unified.tcl'
        r=subprocess.run([str(GOWIN),str(p/'tools'/script)],cwd=p,stdout=f,stderr=f)
    write_json(root/'exit.json',{'returncode':r.returncode});print(label,'exit',r.returncode)
    sys.exit(r.returncode)

def audit():
    spec=importlib.util.spec_from_file_location('audit',PROJECT/'tools/audit_fx_builds.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    info=mod.sources(HERE/'base');base=mod.audit(HERE/'base',info,{})
    # Frozen baseline outputs intentionally retain the verified production paths.
    original=json.loads((PRIOR/'final_production_audit.json').read_text(encoding='utf-8'))
    base.update({k:original[k] for k in ('metrics','status','unrouted_nets','timing','strategy','bitstream_sha256')})
    base['baseline_output_origin']='Verified production build; copied reports retain original paths'
    labels=('fixed16','fixed16_clean','fx_fixed16','fixed16_clean_sdc','fx_fixed16_sdc')
    rows=[base]+[mod.audit(HERE/l,info,base['metrics']) for l in labels if (HERE/l).exists()]
    for row in rows:
        p=HERE/row['label']/PROJECT.name
        files=['impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do',
               'impl/pnr/PCM5102_UNIFIED.rpt.txt','impl/pnr/PCM5102_UNIFIED_tr_content.html',
               'impl/pnr/PCM5102_UNIFIED.timing_paths','impl/pnr/device.cfg',
               'impl/PCM5102_UNIFIED_process_config.json']
        row['actual_build_file_hashes']={name:sha(p/name) for name in files if (p/name).is_file()}
        if row['label']!='base':
            row['canonical_input_manifest_exact']=manifest(HERE/row['label'])==json.loads((HERE/row['label']/'sources.json').read_text(encoding='utf-8'))
            if not row['canonical_input_manifest_exact']:row['status']='snapshot_integrity_failed'
    write_json(HERE/'build_audit.json',rows)
    for r in rows:
        t=r.get('timing') or {}
        print(r['label'],r['status'],{k:v['used'] for k,v in r['metrics'].items()},
              r['delta_vs_baseline'],'unrouted',r['unrouted_nets'],
              'violations',t.get('setup_violated_endpoints'),t.get('hold_violated_endpoints'),
              'WNS',(t.get('setup_raw_worst_path') or {}).get('slack_ns'),
              'corrupt',r['snapshot_corrupt_inputs'])

if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare()
    elif sys.argv[1]=='build':build(sys.argv[2])
    elif sys.argv[1]=='pnr':build(sys.argv[2],True)
    elif sys.argv[1]=='audit':audit()
