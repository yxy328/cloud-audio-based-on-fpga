"""Frozen netlist PnR-only retry: placement strategy 0 -> 1, no RTL edits."""
from pathlib import Path
import hashlib,json,shutil
H=Path(__file__).resolve().parent
P=H.parents[1]
PREVIOUS=P/'reports/local_reuse_20261025'
OLD=P/'sim/build/unified/engine_share_base_20261024'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def dump(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2),encoding='utf-8')
origins={'baseline_place1':OLD,'apds_serial_place1':PREVIOUS/'apds_serial','flash_rotate_place1':PREVIOUS/'flash_rotate'}
freeze={}
for name,origin in origins.items():
    dst=H/name;dst.mkdir(exist_ok=False)
    rows=json.loads((origin/'sources.json').read_text(encoding='utf-8-sig'))
    for row in rows:
        rel=Path(row['Path'].replace('\\','/'))
        assert not rel.is_absolute() and '..' not in rel.parts
        assert sha(origin/rel)==row['SHA256'].upper(),(name,str(rel))
        p=dst/rel;p.parent.mkdir(exist_ok=True,parents=True);shutil.copyfile(origin/rel,p)
        assert sha(p)==row['SHA256'].upper()
    dump(dst/'sources.json',rows)
    src_syn=origin/'pcm5102_pam8403/impl/gwsynthesis'
    dst_syn=dst/'pcm5102_pam8403/impl/gwsynthesis'
    shutil.copytree(src_syn,dst_syn)
    syn_hashes={p.name:sha(p) for p in src_syn.iterdir() if p.is_file()}
    assert all(sha(dst_syn/p)==v for p,v in syn_hashes.items())
    script=dst/'pcm5102_pam8403/tools/pnr_only.tcl'
    text=(dst/'pcm5102_pam8403/tools/build_unified.tcl').read_text(encoding='utf-8-sig')
    assert text.count('-place_option 0')==1 and text.count('run all')==1
    text=text.replace('-place_option 0','-place_option 1').replace('run all','run pnr')
    script.write_text(text,encoding='utf-8')
    freeze[name]={'origin':str(origin),'source_manifest_sha256':sha(origin/'sources.json'),'verified_source_inputs':len(rows),
      'synthesis_inputs':syn_hashes,'pnr_only_tcl_sha256':sha(script),
      'only_physical_factor_changed':'place_option 0 -> 1; same synthesized netlist; route_option 0, route_maxfan 23'}
gw=Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
shutil.copyfile(PREVIOUS/'audit_helpers.py',H/'audit_helpers.py')
dump(H/'freeze.json',{'tool':str(gw),'tool_sha256':sha(gw),'builds':freeze,
  'scope':'Experiment only; no production files or delivered bitstreams overwritten.'})
prod=[]
for row in json.loads((PREVIOUS/'production_before.json').read_text(encoding='utf-8')):
    p=P.parent/row['Path']
    if p.exists():prod.append({'Path':row['Path'],'SHA256':sha(p)})
dump(H/'production_before.json',prod)
print('Prepared three independently verified PnR-only retries (98 source inputs each).')
