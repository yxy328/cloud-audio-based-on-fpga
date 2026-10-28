from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent;P=R.parent.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
j=json.loads((R/'release.json').read_text(encoding='utf-8'))
for name,h in j['published_files'].items():assert sha(P/name)==h,name
for name,h in j['rollback_hashes'].items():assert sha(R/'rollback_Code40'/name)==h,name
for name,h in j['source_hashes'].items():assert sha(P/name)==h,name
assert sha(P/'impl/pnr/PCM5102_UNIFIED.fs')==sha(R/'PCM5102_UNIFIED_RHYTHM_CODE41.fs')==j['bitstream_sha256']
assert sha(P/'android_app/dist/FPGA-Music-Unified.apk')==sha(P/'android_app/dist/FPGA-Music-Rhythm-Code41.apk')==j['apk_sha256']
assert (P/'RHYTHM_GAME.md').is_file() and (R/'README.md').is_file()
check={'default_artifacts_match_named':True,'all_published_files_match':True,'all_rollback_files_match':True,
    'all_fpga_sources_match_tested_snapshot':True,'board_programmed':False,'app_installed':False}
for name in ['installed_source_check.log','installed_app_core.log']:
    p=R/name
    raw=p.read_bytes();text=raw.decode('utf-16' if raw[:2]==b'\xff\xfe' else 'utf-8-sig',errors='replace')
    assert 'PASS' in text and 'FATAL' not in text and 'AssertionError' not in text,name
    if name.startswith('installed_app'):assert 'PASS RhythmState' in text
    check[name]={'sha256':sha(p),'pass_count':sum(line.startswith('PASS') for line in text.splitlines())}
(R/'post_release_check.json').write_text(json.dumps(check,indent=2),encoding='utf-8')
print(json.dumps(check))
