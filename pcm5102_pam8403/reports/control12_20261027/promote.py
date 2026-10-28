"""Promote only a fully verified, routed candidate with >=35 spare CLS."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,stat,re

R=Path(__file__).resolve().parent
BASE=R.parents[1]
ROOT=BASE.parent
P=R/'candidate/pcm5102_pam8403'
A=R/'app_candidate'
label=sys.argv[1]
SNAP=P/'sim/build/unified'/label
B=SNAP/'pcm5102_pam8403'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def save(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
subprocess.run([sys.executable,str(R/'audit.py')],check=True)
result=next(row for row in json.loads((R/'build_results.json').read_text(encoding='utf-8'))['builds'] if row['label']==label)
assert result['default_hardware_admissible'], 'Not admissible: routing/timing/35 CLS reserve'
assert result['current_candidate_inputs_match'] and not result['snapshot_corrupt_inputs']
assert all(v['used']<=v['capacity'] for v in result['metrics'].values())
subprocess.run([sys.executable,str(R/'verify_final.py'),label],check=True)
place=result['strategy']['place_option'];route=result['strategy']['route_option'];fan=result['strategy']['route_maxfan']
assert place in range(5) and route in range(3) and 1<=fan<=100
for kind in ['setup','hold']:
    assert result['timing'][kind+'_raw_worst_path']['slack_ns']>=0
for name in ['touch_width_equivalence.log','width_final_top.log','width_final_units.log','width_final_compat.log','app_core_final.log','app_control12.log']:
    data=(R/name).read_text(encoding='utf-8-sig',errors='replace')
    assert 'PASS' in data and 'FATAL:' not in data and 'Exception:' not in data, name
assert (R/'width_final_top.log').read_text(encoding='utf-8-sig',errors='replace').count('PASS control12')==2
assert not json.loads((R/'production_unchanged.json').read_text(encoding='utf-8'))['changed']
tracked_changes=subprocess.check_output(['git','diff','--name-only'],cwd=ROOT,text=True).strip()
assert not tracked_changes, 'Inspect concurrent tracked production edits before promotion: '+tracked_changes
assert not json.loads((R/'app_assets_comparison.json').read_text(encoding='utf-8'))['changed_assets']
assert sha(BASE/'android_app/tools/debug.keystore')==sha(A/'tools/debug.keystore')
apk=A/'dist/FPGA-Music-Control12-Candidate-Code40.apk'
named_apk=BASE/'android_app/dist/FPGA-Music-Control12-Code40.apk'
named_fs=R/'PCM5102_UNIFIED_CONTROL12_20261027.fs'
assert not named_apk.exists() and not named_fs.exists()
assert "versionCode='40'" in (R/'app_build_paired.log').read_text(encoding='utf-8-sig',errors='replace')
rollback=R/'rollback_Code39'
assert not rollback.exists(),'Rollback folder exists; inspect a previous promotion before retrying'
rollback.mkdir()
copies=[]
def copy(source,target):
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():target.chmod(target.stat().st_mode|stat.S_IWRITE)
    shutil.copy2(source,target)
    assert sha(source)==sha(target)
    copies.append({'path':str(target.relative_to(BASE)),'sha256':sha(target)})
def install(source,target):
    if target.exists():
        backup=rollback/target.relative_to(BASE);backup.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,backup)
    copy(source,target)

# Preserve the baseline source/config and both rolling artifacts first.
for source in (P/'src').iterdir():
    if source.is_file():
        target=BASE/'src'/source.name
        if not target.exists() or sha(source)!=sha(target):install(source,target)
for name in ['generate_hc05_decoder.py','generate_hc05_replies.py']:
    install(P/'tools'/name,BASE/'tools'/name)
build_script=(BASE/'tools/build_unified.tcl').read_text(encoding='utf-8')
for option,value in [('place_option',place),('route_option',route),('route_maxfan',fan)]:
    build_script=re.sub(r'(-'+option+r' )\d+',lambda m:m[1]+str(value),build_script)
if build_script!=(BASE/'tools/build_unified.tcl').read_text(encoding='utf-8'):
    (R/'selected_build_unified.tcl').write_text(build_script,encoding='utf-8')
    install(R/'selected_build_unified.tcl',BASE/'tools/build_unified.tcl')
install(P/'tools/run_sim.ps1',BASE/'tools/run_sim.ps1')
install(P/'tools/test_control12.ps1',BASE/'tools/test_control12.ps1')
for source in (P/'sim').glob('tb_control12*.v'):install(source,BASE/'sim'/source.name)
install(P/'sim/tb_hc05_code39_equivalence.v',BASE/'sim/tb_hc05_code39_equivalence.v')
install(P/'sim/tb_hc05_download_fixed16.v',BASE/'sim/tb_hc05_download_fixed16.v')
for source in (P/'sim/reference').glob('*code39*'):install(source,BASE/'sim/reference'/source.name)
for name in ['tb_performance_take.v','tb_take_atomic.v','tb_fx_take_atomic_528.v']:
    install(P/'sim'/name,BASE/'sim'/name)
for folder in ['app','core_test']:
    for source in (A/folder).rglob('*'):
        if not source.is_file():continue
        target=BASE/'android_app'/source.relative_to(A)
        if not target.exists() or sha(source)!=sha(target):install(source,target)
install(A/'test-core.ps1',BASE/'android_app/test-core.ps1')
for section in ['gwsynthesis','pnr']:
    for source in (B/'impl'/section).iterdir():
        if source.is_file() and source.name.startswith('PCM5102_UNIFIED'):
            install(source,BASE/'impl'/section/source.name)
for name in ['cmd.do','device.cfg']:
    install(B/'impl/pnr'/name,BASE/'impl/pnr'/name)
install(B/'impl/PCM5102_UNIFIED_process_config.json',BASE/'impl/PCM5102_UNIFIED_process_config.json')
copy(apk,named_apk)
install(apk,BASE/'android_app/dist/FPGA-Music-Unified.apk')
copy(B/'impl/pnr/PCM5102_UNIFIED.fs',named_fs)

metrics=result['metrics'];remaining=int(result['cls_remaining'])
setup=result['timing']['setup_raw_worst_path']['slack_ns']
hold=result['timing']['hold_raw_worst_path']['slack_ns']
guide='''# 十二路映射与弯音

使用 App **1.39-control12 / Code40** 与配套十二路码流。默认入口已更新。TTP229 接线及十六键串行配置保持。

- K1～K12 默认依次为 C4～B4（MIDI 60～71），均可改映射到 MIDI 60～72，并可独立弯音。
- K13～K16 继续为 C5/D5/E5/F5；触摸引擎仍支持十六键发声。
- App“触摸 → 音高”提供十二路映射与十二个弯音滑杆；恢复默认映射即可恢复完整半音阶。
- 曲谱下载、自动演奏、曲谱弯音及屏幕十二列指引共用十二路映射。同一和弦共用一个曲谱弯音目标；空白沿用各自手动目标，0 显式回正。STOP、休止或结束后按当前速率回到各自手动目标。
- 原两列 CSV / MIDI 导入和三列弯音 CSV 的预览、导出继续可用。128 条曲谱、每条 1～60000 ms 保持；十二个键最多覆盖十二种不同音高，不能同时覆盖 60～72 的全部十三种音高，缺音会拒绝下载。

`MAP?` 现在返回十二项；`MAP,<1..12>,<60..72>` 返回 `OK`。`BEND,<1..12>,<ratio>` 扩至十二路，其他比率/范围/忙保护沿用原协议。请配套更新 APK 和码流。

TAKE 继续使用 1024 个差分事件，能记录/回放新增五路的实际弯音音高。新版可读取旧七路 TAKE；新版十二路 TAKE 由配套新版固件回放。字段增加会增加初始快照及同时变化时的事件数，不承诺同一操作的录制时长不变。

[交付与资源报告](reports/control12_20261027/README.md) · [曲谱弯音 CSV 用法](SCORE_BEND.md)
'''
(BASE/'CONTROL12.md').write_text(guide,encoding='utf-8')
p=BASE/'SCORE_BEND.md';old=p.read_text(encoding='utf-8');backup=rollback/'SCORE_BEND.md';shutil.copy2(p,backup)
p.write_text(old.replace('1.38-scorebend / Code39','1.39-control12 / Code40').replace('实际七键映射','实际十二键映射')+'\n十二路映射、弯音与指引详见 [CONTROL12.md](CONTROL12.md)。\n',encoding='utf-8')
for rel,link in [('README.md','CONTROL12.md'),('CHROMATIC_KEYS.md','CONTROL12.md'),('VOICE_PITCH.md','CONTROL12.md'),('TOUCH16.md','CONTROL12.md'),('android_app/README.md','../CONTROL12.md')]:
    path=BASE/rel;backup=rollback/rel;backup.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,backup)
    text=path.read_text(encoding='utf-8')
    banner=f'> 2026-10-27 当前入口：Code40，K1～K12 已支持映射、独立弯音、曲谱及十二列指引；K13～K16 保留高音键。使用与配套版本见 [十二路说明]({link})。下文较早版本记录按其原范围阅读。\n\n'
    path.write_text(banner+text,encoding='utf-8')
save(R/'release.json',{'label':label,'build':result,'copied_files':copies,'default_apk_sha256':sha(BASE/'android_app/dist/FPGA-Music-Unified.apk'),'default_bitstream_sha256':sha(BASE/'impl/pnr/PCM5102_UNIFIED.fs'),'board_programmed':False,'app_installed':False})
table='\n'.join(f'| {name} | {v["used"]:g} / {v["capacity"]:g} | {v["capacity"]-v["used"]:g} |' for name,v in metrics.items())
(R/'README.md').write_text(f'''# 十二路控制交付（2026-10-27）

已接入默认工程与 App **1.39-control12 / Code40**。K1～K12 支持映射、独立弯音、曲谱弯音、自动演奏和十二列指引；K13～K16 保留高音，十六键发声保留。未安装 App、烧录 FPGA 或写板上 Flash。

| 资源 | 本轮用量 | 剩余 |
|---|---:|---:|
{table}

CLS 保留 35 后仍可用 **{remaining-35}**。50 MHz，sharing=1、retiming=1、place{place}/route{route}/fan{fan}；未布通 0，setup/hold 违例 0/0，原始 WNS **{setup:+.3f}/{hold:+.3f} ns**。资源增量以 `build_results.json` 的 Code39 基线到本轮最终物理结果计算，包含 RTL 与物理策略联合影响，不叠加中间候选成本。

## 产物

- [Code40 APK](../../android_app/dist/FPGA-Music-Control12-Code40.apk)，SHA256 `{sha(named_apk)}`。
- [配套码流](PCM5102_UNIFIED_CONTROL12_20261027.fs)，SHA256 `{sha(named_fs)}`。
- [用法](../../CONTROL12.md)、[设计与兼容边界](DESIGN.md)、[构建记录](build_results.json)、[最终回归与源指纹](final_verification.json)、[验证日志索引](verification.json)、[本轮交付指纹](release.json)。
- 标准 `android_app/dist/FPGA-Music-Unified.apk` 与 `impl/pnr/PCM5102_UNIFIED.fs` 已同步，并分别与命名文件逐字节核对。
- [Code39 回退目录](rollback_Code39/) 保存了本轮覆盖的原源码/配置、旧滚动 APK 和旧默认码流。原 Code39 命名交付仍保留。

## 验证与边界

十二键逐键十三个合法音高、两位键号、全部 BEND 地址、严格边界和旧七路协议通过。十二路扫描验证 1024 步滑音、单位/端点、独立声部、压力叠加与回正；曲谱验证 128×1 ms 密集十二键/休止/弯音和完整指引、128×60000 ms 上限、原子双 bank、STOP/重启及失败保留旧谱。

整机测试核对 84 个精确音高结果、24 条 UART 交互、十六键、十二列外部屏幕时序、外部 I2S 协议/余量/音频帧期限、曲谱目标与手动恢复。TAKE 验证旧33字段/新43字段兼容、原子捕获、缺字段拒绝，并经过真实 RTL 顶层 UART 录制/停止/回放和 K8/K12 实际 DDS 音高恢复。通用 TAKE 和原528位三效果原子快照回归通过。

Android 核心回归、新增十二键导入/匹配/拒绝/弯音 CSV 检查、APK 编译、版本和签名通过。与 Code39 的十项素材逐项一致，签名证书保持。数字仿真和时序报告不替代手机、蓝牙、板上烧录及 DAC 听音验收。

最终位宽优化对照旧引擎：音量移位0/4/18及快速读四组共768帧逐位一致，覆盖16路相位/包络/年龄/踏板/复音/旧格式回退，普通/快速读最忙1011/819拍（1024拍期限）。实时按键上行逐周期对照旧实现100000拍，覆盖满FIFO、回绕、停发、复位和UART背压。最终23组RTL检查及源指纹见 final_verification.json；资源或时序未达标的中间RAM原型均未采用。

复现：`tools/test_control12.ps1` 运行23组RTL与App核心检查；新建唯一标签后执行 `tools/check_unified_build.ps1 -Label <label> -SynthesisOnly` 和 `tools/resume_unified_pnr.ps1 -Label <label>`。原始冻结输入、全部候选与失败记录均保存在本目录。
''',encoding='utf-8')
print(json.dumps({'promoted':label,'CLS_remaining':remaining,'usable_after_reserve':remaining-35,'apk_sha256':sha(named_apk),'fs_sha256':sha(named_fs)},ensure_ascii=False))
