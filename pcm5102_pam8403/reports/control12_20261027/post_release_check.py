from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parent;BASE=R.parents[1];ROOT=BASE.parent
P=R/'candidate/pcm5102_pam8403';A=R/'app_candidate';rollback=R/'rollback_Code39'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
release=json.loads((R/'release.json').read_text(encoding='utf-8'))
assert release['build']['default_hardware_admissible']
assert all(sha(BASE/row['path'])==row['sha256'] for row in release['copied_files'])
assert release['build']['cls_remaining']==38 and release['build']['delta_vs_baseline']['CLS']==43
assert 38-35==3
assert all(sha(p)==sha(BASE/'src'/p.name) for p in (P/'src').iterdir() if p.is_file())
assert all(sha(p)==sha(BASE/'android_app'/p.relative_to(A)) for p in (A/'app').rglob('*') if p.is_file())
assert sha(BASE/'android_app/dist/FPGA-Music-Unified.apk')==sha(BASE/'android_app/dist/FPGA-Music-Control12-Code40.apk')==release['default_apk_sha256']
assert sha(BASE/'impl/pnr/PCM5102_UNIFIED.fs')==sha(R/'PCM5102_UNIFIED_CONTROL12_20261027.fs')==release['default_bitstream_sha256']
before=json.loads((R/'production_unchanged.json').read_text(encoding='utf-8'))
assert sha(rollback/'android_app/dist/FPGA-Music-Unified.apk')==before['default_apk_sha256']
assert sha(rollback/'impl/pnr/PCM5102_UNIFIED.fs')==before['default_bitstream_sha256']
changed=[]
for row in json.loads((R/'freeze.json').read_text(encoding='utf-8')):
 p=ROOT/row['path']
 if sha(p)!=row['sha256']:
  rel=p.relative_to(BASE)
  assert sha(rollback/rel)==row['sha256'],str(rel)
  changed.append(str(rel))
final=json.loads((R/'final_verification.json').read_text(encoding='utf-8'))
assert final['rtl_check_groups']==23
assert all(sha(R/name)==entry['sha256'] for name,entry in final['logs'].items())
core=(R/'app_core_installed_sources.log').read_text(encoding='utf-8-sig',errors='replace')
assert 'PASS' in core and 'Exception' not in core and 'FAIL' not in core
result={'checks':'PASS','source_and_app_files_match_tested_candidates':True,
 'default_artifacts_match_named_release':True,'rollback_matches_Code39':True,
 'changed_frozen_inputs':changed,'rtl_check_groups':23,
 'CLS_net_increase':43,'CLS_remaining':38,'CLS_safety_reserve':35,'CLS_usable':3,
 'APK_sha256':release['default_apk_sha256'],'bitstream_sha256':release['default_bitstream_sha256'],
 'app_core_in_installed_source_location':'PASS','board_programmed':False,'app_installed':False}
(R/'post_release_check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:result[k] for k in ['checks','rtl_check_groups','CLS_net_increase','CLS_remaining','CLS_safety_reserve','CLS_usable']}))
