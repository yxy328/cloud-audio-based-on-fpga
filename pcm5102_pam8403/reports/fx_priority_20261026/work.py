"""Three-effects priority build: preserve current working-tree inputs and evidence."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parent.parent;REPO=PROJECT.parent
GOWIN=Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def manifest(root):
    result=[]
    for p in sorted(root.rglob('*')):
        if not p.is_file():continue
        n=p.relative_to(root).as_posix()
        if n.startswith(('pcm5102_pam8403/src/','pmod_hub75e/src/','build_inputs/')) or n in (
            'pcm5102_pam8403/PCM5102_UNIFIED.gprj','pcm5102_pam8403/tools/build_unified.tcl'):
            result.append({'Path':n,'SHA256':sha(p)})
    return result
def prepare():
    old=PROJECT/'reports/touch16_delivery_20261026'
    inputs=json.loads((old/'production_inputs.json').read_text(encoding='utf-8'))
    assert all(sha(REPO/r['Path'])==r['SHA256'] for r in inputs)
    audit=json.loads((old/'production_audit.json').read_text(encoding='utf-8'))
    assert all(sha(PROJECT/k)==v for k,v in audit['actual_build_file_hashes'].items())
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==audit['bitstream_sha256']
    assert sha(GOWIN)==audit['gowin_sha256']
    base=HERE/'base';assert not base.exists();p=base/PROJECT.name;p.mkdir(parents=True)
    for folder in ('src','tools','sim'):
        shutil.copytree(PROJECT/folder,p/folder,ignore=shutil.ignore_patterns('build','__pycache__'))
    shutil.copy2(PROJECT/'PCM5102_UNIFIED.gprj',p/'PCM5102_UNIFIED.gprj')
    shutil.copytree(REPO/'pmod_hub75e/src',base/'pmod_hub75e/src')
    shutil.copytree(REPO/'pmod_hub75e/sim',base/'pmod_hub75e/sim',ignore=shutil.ignore_patterns('build'))
    (base/'build_inputs').mkdir()
    for name in ('PCM5102_UNIFIED_process_config.json','project_process_config.json'):
        shutil.copy2(PROJECT/'impl'/name,base/'build_inputs'/name)
    shutil.copytree(PROJECT/'impl/pnr',p/'impl/pnr')
    shutil.copytree(PROJECT/'impl/gwsynthesis',p/'impl/gwsynthesis')
    save(base/'sources.json',manifest(base))
    shutil.copy2(PROJECT/'android_app/dist/FPGA-Music-Unified.apk',HERE/'previous_Code26.apk')
    for name,args in [('starting_status.txt',['status','--porcelain=v1']),('starting_diff.patch',['diff','--binary','HEAD'])]:
        with (HERE/name).open('wb') as f:subprocess.run(['git','-C',str(REPO),*args],stdout=f,check=True)
    save(HERE/'priority.json',{'date':'2026-10-26','user_request':'暂停后续扩展，优先把混响和三效果做好',
        'deferred_D_B2_E_reserve':{'Logic':1650,'CLS':330,'BSRAM':4},'retained_CLS_safety':35,
        'existing_features_preserved':True,'baseline_reused_after_101_inputs_and_actual_build_hashes_verified':True,
        'gowin_sha256':sha(GOWIN),'previous_fs_sha256':audit['bitstream_sha256'],'previous_apk_sha256':sha(HERE/'previous_Code26.apk')})
    candidate=HERE/'chain';shutil.copytree(base,candidate,ignore=shutil.ignore_patterns('impl','build','sources.json','*.gprj.user'))
    (candidate/PROJECT.name/'impl').mkdir()
    print('Verified fixed16 production baseline; prepared isolated chain candidate; kept 35 CLS safety, deferred D/B2/E')
def build(label):
    root=HERE/label;p=root/PROJECT.name;assert not (root/'build.log').exists()
    save(root/'sources.json',manifest(root))
    with (root/'build.log').open('w',encoding='utf-8') as f:
        r=subprocess.run([str(GOWIN),str(p/'tools/build_unified.tcl')],cwd=p,stdout=f,stderr=f)
    save(root/'exit.json',{'returncode':r.returncode,'inputs_unchanged':manifest(root)==json.loads((root/'sources.json').read_text(encoding='utf-8'))})
    print(label,'exit',r.returncode)
if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare()
    elif sys.argv[1]=='build':build(sys.argv[2])
