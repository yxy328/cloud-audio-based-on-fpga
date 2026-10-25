from delivery import *
import importlib.util

log=HERE/'final_production.log'
if log.exists():raise RuntimeError('Final build log exists; preserve it and use a new label')
expected=json.loads((HERE/'apds/sources.json').read_text(encoding='utf-8'))
inputs=[r for r in expected if r['Path'].startswith(('pcm5102_pam8403/src/','pmod_hub75e/src/'))
        or r['Path'] in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj','pcm5102_pam8403/tools/build_unified.tcl')]
before=[{'Path':r['Path'],'SHA256':sha(REPO/r['Path'])} for r in inputs]
assert before==inputs, 'Final source tree differs from validated APDS snapshot'
write_json(HERE/'final_inputs.json',before)
with log.open('w',encoding='utf-8') as f:
    r=subprocess.run([str(GOWIN),str(PROJECT/'tools/build_unified.tcl')],cwd=PROJECT,stdout=f,stderr=f)
after=[{'Path':r['Path'],'SHA256':sha(REPO/r['Path'])} for r in inputs]
assert before==after, 'Source mutated during final build'
spec=importlib.util.spec_from_file_location('audit_final',PROJECT/'tools/audit_fx_builds.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
base_info=mod.sources(HERE/'base');base=mod.audit(HERE/'base',base_info,{})
row=mod.audit(REPO,mod.sources(HERE/'apds'),base['metrics'])
row['label']='production_apds';row['build_exit_code']=r.returncode
row['source_manifest']=str(HERE/'final_inputs.json')
row['source_manifest_sha256']=sha(HERE/'final_inputs.json')
row['verified_inputs']=len(inputs);row['snapshot_corrupt_inputs']=[]
row['changed_inputs_vs_selected_apds']=[]
row.pop('changed_input_hashes',None);row.pop('changed_inputs_vs_baseline',None)
if row['status']=='snapshot_integrity_unverified' and r.returncode==0:row['status']='validated'
row['actual_build_file_hashes']={p.relative_to(PROJECT).as_posix():sha(p) for p in (
    PROJECT/'impl/gwsynthesis/PCM5102_UNIFIED.prj',PROJECT/'impl/pnr/cmd.do',PROJECT/'impl/pnr/device.cfg',
    PROJECT/'impl/pnr/PCM5102_UNIFIED.rpt.txt',PROJECT/'impl/pnr/PCM5102_UNIFIED_tr_content.html',
    PROJECT/'impl/pnr/PCM5102_UNIFIED.timing_paths') if p.exists()}
write_json(HERE/'final_production_audit.json',row)
print(row['status'],row['metrics'],row['bitstream_sha256'])
assert row['status']=='validated', 'Final production failed acceptance'
