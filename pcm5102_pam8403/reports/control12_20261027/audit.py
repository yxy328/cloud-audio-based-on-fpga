"""Collect reproducible evidence without changing default inputs or artifacts."""
from pathlib import Path
import hashlib, json, re, importlib.util, difflib

R=Path(__file__).resolve().parent
ROOT=R.parents[2]
BASE=ROOT/'pcm5102_pam8403'
P=R/'candidate/pcm5102_pam8403'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def save(name,value):(R/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

spec=importlib.util.spec_from_file_location('build_audit',BASE/'tools/audit_fx_builds.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
base_report=(BASE/'impl/pnr/PCM5102_UNIFIED.rpt.txt').read_text(encoding='utf-8',errors='replace')
baseline={}
for name in m.METRICS:
    hit=re.search(rf'^\s*{name}\s+\|\s*([\d.]+)/([\d.]+)',base_report,re.M)
    if hit:baseline[name]={'used':float(hit[1]),'capacity':float(hit[2])}
if (R/'baseline_resources.json').exists():
    baseline=json.loads((R/'baseline_resources.json').read_text(encoding='utf-8'))
else:save('baseline_resources.json',baseline)
records=[]
for snapshot in sorted((P/'sim/build/unified').iterdir()):
    if not snapshot.is_dir():continue
    row=m.audit(snapshot,m.sources(snapshot),baseline)
    row['label']=snapshot.name
    row['source_directory']=str(snapshot)
    log_path=snapshot/'build.log'
    if not log_path.exists():log_path=snapshot/'pnr.log'
    log=log_path.read_text(encoding='utf-8-sig',errors='replace') if log_path.exists() else ''
    row['synthesis_resource_failure']=re.findall(r'ERROR \(RP0006\).*',log)
    pnr_report=snapshot/'pcm5102_pam8403/impl/pnr/PCM5102_UNIFIED.rpt.txt'
    if pnr_report.exists():
        pnr_text=pnr_report.read_text(encoding='utf-8',errors='replace')
        unplaced=re.search(r"'(\d+) LUT\(s\).*?unPlaced",pnr_text)
        if unplaced:
            row['status']='placement_failed'
            row['unplaced_lut_equivalents']=int(unplaced[1])
    if row['synthesis_resource_failure']:row['status']='synthesis_resource_failed'
    if 'CLS' in row['metrics']:
        row['cls_remaining']=row['metrics']['CLS']['capacity']-row['metrics']['CLS']['used']
        row['cls_safety_reserve']=35
    row['default_hardware_admissible']=row['status']=='validated' and row.get('cls_remaining',0)>=35
    if snapshot.name=='control12_decode':
        row['status']='discarded_before_completion'
        row['reason']='Response target tag needed to be held throughout the new decoder; fixed and regressed in decode_final.'
    if snapshot.name=='control12_step_ram':
        row['status']='discarded_before_completion'
        row['reason']='First RAM prototype required corrected slow-read prefetch and seven-step legacy capture length. Fixed and regressed in step_ram_final.'
    rpt=snapshot/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn.rpt.html'
    if rpt.exists():
        text=rpt.read_text(encoding='utf-8',errors='replace')
        h=re.search(r'<td>Logic</td>\s*<td>(.*?)</td>',text,re.S)
        row['synthesis_logic_report']=h[1] if h else None
    row['current_candidate_inputs_match']=all(
        not name.startswith('pcm5102_pam8403/src/') or (P/name.split('/',1)[1]).exists() and sha(P/name.split('/',1)[1])==digest
        for name,digest in m.sources(snapshot)['entries'].items())
    records.append(row)
save('build_results.json',{'baseline':baseline,'builds':records})
frozen=json.loads((R/'freeze.json').read_text(encoding='utf-8'))
changed=[row['path'] for row in frozen if sha(ROOT/row['path'])!=row['sha256']]
production_check={'checked_inputs':len(frozen),'changed':changed,
    'default_apk_sha256':sha(BASE/'android_app/dist/FPGA-Music-Unified.apk'),
    'default_bitstream_sha256':sha(BASE/'impl/pnr/PCM5102_UNIFIED.fs')}
save('production_after_promotion.json' if (R/'release.json').exists() else 'production_unchanged.json',production_check)
manifest=[];patch=[]
paths=list((P/'src').glob('*'))+[P/'tools/generate_hc05_decoder.py',P/'tools/generate_hc05_replies.py',P/'tools/run_sim.ps1']
paths+=list((P/'sim').glob('tb_control12*.v'))
paths+=[P/'sim/tb_hc05_code39_equivalence.v',P/'sim/tb_hc05_download_fixed16.v']+list((P/'sim/reference').glob('*code39*'))
paths+=[P/'sim'/name for name in ['tb_performance_take.v','tb_take_atomic.v','tb_fx_take_atomic_528.v']]
for candidate in paths:
    if not candidate.is_file():continue
    rel=candidate.relative_to(P);original=BASE/rel
    if original.exists() and sha(original)==sha(candidate):continue
    manifest.append({'path':str(rel),'sha256':sha(candidate)})
    old=original.read_text(encoding='utf-8').splitlines(True) if original.exists() else []
    patch+=difflib.unified_diff(old,candidate.read_text(encoding='utf-8').splitlines(True),
        fromfile='a/pcm5102_pam8403/'+rel.as_posix() if original.exists() else '/dev/null',
        tofile='b/pcm5102_pam8403/'+rel.as_posix())
save('candidate_inputs.json',manifest)
(R/'candidate.patch').write_text(''.join(patch),encoding='utf-8')
app=R/'app_candidate'
app_files=[p for p in (app/'app').rglob('*') if p.is_file()]
save('app_inputs.json',[{'path':str(p.relative_to(app)),'sha256':sha(p)} for p in app_files])
app_patch=[]
for candidate in app_files+list((app/'core_test').glob('*.java'))+[app/'test-core.ps1']:
    if candidate.suffix not in ('.java','.xml','.gradle','.ps1'):continue
    rel=candidate.relative_to(app);original=BASE/'android_app'/rel
    if original.exists() and sha(original)==sha(candidate):continue
    old=original.read_text(encoding='utf-8').splitlines(True) if original.exists() else []
    app_patch+=difflib.unified_diff(old,candidate.read_text(encoding='utf-8').splitlines(True),
        fromfile='a/pcm5102_pam8403/android_app/'+rel.as_posix() if original.exists() else '/dev/null',
        tofile='b/pcm5102_pam8403/android_app/'+rel.as_posix())
(R/'app_candidate.patch').write_text(''.join(app_patch),encoding='utf-8')
save('verification.json',{
    'logs':{name:[line for line in (R/name).read_text(encoding='utf-8-sig',errors='replace').splitlines() if line.startswith('PASS')]
        for name in ['legacy_regression.log','compact_validation_tests.log','control12_units.log','take_legacy.log','control12_protocol.log','control12_top_final.log','control12_top_decode_final.log','control12_dense.log','score_decode_tests_fixed.log','control12_take_top_final.log','map_reply_tests.log','trusted_tests.log','shared_reply_top_tests.log','shared_reply_take_top_production.log','code39_differential.log','fixed16_download.log','app_core.log','app_core_final.log','app_control12.log','step_ram_regression.log','packed_steps_equivalence.log','packed_steps_top.log','packed_steps_legacy.log','touch_width_equivalence.log','width_final_top.log','width_final_units.log','width_final_compat.log'] if (R/name).exists()},
    'candidate_apk':{'path':str(app/'dist/FPGA-Music-Control12-Candidate-Code40.apk'),'sha256':sha(app/'dist/FPGA-Music-Control12-Candidate-Code40.apk')},
    'board_programmed':False,'app_installed':False})
print(json.dumps({'unchanged_inputs':len(frozen),'changed_inputs':changed,
    'builds':[{k:r.get(k) for k in ['label','status','metrics','synthesis_resource_failure']} for r in records]},ensure_ascii=False))
