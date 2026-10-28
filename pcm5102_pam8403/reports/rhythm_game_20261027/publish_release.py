from pathlib import Path
import json,hashlib,shutil,sys,stat
from PIL import Image
R=Path(__file__).resolve().parent;P=R.parent.parent;C=R/'candidate/pcm5102_pam8403'
F=C/'sim/build/unified/rhythm_game_release41/pcm5102_pam8403';BACK=R/'rollback_Code40'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
audit=json.loads((R/'build_audit.json').read_text(encoding='utf-8'))
resume='--resume' in sys.argv
assert not audit['published'] and audit['metrics']['CLS']['remaining']>=35
assert BACK.exists() if resume else not BACK.exists()
old=json.loads((P/'reports/control12_20261027/release.json').read_text(encoding='utf-8-sig'))
for e in old['copied_files']:
    f=BACK/e['path'] if resume and (BACK/e['path']).exists() else P/e['path'];assert f.exists() and sha(f)==e['sha256'],str(f)
assert sha((BACK if resume else P)/'impl/pnr/PCM5102_UNIFIED.fs')==old['default_bitstream_sha256']
assert sha((BACK if resume else P)/'android_app/dist/FPGA-Music-Unified.apk')==old['default_apk_sha256']
allowed={'downloadable_song.v','hc05_keymap.v','hc05_command.hex','hc05_command_decode.v',
    'top.v','hub75e_rhythm_display.v','key_live_stream.v','uart_8n1.v','sensor_poly_audio.v',
    'rhythm_game.v','rhythm_font.hex','rhythm_points.hex','rhythm_stats.hex','rhythm_judge.hex'}
copies=[]
for f in (C/'src').rglob('*'):
    if f.is_file():
        rel=f.relative_to(C);dest=P/rel
        if not dest.exists() or sha(f)!=sha(dest) or (resume and f.name in allowed):
            assert f.name in allowed,str(rel);copies.append((f,dest))
files=['PCM5102_UNIFIED.gprj','tools/generate_hc05_decoder.py','tools/check_unified_build.ps1',
    'tools/run_sim.ps1','tools/generate_rhythm_tables.py','tools/test_rhythm.ps1',
    'impl/PCM5102_UNIFIED_process_config.json','android_app/app/build.gradle',
    'android_app/app/src/main/AndroidManifest.xml','android_app/app/src/main/java/cn/fpga/score/MainActivity.java',
    'android_app/app/src/main/java/cn/fpga/score/RhythmState.java','android_app/core_test/RhythmStateTest.java',
    'android_app/test-core.ps1','sim/reference/sensor_staging_reference.v',
    'sim/tb_rhythm_game.v','sim/tb_rhythm_panel.v','sim/tb_rhythm_raster.v','sim/tb_rhythm_protocol.v',
    'sim/tb_rhythm_top.v','sim/tb_rhythm_netlist.v','sim/tb_sensor_staging_equivalence.v']
copies.extend((C/rel,P/rel) for rel in files)
for folder in ['impl/pnr','impl/gwsynthesis']:
    copies.extend((f,P/folder/f.name) for f in (F/folder).iterdir() if f.is_file())
apk=C/'android_app/dist/FPGA-Music-Rhythm-Code41.apk';fs=F/'impl/pnr/PCM5102_UNIFIED.fs'
assert sha(apk)==audit['apk_sha256'] and sha(fs)==audit['bitstream_sha256']
copies.extend([(apk,P/'android_app/dist/FPGA-Music-Rhythm-Code41.apk'),
               (apk,P/'android_app/dist/FPGA-Music-Unified.apk'),
               (fs,R/'PCM5102_UNIFIED_RHYTHM_CODE41.fs')])
docs=['README.md','CONTROL12.md','RHYTHM_GUIDE.md','android_app/README.md',
      'CHROMATIC_KEYS.md','TOUCH16.md','VOICE_PITCH.md','SCORE_BEND.md']
backup_manifest={}
if resume:
    backup_manifest={str(f.relative_to(BACK)):sha(f) for f in BACK.rglob('*') if f.is_file()}
else:
    for dest in [d for _,d in copies if d.is_relative_to(P) and not d.is_relative_to(R)]+[P/d for d in docs]:
        if dest.exists():
            rel=dest.relative_to(P);q=BACK/rel;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dest,q);backup_manifest[str(rel)]=sha(q)
for source,dest in copies:
    dest.parent.mkdir(parents=True,exist_ok=True)
    # Gowin marks generated .bin files read-only. Preserve the original in the
    # rollback directory, clear only that file attribute, then replace bytes.
    if dest.exists() and not dest.stat().st_mode & stat.S_IWRITE:dest.chmod(dest.stat().st_mode | stat.S_IWRITE)
    shutil.copy2(source,dest);assert sha(source)==sha(dest)
    if dest.is_relative_to(P) and not dest.is_relative_to(R):audit.setdefault('published_files',{})[str(dest.relative_to(P))]=sha(dest)
for name in docs:
    p=P/name;s=p.read_text(encoding='utf-8-sig');s=s.replace('当前入口：Code40','当前入口：Code41（音游增强，沿用十二路映射）')
    if name=='CONTROL12.md':s=s.replace('使用 App **1.39-control12 / Code40** 与配套十二路码流。','使用 App **1.40-rhythm / Code41** 与配套音游码流，十二路协议沿用 Code40；音游设置与计分见 [音游说明](RHYTHM_GAME.md)。')
    if name=='README.md':s='**2026-10-27 音游增强已接入默认入口：App 1.40-rhythm / Code41。** 单点、和弦、长按、重复音判定，得分/连击/Miss，薄音符、三主题和击打闪光。剩余94 CLS（保留35后可用59）、54/56 BSRAM，50MHz setup/hold零违例。见 [音游用法](RHYTHM_GAME.md) 与 [交付/回退](reports/rhythm_game_20261027/README.md)。未安装或烧录。下列旧版本记录按其原范围阅读。\n\n'+s
    if name=='android_app/README.md':s='**2026-10-27 当前安装包：1.40-rhythm / Code41。** [FPGA-Music-Rhythm-Code41.apk](dist/FPGA-Music-Rhythm-Code41.apk) 与默认 Unified.apk 相同。主页“十二键音游”可设难度/配色/薄音符/长按/特效，读分与自动刷新；配套码流、原理及回退见 [音游说明](../RHYTHM_GAME.md)。未安装到手机。以下旧版本记录保留。\n\n'+s
    if name=='RHYTHM_GUIDE.md':s='> 2026-10-27 当前默认工程为 Code41 十二列音游，含真实判定、得分、连击、长按、薄音符和击打反馈。请先看 [当前用法](RHYTHM_GAME.md)。以下七轨文章为早期版本记录，不代表当前默认工程的列数与功能。\n\n'+s
    p.write_text(s,encoding='utf-8')
Image.open(C/'sim/build/rhythm_panel.ppm').resize((640,640),Image.Resampling.NEAREST).save(R/'rhythm_panel.png')
audit['published']=True;audit['rollback_hashes']=backup_manifest
audit['routed_scan']={'result':'PASS','log_sha256':sha(R/'netlist_scan.log'),'scope':'40 row pairs, startup/scan/RGB/blanking; no full UART netlist run'}
audit['full_uart_netlist']='Earlier run terminated to correct a 33-byte expected fixture for a 32-byte frame; not counted as PASS.'
audit['source_and_named_artifacts_match']=True
(R/'release.json').write_text(json.dumps(audit,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({'published_files':len(audit['published_files']),'rollback_files':len(backup_manifest),
    'apk_sha256':sha(P/'android_app/dist/FPGA-Music-Unified.apk'),'fs_sha256':sha(P/'impl/pnr/PCM5102_UNIFIED.fs')},ensure_ascii=False))
