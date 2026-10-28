"""Publish the validated Code44 snapshot; run from the project directory."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import stat
import sys

project = Path.cwd().resolve()
assert project.name == 'pcm5102_pam8403'
report = project / 'reports/rhythm_flick_shape_20261028'
label = sys.argv[1] if len(sys.argv)>1 else 'rhythm_flick44_b'
assert label in ('rhythm_flick44_b', 'rhythm_flick44_c')
snapshot = project / 'sim/build/unified' / label
target = snapshot / project.name
pnr = target / 'impl/pnr'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def copy(src, dst):
    assert dst.resolve().is_relative_to(project)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        if sha(src) == sha(dst):
            return
        dst.chmod(dst.stat().st_mode | stat.S_IWRITE)
    shutil.copy2(src, dst)


inputs = json.loads((snapshot / 'sources.json').read_text(encoding='utf-8-sig'))
for entry in inputs:
    relative = Path(entry['Path'])
    frozen = snapshot / relative
    assert sha(frozen) == entry['SHA256'], frozen
    if relative.parts[0] in ('pcm5102_pam8403', 'pmod_hub75e') and 'tools' not in relative.parts:
        live = project.parent / relative
        assert sha(live) == entry['SHA256'], live
old_inputs = json.loads((project / 'reports/rhythm_width5_20261028/frozen_inputs.json').read_text(encoding='utf-8-sig'))
old_hashes = {e['Path']: e['SHA256'] for e in old_inputs}
changed = [e['Path'] for e in inputs if e['Path'] in old_hashes and e['SHA256'] != old_hashes[e['Path']]]
assert changed == [r'pcm5102_pam8403\src\hub75e_rhythm_display.v'], changed

resources = {}
rpt = (pnr / 'PCM5102_UNIFIED.rpt.txt').read_text()
for name in ('Logic', 'CLS', 'Register', 'BSRAM', 'DSP'):
    used, total = re.search(r'^  ' + name + r'\s+\|\s*(\d+(?:\.\d+)?)/(\d+)', rpt, re.M).groups()
    resources[name] = dict(used=float(used) if '.' in used else int(used), total=int(total))
    assert float(used) <= int(total), (name, used, total)
sta = (pnr / 'PCM5102_UNIFIED_tr_content.html').read_text()
slacks = {}
for kind in ('Setup', 'Hold'):
    slacks[kind] = float(re.search('name="' + kind + r'_Slack_Table".*?<td>1</td>\s*<td>([^<]+)', sta, re.S).group(1))
    assert slacks[kind] >= 0, slacks
section = sta.split('name="Total_Negative_Slack_Report"', 1)[1].split('<h1', 1)[0]
violations = re.findall(r'<tr>\s*<td>([^<]+)</td>\s*<td>(Setup|Hold)</td>\s*<td>([^<]+)</td>\s*<td>(\d+)</td>', section)
assert len(violations) == 4 and all(float(v[2]) == 0 and int(v[3]) == 0 for v in violations), violations
route_log = (snapshot / 'pnr.log').read_text(encoding='utf-8-sig')
assert 'Placement and routing completed' in route_log and 'Bitstream generation completed' in route_log
assert not re.search(r'ERROR\s*\(', route_log), 'Route reported an error'
assert '-convert_sdp32_36_to_sdp16_18 0' in (target / 'tools/build_unified.tcl').read_text()
scan = (report / 'routed_scan.log').read_text(encoding='utf-8-sig')
assert 'PASS routed netlist scan' in scan and 'FATAL' not in scan
assert 'PASS RhythmState:' in (report / 'app_snapshot.log').read_text(encoding='utf-8-sig')
assert 'PASS exported RGB image:' in (report / 'exported_pixels.log').read_text(encoding='utf-8-sig')
tests = []
for test in ('tb_rhythm_panel', 'tb_rhythm_tails', 'tb_rhythm_raster', 'tb_hub75e_rhythm_display'):
    log = project / ('sim/build/' + test + '_quick.log')
    content = log.read_text(encoding='utf-8-sig')
    assert 'PASS ' in content and 'FATAL' not in content, test
    saved = report / 'tests' / log.name
    copy(log, saved)
    tests.append(dict(test=test, log=str(saved.relative_to(report)), sha256=sha(saved), test_source_sha256=sha(project / 'sim' / (test + '.v'))))

apk = project / 'android_app/dist/FPGA-Music-Rhythm-Flick-Code44.apk'
assert apk.is_file()
manifest = project / 'android_app/app/src/main/AndroidManifest.xml'
assert 'versionCode="44"' in manifest.read_text(encoding='utf-8')
assert '1.43-rhythm-flick' in manifest.read_text(encoding='utf-8')
old_release = json.loads((project / 'reports/rhythm_width5_20261028/release.json').read_text())
rollback = report / 'rollback_Code43'
assert sha(rollback / 'impl/pnr/PCM5102_UNIFIED.fs') == old_release['outputs']['bitstream']['sha256']
assert sha(rollback / 'android_app/dist/FPGA-Music-Unified.apk') == old_release['outputs']['apk']['sha256']

bitstream = report / 'PCM5102_UNIFIED_RHYTHM_FLICK_CODE44.fs'
copy(pnr / 'PCM5102_UNIFIED.fs', bitstream)
for directory in ('gwsynthesis', 'pnr'):
    for file in (target / 'impl' / directory).rglob('*'):
        if file.is_file():
            copy(file, project / 'impl' / directory / file.relative_to(target / 'impl' / directory))
copy(apk, project / 'android_app/dist/FPGA-Music-Unified.apk')
for name in ('PCM5102_UNIFIED.rpt.txt', 'PCM5102_UNIFIED.rpt.html', 'PCM5102_UNIFIED.tr.html', 'PCM5102_UNIFIED_tr_content.html', 'PCM5102_UNIFIED_tr_cata.html'):
    copy(pnr / name, report / name)
copy(snapshot / 'sources.json', report / 'frozen_inputs.json')
copy(target / 'tools/build_unified.tcl', report / 'frozen_synthesis.tcl')
copy(target / 'tools/resume_pnr.tcl', report / 'frozen_pnr.tcl')
assert sha(project / 'impl/pnr/PCM5102_UNIFIED.fs') == sha(bitstream)
assert sha(project / 'android_app/dist/FPGA-Music-Unified.apk') == sha(apk)

place = int(re.findall(r'-place_option (\d+)', (target / 'tools/resume_pnr.tcl').read_text())[-1])
release = dict(date='2026-10-28', label=label, app_version_code=44, app_version_name='1.43-rhythm-flick',
    device='GW5A-LV25MG121NC1/I0', tool='Gowin V1.9.11.03 Education', target_mhz=50,
    place=place, route=0, maxfan=23, native_wide_bsram=True, resources=resources,
    remaining_cls=resources['CLS']['total']-resources['CLS']['used'], setup_slack_ns=slacks['Setup'], hold_slack_ns=slacks['Hold'],
    violations=violations, unrouted=0, outputs=dict(apk=dict(name=apk.name, sha256=sha(apk)), bitstream=dict(name=bitstream.name, sha256=sha(bitstream))),
    all_live_fpga_inputs_match_frozen=True, changed_frozen_inputs_from_code43=changed,
    app_inputs={str(p.relative_to(project)): sha(p) for p in (project / 'android_app/app/src/main').rglob('*') if p.is_file()},
    app_gradle_sha256=sha(project / 'android_app/app/build.gradle'), rtl_tests=tests,
    rollback_inputs={str(p.relative_to(report)): sha(p) for p in rollback.rglob('*') if p.is_file()},
    layout=dict(lanes=12, tap_width_px=5, tap_height_px=1, key_width_px=5, flick_mask=['..###','###..'], flick_anchor='lower row reaches HIT_Y=54', score='six horizontal red digits at upper right'),
    installed_on_phone=False, programmed_fpga=False, routed_scan=scan.strip(),
    candidates={'a':'failed routing:539 unrouted nets', 'b':'complete route, zero timing violations', 'c':'stopped after b passed; not validated'})
(report / 'release.json').write_text(json.dumps(release, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
remaining = release['remaining_cls']
summary = f"Logic {resources['Logic']['used']} / CLS {resources['CLS']['used']} / Register {resources['Register']['used']} / BSRAM {resources['BSRAM']['used']} / DSP {resources['DSP']['used']}，剩{remaining} CLS。50MHz完整布通，主时钟与ADC时钟setup/hold违例均0，最差余量 {slacks['Setup']:+.3f}/{slacks['Hold']:+.3f} ns。"
readme = f'''# Code44：粉色 FLICK 阶梯轮廓

2026-10-28。修正Code43只给FLICK换成粉色、仍画成横条的问题。按照用户参考图中的六个粉色像素，改为整体5×2像素的阶梯：

```text
..###
###..
```

上排右侧3点，下排左侧3点；下排保持原来的到线判定位置。TAP保持5×1像素，HOLD尾条、黄色DRAG和下方十二键各5像素宽。顶部红色得分、命中变黄和四类判定继续保留。

- [Code44 APK](../../android_app/dist/FPGA-Music-Rhythm-Flick-Code44.apk)，App 1.43-rhythm-flick，更新音符形状说明。
- [Code44 配套位流](PCM5102_UNIFIED_RHYTHM_FLICK_CODE44.fs)
- [用法](../../RHYTHM_GAME.md)、[产物指纹与资源](release.json)

APK SHA256：`{sha(apk)}`。

位流 SHA256：`{sha(bitstream)}`。

## 实现与资源

仅修改FPGA的 `hub75e_rhythm_display.v`。复用已有两份面板缓存，在每行消隐时先读取相邻行的FLICK上排、再读取本行音符；两次读取冻结同一个滚动原点。不新增BSRAM、每个音符的计时器或曲谱事件写入次数。头部、上排一同滚动，包含跨31/32行的显示。其它FPGA输入逐项与Code43冻结版本一致。

最终候选 `{label}`，Gowin V1.9.11.03 Education，GW5A-LV25MG121NC1/I0，place{place}/route0/maxfan23，保留原生32/36位BSRAM。

{summary} BSRAM使用{resources['BSRAM']['used']}/{resources['BSRAM']['total']}，余{resources['BSRAM']['total']-resources['BSRAM']['used']}块。CLS余量比此前35个预留口径少{35-remaining}个，后续扩展需重新评估资源和时序。

## 验证与边界

- [外部RGB显示回归](display_tests.log)：逐像素/PWM检查FLICK的5×2轮廓及空白角、31/32行跨区、判定线54、滚动和STOP清屏；TAP/长按/DRAG、十二个底键、得分和133时钟扫描通过。
- 同轮检查600/2300/60000ms长按尾条、独立64行模型与994个密集音符、旧七列6174组参考扫描行，均通过。测试源与日志指纹见release.json。
- [导出像素核对](exported_pixels.log)、[FPGA输入比较](input_comparison.log)、[实际RTL分数快照解析](app_snapshot.log)通过。
- [APK构建](apk_build.log)完成Java/D8/aapt2编译、版本及签名核对。
- [路由后网表扫描](routed_scan.log)：40组64列外部RGB行、133时钟、已知像素和消隐/LAT顺序通过。这是启动扫描检查，不是整局门级玩法测试。

默认APK、默认位流及综合/路由输出已与同一最终候选同步。没有安装手机、烧录FPGA或做实体面板验收。玩法/音频等未改部分的更早验证见[Code43](../rhythm_width5_20261028/README.md)及[Code42](../rhythm_notes_20261028/README.md)。

## 未交付候选

候选a的像素测试通过，但布局布线报539条未布通，未生成可交付位流。随后改为消隐期复用原缓存，b使用place2完成验证。备用c从同一RTL尝试place4，在b完整布通且时序通过后停止，不计为验证通过。a的源码和构建日志保留用于追溯。

## 回退与复现

[rollback_Code43](rollback_Code43/) 保存改动前的源码、App、测试、文档和默认APK/位流；Code43命名产物仍保留。未进行Git提交。

```powershell
& ./tools/run_sim.ps1 -Quick -Tests @('tb_rhythm_panel','tb_rhythm_tails','tb_rhythm_raster','tb_hub75e_rhythm_display')
& ./android_app/build-apk.ps1 -OutputApk dist/FPGA-Music-Rhythm-Flick-Code44.apk
& ./tools/check_unified_build.ps1 -Label <新标签> -SynthesisOnly
& ./tools/resume_unified_pnr.ps1 -Label <新标签>
```

![实际外部RGB/PWM扫描仿真，放大8倍](rhythm_flick_x8.png)
'''
(report / 'README.md').write_text(readme, encoding='utf-8')
current = '**2026-10-28 当前为Code44粉色阶梯版。** FLICK已按图改为5×2像素阶梯，上排右3点、下排左3点；TAP及底部十二键仍宽5像素。'
entries = {
    project.parent / 'README.md': current+f'50MHz零时序违例，剩{remaining} CLS，BSRAM{resources['BSRAM']['used']}/{resources['BSRAM']['total']}；默认APK/位流已同步，未安装或烧录。见[用法](pcm5102_pam8403/RHYTHM_GAME.md)与[交付/预览](pcm5102_pam8403/reports/rhythm_flick_shape_20261028/README.md)。以下Code43及更早内容为历史记录。',
    project / 'README.md': current+f'App 1.43-rhythm-flick；{summary}未上板。见[用法](RHYTHM_GAME.md)与[交付/预览](reports/rhythm_flick_shape_20261028/README.md)。以下为历史记录。',
    project / 'VERIFICATION.md': '**2026-10-28 Code44 粉色阶梯修正：** '+summary+f"BSRAM{resources['BSRAM']['used']}/{resources['BSRAM']['total']}。"+'外部扫描轮廓/跨区/滚动/清屏、尾条及旧扫描、App构建与遥测、路由后40组扫描均通过；未安装或烧录。见[本轮报告](reports/rhythm_flick_shape_20261028/README.md)。以下为历史轮次。',
    project / 'android_app/README.md': '**2026-10-28 当前安装包：1.43-rhythm-flick / Code44。** [Code44 APK](dist/FPGA-Music-Rhythm-Flick-Code44.apk)与默认Unified.apk相同。配套位流将粉色FLICK改为5×2阶梯形；TAP与十二个底键保持5像素宽，App说明同步更新。见[用法](../RHYTHM_GAME.md)及[验证/预览](../reports/rhythm_flick_shape_20261028/README.md)。未安装手机。以下为此前版本记录。',
}
for path, paragraph in entries.items():
    text = path.read_text(encoding='utf-8')
    if paragraph not in text:
        path.write_text(paragraph+'\n\n'+text, encoding='utf-8', newline='\r\n')
print(json.dumps({k:release[k] for k in ('label','resources','remaining_cls','setup_slack_ns','hold_slack_ns','outputs')}, indent=2))
