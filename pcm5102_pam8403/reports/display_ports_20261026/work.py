"""Freeze, simulate, build and audit display-port experiments in isolation."""
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
PRIOR = PROJECT / 'reports/hc05_cls_first_20261026'
GOWIN = Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
IVERILOG = Path('C:/iverilog/bin/iverilog.exe')
VVP = Path('C:/iverilog/bin/vvp.exe')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def manifest(root):
    entries = []
    for folder in ('pcm5102_pam8403/src', 'pmod_hub75e/src', 'build_inputs'):
        entries += [{'Path': p.relative_to(root).as_posix(), 'SHA256': sha(p)}
                    for p in sorted((root/folder).rglob('*')) if p.is_file()]
    for name in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj', 'pcm5102_pam8403/tools/build_unified.tcl'):
        entries.append({'Path':name, 'SHA256':sha(root/name)})
    return entries

def prepare():
    baseline = HERE/'baseline'
    assert not baseline.exists()
    prior = json.loads((PRIOR/'integration.json').read_text(encoding='utf-8'))
    production = prior['production_inputs']
    assert all(sha(REPO/r['Path'])==r['SHA256'] for r in production), 'Production inputs drifted'
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==prior['production_bitstream_sha256']
    for folder in ('src','tools','sim'):
        shutil.copytree(PROJECT/folder, baseline/PROJECT.name/folder,
                        ignore=shutil.ignore_patterns('build','__pycache__'))
    shutil.copy2(PROJECT/'PCM5102_UNIFIED.gprj', baseline/PROJECT.name/'PCM5102_UNIFIED.gprj')
    shutil.copytree(REPO/'pmod_hub75e/src', baseline/'pmod_hub75e/src')
    shutil.copytree(PRIOR/'reply_place1/build_inputs', baseline/'build_inputs')
    save(baseline/'sources.json', manifest(baseline))
    backup = HERE/'production_before'
    for folder in ('gwsynthesis','pnr'):
        shutil.copytree(PROJECT/'impl'/folder, backup/'impl'/folder)
    shutil.copy2(PROJECT/'src/hub75e_rhythm_display.v', backup/'hub75e_rhythm_display.v')
    base_audit=json.loads((PRIOR/'reply_place1/audit.json').read_text(encoding='utf-8'))
    save(HERE/'freeze.json', {'production_inputs':production, 'baseline_audit':base_audit,
         'gowin_sha256':sha(GOWIN), 'baseline_fs_sha256':prior['production_bitstream_sha256'],
         'baseline_report_sha256':sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.rpt.txt')})
    target=HERE/'window3'
    shutil.copytree(baseline,target,ignore=shutil.ignore_patterns('sources.json'))
    path=target/PROJECT.name/'src/hub75e_rhythm_display.v'
    source=path.read_text(encoding='utf-8')
    source=source.replace('    // The first RAM is the insertion read/modify/write port. Six identical\n'
        '    // copies supply the upper/lower three-row glyph reads in parallel.\n'
        '    // This trades seven spare BSRAMs for the parallel shift and wide muxes.\n',
        '    // Keep the dedicated insertion read/modify/write RAM. Two panel\n'
        '    // RAMs maintain sliding windows with write-through forwarding.\n')
    start=source.index('    wire [6:0] panel_heads[0:5];')
    end=source.index('`ifndef SYNTHESIS',start)
    source=source[:start]+(HERE/'window_ports.vfrag').read_text(encoding='utf-8')+source[end:]
    # Verilog-2001 generate variables must be declared outside the for loop.
    source=source.replace('    genvar half;', '    genvar half,dy;').replace('for(genvar dy=0;', 'for(dy=0;')
    path.write_text(source,encoding='utf-8',newline='\n')
    save(target/'sources.json',manifest(target))
    print('Frozen current production; prepared window3, only display RTL differs',flush=True)

def build(label):
    root=HERE/label
    assert not (root/'build.log').exists()
    before=manifest(root); save(root/'sources.json',before)
    with (root/'build.log').open('w',encoding='utf-8') as log:
        result=subprocess.run([str(GOWIN),str(root/PROJECT.name/'tools/build_unified.tcl')],
                              cwd=root/PROJECT.name,stdout=log,stderr=log)
    save(root/'exit.json',{'returncode':result.returncode,'inputs_unchanged':before==manifest(root)})
    print(label,'finished',result.returncode,flush=True)

def physical(label, place):
    root=HERE/label
    assert not root.exists()
    shutil.copytree(HERE/'baseline',root,ignore=shutil.ignore_patterns('sources.json','build','__pycache__'))
    source=HERE/'window3'/PROJECT.name/'src/hub75e_rhythm_display.v'
    shutil.copy2(source,root/PROJECT.name/'src/hub75e_rhythm_display.v')
    script=root/PROJECT.name/'tools/build_unified.tcl'
    text=script.read_text(encoding='utf-8')
    text=re.sub(r'(-place_option )\d+',lambda m:m[1]+str(place),text)
    script.write_text(text,encoding='utf-8',newline='\n')
    save(root/'functional_reference.json',{'parent':'window3','display_sha256':sha(source),
         'reason':'Only place_option changes; all RTL/ROM/constraints and synthesis settings are identical'})
    save(root/'sources.json',manifest(root))
    print('Prepared',label,'place',place,flush=True)

def audit(label):
    helper=PROJECT/'reports/local_reuse_20261025/audit_helpers.py'
    spec=importlib.util.spec_from_file_location('display_audit',helper)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
    result=module.audit(HERE/label,module.sources(HERE/'baseline'),freeze['baseline_audit']['metrics'])
    result['gowin_sha256']=sha(GOWIN)
    save(HERE/label/'audit.json',result)
    print(json.dumps({k:result[k] for k in ('status','metrics','delta_vs_baseline','unrouted_nets','timing')},indent=2))

def test(label, names):
    root=HERE/label
    project=root/PROJECT.name
    out=root/'tests';out.mkdir(exist_ok=True)
    (project/'sim/build').mkdir(parents=True,exist_ok=True)
    results=[]
    for name in names:
        bench=HERE/(name+'.v')
        if not bench.exists():bench=project/'sim'/(name+'.v')
        rtl=list((project/'src').glob('*.v'))+list((root/'pmod_hub75e/src').glob('*.v'))
        # All original RTL modules are available; uninstantiated modules are ignored.
        rtl += [project/'sim/reference/hub75e_rhythm_display_reference.v']
        reference=out/'display_before.v'
        reference.write_text((HERE/'baseline'/PROJECT.name/'src/hub75e_rhythm_display.v').read_text(encoding='utf-8').replace(
            'module hub75e_rhythm_display #(', 'module hub75e_rhythm_display_before #(',1),encoding='utf-8')
        rtl += [reference]
        binary=out/(name+'.vvp')
        logpath=out/(name+'.log')
        attempt=1
        while logpath.exists():
            logpath=out/(name+f'.attempt{attempt}.log');attempt+=1
        with logpath.open('w',encoding='utf-8') as log:
            c=subprocess.run([str(IVERILOG),'-g2001','-s',name,'-o',str(binary),str(bench),*map(str,rtl)],cwd=project,stdout=log,stderr=log)
            log.flush()
            r=subprocess.run([str(VVP),str(binary)],cwd=project,stdout=log,stderr=log) if c.returncode==0 else c
        content=logpath.read_text(encoding='utf-8')
        result={'test':name,'returncode':r.returncode,'passed':r.returncode==0 and bool(re.search(r'^PASS',content,re.M)),
                'pass_lines':re.findall(r'^PASS[^\r\n]*',content,re.M),'log':str(logpath),
                'bench_sha256':sha(bench),'log_sha256':sha(logpath)}
        results.append(result);print(result,flush=True)
        if not result['passed']: print(content[-4000:],flush=True)
    record=out/('verification_'+ '_'.join(names)+'.json')
    save(record,{'display_sha256':sha(project/'src/hub75e_rhythm_display.v'),'tests':results,
                                  'all_passed':all(r['passed'] for r in results)})
    if not all(r['passed'] for r in results):raise SystemExit(1)

if __name__=='__main__':
    action=sys.argv[1]
    if action=='prepare':prepare()
    elif action=='build':build(sys.argv[2])
    elif action=='audit':audit(sys.argv[2])
    elif action=='test':test(sys.argv[2],sys.argv[3:])
    elif action=='physical':physical(sys.argv[2],int(sys.argv[3]))
