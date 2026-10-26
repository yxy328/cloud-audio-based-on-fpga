"""Reuse exact frozen synthesis; remove only false paths to deleted hardware."""
from pathlib import Path
import shutil,json
import experiment as exp
here=Path(__file__).resolve().parent
records=[]
for label in ('fixed16_clean','fx_fixed16'):
    old=here/label;new=here/(label+'_sdc')
    assert not new.exists()
    assert json.loads((old/'exit.json').read_text(encoding='utf-8'))['returncode']==1
    assert 'ERROR  (TA2003)' in (old/'build.log').read_text(encoding='utf-8')
    assert exp.manifest(old)==json.loads((old/'sources.json').read_text(encoding='utf-8'))
    shutil.copytree(old,new,ignore=shutil.ignore_patterns('impl','build','build.log','exit.json','sources.json'))
    p=new/'pcm5102_pam8403';(p/'impl').mkdir()
    shutil.copytree(old/'pcm5102_pam8403/impl/gwsynthesis',p/'impl/gwsynthesis')
    sdc=p/'src/PCM5102_UNIFIED.sdc'
    lines=sdc.read_text(encoding='utf-8-sig').splitlines()
    removed=[s for s in lines if '/u_touch_input/input_meta' in s or '/u_touch_mode_input/input_meta' in s]
    assert len(removed)==2 and all(s.startswith('set_false_path') for s in removed)
    sdc.write_text('\n'.join(s for s in lines if s not in removed)+'\n',encoding='utf-8')
    build=p/'tools/build_unified.tcl'
    text=build.read_text(encoding='utf-8-sig');assert text.count('    run all\n')==1
    (p/'tools/pnr_only.tcl').write_text(text.replace('    run all\n','    run pnr\n'),encoding='utf-8')
    exp.write_json(new/'sources.json',exp.manifest(new))
    orig={r['Path']:r['SHA256'] for r in exp.manifest(old)}
    dest={r['Path']:r['SHA256'] for r in exp.manifest(new)}
    changed=[k for k in sorted(orig.keys()|dest.keys()) if orig.get(k)!=dest.get(k)]
    assert changed==['pcm5102_pam8403/src/PCM5102_UNIFIED.sdc','pcm5102_pam8403/tools/pnr_only.tcl'],changed
    files=['PCM5102_UNIFIED.vg','PCM5102_UNIFIED.prj','PCM5102_UNIFIED_syn_rsc.xml']
    assert all(exp.sha(old/'pcm5102_pam8403/impl/gwsynthesis'/k)==exp.sha(p/'impl/gwsynthesis'/k) for k in files)
    record={'label':new.name,'synthesis_origin':label,'rtl_rom_project_identical_to_origin':True,
            'changed_inputs_vs_origin':changed,'removed_stale_false_paths':removed,
            'synthesis_files_sha256':{k:exp.sha(p/'impl/gwsynthesis'/k) for k in files},
            'synthesis_prj_retains_original_candidate_paths':True,
            'new_full_pnr_from_exact_verified_netlist':True,'strategy_changed':False}
    exp.write_json(new/'synthesis_reuse.json',record);records.append(record)
exp.write_json(here/'constraint_repair.json',records)
print('Preserved both failed runs; prepared fresh PnR outputs from identical synthesis, deleting only two stale false paths')
