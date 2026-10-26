"""Admit only the passing combined design; preserve all old defaults first."""
from work import *
import stat

def copy_checked(source,target):
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():target.chmod(target.stat().st_mode|stat.S_IWRITE)
    shutil.copy2(source,target)
    assert sha(source)==sha(target),str(target)

label=sys.argv[1]
root=HERE/label
audit=json.loads((root/'audit.json').read_text(encoding='utf-8'))
freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
assert audit['admitted_physical'] and audit['status']=='validated'
assert json.loads((root/'exit.json').read_text(encoding='utf-8'))=={'returncode':0,'inputs_unchanged':True}
assert manifest(root)==json.loads((root/'sources.json').read_text(encoding='utf-8'))
assert sha(GOWIN)==freeze['gowin_sha256']
parent_rows={r['Path']:r['SHA256'] for r in manifest(HERE/'candidate')}
rows={r['Path']:r['SHA256'] for r in manifest(root)}
assert [n for n in rows if rows[n]!=parent_rows[n]] in ([],['pcm5102_pam8403/tools/build_unified.tcl'])

required=['tb_score_bend_words','tb_score_legacy','tb_score_bend_protocol',
          'tb_score_bend_manual_legacy','tb_score_bend_slew','tb_score_bend_scope',
          'tb_score_bend_frame_take','tb_hc05_download_current','tb_fx3_replay_decode',
          'tb_fx_take_atomic_528','tb_top_score_config','tb_top_audition',
          'tb_top_touch16_recovery','tb_song_time_bound']
required += [name+'_score_equiv' for name in ('tb_command_protocol','tb_hc05_extensions',
    'tb_hc05_control_races','tb_fx_protocol','tb_hc05_keymap','tb_hc05_download_current',
    'tb_hc05_take','tb_hc05_adsr','tb_hc05_bend','tb_hc05_visual','tb_hc05_xy')]
passed={}
for path in sorted((HERE/'candidate/tests').glob('*/results.json')):
    for row in json.loads(path.read_text(encoding='utf-8')):
        if row['passed']:
            assert sha(Path(row['log']))==row['sha256']
            passed[row['test']]=row
assert not set(required)-set(passed),('Missing passing checks',set(required)-set(passed))
baseline_checks=json.loads((HERE/'baseline/tests/final_audio/results.json').read_text(encoding='utf-8'))
assert all(row['passed'] for row in baseline_checks)
golden=HERE/'baseline'/PROJECT.name/'sim/build/tb_top_audition_serial_current.csv'
actual=HERE/'candidate'/PROJECT.name/'sim/build/tb_top_audition.csv'
assert sha(golden)==sha(actual),'Legacy audition external I2S PCM differs from unchanged baseline'
save(HERE/'legacy_audio_equivalence.json',{'baseline_sha256':sha(golden),'candidate_sha256':sha(actual),
    'equal':True,'sample_count':len(actual.read_text(encoding='utf-8').splitlines())-1,
    'scope':'every external I2S PCM sample and timestamp for the legacy audition scenario'})
core=(HERE/'app_core.log').read_text(encoding='utf-8',errors='replace')
assert '4827 checks' in core and 'PASS SongCodec:' in core and 'PASS SppLink:' in core
app=HERE/'app_stage'
apk=app/'dist/FPGA-Music-ScoreBend-Code39.apk'
assert apk.exists() and 'Verified' in (HERE/'app_build.log').read_text(encoding='utf-8',errors='replace')
certs=[re.search(r'certificate SHA-256 digest:\s*([a-f0-9]+)',(HERE/name).read_text(encoding='utf-8')).group(1)
       for name in ('apk_certificate.txt','rollback_certificate.txt')]
assert certs[0]==certs[1]

# Prepare the complete change list and reject concurrent edits before mutations.
original={r['Path']:r['SHA256'] for r in freeze['production_inputs']}
assert all(sha(REPO/name)==value for name,value in original.items()),'Production drift'
changes=[name for name,value in original.items() if rows[name]!=value]
allowed={'pcm5102_pam8403/src/downloadable_song.v','pcm5102_pam8403/src/fsr_pitch_scaler.v',
    'pcm5102_pam8403/src/hc05_keymap.v','pcm5102_pam8403/src/hc05_reply.hex',
    'pcm5102_pam8403/src/top.v','pcm5102_pam8403/tools/build_unified.tcl'}
assert set(changes)<=allowed,changes
assert sha(PROJECT/'tools/generate_hc05_replies.py')==sha(HERE/'baseline'/PROJECT.name/'tools/generate_hc05_replies.py')
app_original={r['Path']:r['SHA256'] for r in freeze['app_inputs']}
assert all(sha(PROJECT/'android_app'/name)==value for name,value in app_original.items()),'App source/artwork drift'
app_changes=[]
for p in sorted(app.rglob('*')):
    if not p.is_file():continue
    relative=p.relative_to(app).as_posix()
    if not (relative.startswith('app/') or relative.startswith('core_test/') or relative=='test-core.ps1'):continue
    old=app_original.get(relative)
    if old!=sha(p):
        target=PROJECT/'android_app'/relative
        assert (not target.exists() if old is None else sha(target)==old),('App drift',relative)
        app_changes.append(relative)
assert set(app_changes)=={'app/build.gradle','app/src/main/AndroidManifest.xml',
    'app/src/main/java/cn/fpga/score/MainActivity.java','app/src/main/java/cn/fpga/score/ScoreBends.java',
    'core_test/ScoreBendsTest.java','test-core.ps1'},app_changes

# Apply the tested RTL, its generator, explicit optional test ports and public tests.
for name in changes:copy_checked(root/name,REPO/name)
copy_checked(HERE/'candidate'/PROJECT.name/'tools/generate_hc05_replies.py',PROJECT/'tools/generate_hc05_replies.py')
sim_changes=[]
for p in sorted((HERE/'candidate'/PROJECT.name/'sim').rglob('*.v')):
    rel=p.relative_to(HERE/'candidate'/PROJECT.name).as_posix()
    if '_score_equiv' in p.name:continue  # The full diagnostic wrappers stay in this report.
    old=HERE/'baseline'/PROJECT.name/rel
    if not old.exists() or sha(p)!=sha(old):
        target=PROJECT/rel
        assert not target.exists() if not old.exists() else sha(target)==sha(old)
        copy_checked(p,target);sim_changes.append(rel)
for name in app_changes:copy_checked(app/name,PROJECT/'android_app'/name)

# Copy the complete synthesis/PnR bundle, including its report and raw paths.
output_record=json.loads((CLS/'integration.json').read_text(encoding='utf-8'))['outputs']
outputs=[]
for record in output_record:
    name=record['path'].replace('\\','/')
    assert (root/name).is_file(),name
    copy_checked(root/name,REPO/name)
    outputs.append({'Path':name,'SHA256':sha(REPO/name)})
copy_checked(root/PROJECT.name/'impl/pnr/PCM5102_UNIFIED.fs',HERE/'PCM5102_UNIFIED_SCORE_BEND_20261027.fs')
copy_checked(apk,PROJECT/'android_app/dist/FPGA-Music-ScoreBend-Code39.apk')
copy_checked(apk,PROJECT/'android_app/dist/FPGA-Music-Unified.apk')

after=[{'Path':name,'SHA256':sha(REPO/name)} for name in original]
assert all(row['SHA256']==rows[row['Path']] for row in after)
assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==audit['bitstream_sha256']
app_input_list=[{'Path':p.relative_to(app).as_posix(),'SHA256':sha(p)}
                for p in sorted((app/'app').rglob('*')) if p.is_file()]
assert all(sha(PROJECT/'android_app'/row['Path'])==row['SHA256'] for row in app_input_list)
save(HERE/'app_sources.json',app_input_list)
save(HERE/'verification.json',{'required_count':len(required),'all_passed':True,
    'checks':[passed[name] for name in required],'legacy_outputs_compared':67,
    'legacy_audio_equivalence':json.loads((HERE/'legacy_audio_equivalence.json').read_text(encoding='utf-8')),
    'app_core_log_sha256':sha(HERE/'app_core.log'),'app_build_log_sha256':sha(HERE/'app_build.log')})
save(HERE/'release.json',{'selected':label,'physical_audit':audit,'production_inputs':after,
    'changed_inputs':changes,'changed_generator':'tools/generate_hc05_replies.py',
    'test_changes':sim_changes,'app_changes':app_changes,'outputs':outputs,
    'app_version':'1.38-scorebend / Code39','apk_sha256':sha(apk),
    'bitstream_sha256':audit['bitstream_sha256'],'same_certificate':True,
    'production_sources_match':True,'production_outputs_match':True,
    'installed':False,'programmed':False,'board_flash_written':False,
    'rollback_bitstream':str(HERE/'production_before/impl/pnr/PCM5102_UNIFIED.fs'),
    'rollback_bitstream_sha256':freeze['baseline_audit']['bitstream_sha256'],
    'rollback_apk':str(HERE/'production_before/rollback_app.apk'),
    'rollback_apk_sha256':freeze['rollback_apk_sha256']})
print('Integrated',label,'with',audit['cls_free'],'CLS free;',len(required),'checks; Code39')
