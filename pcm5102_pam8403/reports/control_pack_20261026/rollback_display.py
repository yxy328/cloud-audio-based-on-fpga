"""Withdraw the CLS-increasing experiment without discarding its evidence."""
from pathlib import Path
import hashlib,json,shutil,stat

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parent.parent
REPO=PROJECT.parent
DISPLAY=PROJECT/'reports/display_ports_20261026'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def save(path,obj):path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

record=json.loads((DISPLAY/'integration.json').read_text(encoding='utf-8'))
freeze=json.loads((DISPLAY/'freeze.json').read_text(encoding='utf-8'))
final=json.loads((DISPLAY/'final_check.json').read_text(encoding='utf-8'))
assert not (HERE/'rollback.json').exists()
assert all(sha(REPO/r['Path'])==r['SHA256'] for r in record['production_inputs'])
assert all(sha(REPO/r['path'])==r['SHA256'] for r in record['outputs'])
assert sha(PROJECT/'sim/tb_hub75e_rhythm_display.v')==record['test_fixture_sha256']
for name in ('README.md','VERIFICATION.md'):
    expected=next(v for k,v in final['doc_hashes'].items() if k.replace('\\','/')=='pcm5102_pam8403/'+name)
    assert sha(PROJECT/name)==expected, 'Preserve concurrent document edits'
changes=[]
for r in record['outputs']:
    dst=REPO/r['path']
    relative=dst.relative_to(PROJECT)
    if relative.as_posix()=='src/hub75e_rhythm_display.v':src=DISPLAY/'production_before/hub75e_rhythm_display.v'
    elif relative.as_posix()=='tools/build_unified.tcl':src=DISPLAY/'production_before/build_unified.tcl'
    else:src=DISPLAY/'production_before'/relative
    assert src.is_file(),src
    changes.append((src,dst))
for name in ('README.md','VERIFICATION.md','sim/tb_hub75e_rhythm_display.v'):
    src=DISPLAY/'production_before'/Path(name).name
    changes.append((src,PROJECT/name))
for src,dst in changes:
    if dst.exists():dst.chmod(dst.stat().st_mode|stat.S_IWRITE)
    shutil.copy2(src,dst)
    assert sha(src)==sha(dst)
assert all(sha(REPO/r['Path'])==r['SHA256'] for r in freeze['production_inputs'])
assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==freeze['baseline_fs_sha256']
result={'reason':'CLS is the primary objective; the display candidate increased CLS by 77 without a verified follow-on saving',
        'restored_metrics':freeze['baseline_audit']['metrics'],'production_inputs':freeze['production_inputs'],
        'bitstream_sha256':freeze['baseline_fs_sha256'],
        'restored_files':[{'path':str(dst.relative_to(REPO)),'SHA256':sha(dst)} for _,dst in changes],
        'experimental_evidence_preserved':True,'burned_fpga':False}
save(HERE/'rollback.json',result)
save(DISPLAY/'withdrawn.json',{'reason':result['reason'],'current_production':'First HC-05 validated baseline',
                             'rollback_evidence':'../control_pack_20261026/rollback.json'})
path=DISPLAY/'README.md';text=path.read_text(encoding='utf-8')
text=text.replace('已接入默认工程与默认位流。本次完整 PNR 状态为 `validated`。',
    '**已撤回默认接入。** 该候选功能和时序通过，但新增 77 CLS，不符合当前以减少 CLS 为主的目标。默认工程已恢复 11387 CLS / 53 BSRAM；以下为实验与历史接入记录。')
text=text.replace('默认入口为 `../../impl/pnr/PCM5102_UNIFIED.fs`；独立副本 ',
    '默认位流已恢复第一轮 HC-05 版本。此实验的独立副本 ')
text=text.replace('| window3_place2 | place2/route0/fan23 | validated | 0 | 是 |',
    '| window3_place2 | place2/route0/fan23 | validated | 0 | 已撤回 |')
path.write_text(text,encoding='utf-8')
print('Restored',len(changes),'files; current CLS=11387, BSRAM=53; evidence preserved')
