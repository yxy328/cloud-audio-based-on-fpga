"""Collect measured resources, full-build route/timing evidence and all hashes."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET,importlib.util,re,shutil
H=Path(__file__).resolve().parent
P=H.parents[1]; ROOT=P.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def dump(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2),encoding='utf-8')
helper=H/'audit_helpers.py'
if not helper.exists():shutil.copyfile(P/'tools/audit_fx_builds.py',helper)
spec=importlib.util.spec_from_file_location('audit_helpers',helper)
A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A)
OLD=P/'sim/build/unified/engine_share_base_20261024'
bs=A.sources(OLD);assert not bs['corrupt']
baseline=A.audit(OLD,bs,{})
assert baseline['status']=='validated',baseline['status']
builds=[baseline]
local={}
def hierarchy(path):
    out={}
    def visit(n,prefix):
        path=prefix+'/'+n.attrib['name']
        out[path]={k:int(n.attrib.get(k,0)) for k in ['Lut','Alu','Register']}
        for c in n:visit(c,path)
    visit(ET.parse(path).getroot(),'')
    return out
hb=hierarchy(OLD/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml')
hd={}
for name in ['baseline','apds_serial','flash_rotate']:
    snap=H/name
    si=A.sources(snap);assert not si['corrupt'],si['corrupt']
    if name!='baseline':
        record=A.audit(snap,bs,baseline['metrics'])
        record['target_cls_reduction']=500
        record['meets_resource_route_timing_target']=record['status']=='validated' and record['delta_vs_baseline'].get('CLS',0)<=-500
        record['production_integrated']=False
        record['candidate_disposition']=('requires_integration_regression' if record['meets_resource_route_timing_target'] else
          'eliminated_below_stage_resource_target' if record['status']=='validated' else
          'eliminated_routing_failure' if record['status']=='routing_failed' else
          'eliminated_timing_failure' if record['status']=='timing_failed' else 'pending')
        effective={}
        for rel in ['impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do','impl/pnr/device.cfg']:
            a=OLD/'pcm5102_pam8403'/rel;b=snap/'pcm5102_pam8403'/rel
            if a.exists() and b.exists():
                def normalized(p,root):return A.read_text(p).replace('\\','/').replace(str(root).replace('\\','/'),'<snapshot>').strip()
                equal=normalized(a,OLD)==normalized(b,snap)
                effective[rel]={'equal_after_snapshot_path_normalization':equal,'baseline_sha256':sha(a),'candidate_sha256':sha(b)}
                assert equal,(name,rel,'effective build options differ')
        record['effective_build_configuration']=effective
        builds.append(record)
        sx=snap/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml'
        if sx.exists():
            hc=hierarchy(sx);rows=[]
            for path in set(hb)|set(hc):
                b=hb.get(path,{});c=hc.get(path,{})
                delta=sum(c.get(k,0)-b.get(k,0) for k in ['Lut','Alu'])
                if delta:rows.append({'path':path,'baseline':b,'candidate':c,'self_lut_alu_delta':delta})
            hd[name]=sorted(rows,key=lambda r:abs(r['self_lut_alu_delta']),reverse=True)
    for probe,output in [('probe','apds_probe'),('flash_probe','flash_probe')]:
        xml=snap/probe/'impl/gwsynthesis'/f'{output}_syn_rsc.xml'
        if not xml.exists():continue
        node=ET.parse(xml).getroot()
        attrs=node.attrib
        local[f'{name}/{probe}']={'LUT':int(attrs.get('Lut',0)),'ALU':int(attrs.get('Alu',0)),'FF':int(attrs.get('Register',0)),
          'multipliers':{k:int(v) for k,v in attrs.items() if k.startswith('MULT')},'resource_xml':str(xml),'resource_xml_sha256':sha(xml)}
        local[f'{name}/{probe}']['LUT_plus_ALU']=local[f'{name}/{probe}']['LUT']+local[f'{name}/{probe}']['ALU']
        local[f'{name}/{probe}']['including_children']={k:int(attrs.get('T_'+field,'0').split('(')[0]) for k,field in [('LUT','Lut'),('ALU','Alu'),('FF','Register')]}

def traces(log,tags):return [x for x in log.read_text(encoding='utf-8-sig').splitlines() if x.startswith(tags)]
tests={}
for suffix in ['scenarios','guard']:
    a=H/f'baseline-{suffix}.log';b=H/f'apds_serial-{suffix}.log'
    tags=('CMD ','POLL ','EVENT ','ENDPOINT ')
    x=traces(a,tags);y=traces(b,tags)
    assert x==y,(suffix,[(i,j) for i,j in zip(x,y) if i!=j][:5])
    assert traces(a,('PASS',)) and traces(b,('PASS',))
    tests[suffix]={'equal_trace_records':len(x),'baseline_pass':traces(a,('PASS',)),'candidate_pass':traces(b,('PASS',)),
      'baseline_guard_cycles':traces(a,('GUARD ',)),'candidate_guard_cycles':traces(b,('GUARD ',))}
for name in ['baseline-nack','apds_serial-nack','bus','baseline-flash','flash_rotate-flash']:
    f=H/f'{name}.log'
    if f.exists():tests[name]={'pass_lines':traces(f,('PASS',)), 'fatal_lines':traces(f,('FATAL',)), 'sha256':sha(f)}
slot_a=H/'baseline/pcm5102_pam8403/sim/build/take_nor_slot.hex'
slot_b=H/'flash_rotate/pcm5102_pam8403/sim/build/take_nor_slot.hex'
if slot_b.exists():
    tests['flash_saved_image']={'baseline_sha256':sha(slot_a),'candidate_sha256':sha(slot_b),'byte_identical':slot_a.read_bytes()==slot_b.read_bytes()}
    assert tests['flash_saved_image']['byte_identical']

old=json.loads((H/'production_before.json').read_text())
drift=[{'Path':r['Path'],'before':r['SHA256'],'after':sha(ROOT/r['Path']) if (ROOT/r['Path']).exists() else None} for r in old if not (ROOT/r['Path']).exists() or sha(ROOT/r['Path'])!=r['SHA256']]
dump(H/'production_after_check.json',{'checked_inputs':len(old),'changed_since_start':drift,'note':'Other tools may change production concurrently. This experiment writes only inside its own report directory.'})
dump(H/'isolated_results.json',local)
dump(H/'hierarchy_delta.json',hd)
dump(H/'functional_results.json',tests)
dump(H/'build_audit.json',{'baseline':OLD.name,'builds':builds,'isolated':local,'functional':tests,'production_drift':drift})
evidence={str(p.relative_to(H)).replace('\\','/'):sha(p) for p in H.rglob('*') if p.is_file() and p.suffix in ['.py','.v','.sv','.tcl','.gprj','.sdc','.cst','.hex','.json','.md','.log','.xml','.diff'] and 'impl' not in p.relative_to(H).parts and p.name!='evidence_hashes.json' and '__pycache__' not in p.parts}
dump(H/'evidence_hashes.json',evidence)
for b in builds:print(b['label'],b['status'],{k:v['used'] for k,v in b['metrics'].items()},'unrouted',b['unrouted_nets'])
print('local',json.dumps(local));print('production drift',len(drift))
