"""Publish only the frozen, routed and font-checked score-display repair."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import runpy
import shutil
import stat
import tempfile

project = Path.cwd().resolve()
assert project.name == 'pcm5102_pam8403'
parser = argparse.ArgumentParser()
parser.add_argument('--label', required=True)
parser.add_argument('--route-log', required=True)
parser.add_argument('--extra-source', action='append', default=[])
args = parser.parse_args()
assert re.fullmatch(r'[a-zA-Z0-9_-]+', args.label)
report = project / 'reports/score_visible_20261028'
snapshot = project / 'sim/build/unified' / args.label
target = snapshot / project.name
pnr = target / 'impl/pnr'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def copy(a, b):
    assert b.resolve().is_relative_to(project)
    b.parent.mkdir(parents=True, exist_ok=True)
    if b.exists() and sha(a) == sha(b):
        return
    fd, temp = tempfile.mkstemp(prefix='score-visible-', dir=str(b.parent))
    temp = Path(temp)
    try:
        with a.open('rb') as source, os.fdopen(fd, 'wb') as output:
            shutil.copyfileobj(source, output, 1024*1024)
        if b.exists():
            b.chmod(stat.S_IREAD | stat.S_IWRITE)
        os.replace(temp, b)
        shutil.copystat(a, b)
    finally:
        if temp.exists():
            temp.chmod(stat.S_IREAD | stat.S_IWRITE)
            temp.unlink()


inputs = json.loads((snapshot / 'sources.json').read_text(encoding='utf-8-sig'))
old_inputs = json.loads((project / 'sim/build/unified/score256_46e/sources.json').read_text(encoding='utf-8-sig'))
old_hashes = {e['Path']: e['SHA256'] for e in old_inputs}
changes = []
for e in inputs:
    rel = Path(e['Path'])
    assert sha(snapshot / rel) == e['SHA256'], rel
    if rel.parts[0] in ('pcm5102_pam8403', 'pmod_hub75e') and 'tools' not in rel.parts:
        assert sha(project.parent / rel) == e['SHA256'], rel
    if e['Path'] in old_hashes and old_hashes[e['Path']] != e['SHA256']:
        changes.append(e['Path'])
assert sorted(changes) == sorted([r'pcm5102_pam8403\src\hub75e_rhythm_display.v'] + args.extra_source), changes

route_log_path = report / args.route_log
route_log = route_log_path.read_text(encoding='utf-8-sig')
assert 'Placement and routing completed' in route_log and 'Bitstream generation completed' in route_log
assert 'ERROR' not in route_log
assert 'PASS routed HUD font:' in route_log
assert (pnr / 'PCM5102_UNIFIED.fs').stat().st_mtime >= (target / 'tools/resume_pnr.tcl').stat().st_mtime
assert (pnr / 'PCM5102_UNIFIED.vo').stat().st_mtime >= (pnr / 'PCM5102_UNIFIED.fs').stat().st_mtime
pnr_tcl = (target / 'tools/resume_pnr.tcl').read_text(encoding='utf-8-sig')
place = int(re.findall(r'-place_option\s+(\d+)', pnr_tcl)[-1])
rpt = (pnr / 'PCM5102_UNIFIED.rpt.txt').read_text()
resources = {}
for name in ('Logic', 'CLS', 'Register', 'BSRAM', 'DSP'):
    a, b = re.search(r'^  '+name+r'\s+\|\s*(\d+(?:\.\d+)?)/(\d+)', rpt, re.M).groups()
    resources[name] = dict(used=int(a) if '.' not in a else float(a), total=int(b))
    assert float(a) <= int(b)
sta = (pnr / 'PCM5102_UNIFIED_tr_content.html').read_text()
slacks = {}
for kind in ('Setup', 'Hold'):
    slacks[kind] = float(re.search('name="'+kind+r'_Slack_Table".*?<td>1</td>\s*<td>([^<]+)', sta, re.S).group(1))
    assert slacks[kind] >= 0
section = sta.split('name="Total_Negative_Slack_Report"', 1)[1].split('<h1', 1)[0]
violations = re.findall(r'<tr>\s*<td>([^<]+)</td>\s*<td>(Setup|Hold)</td>\s*<td>([^<]+)</td>\s*<td>(\d+)</td>', section)
assert len(violations) == 4 and all(float(v[2]) == 0 and int(v[3]) == 0 for v in violations), violations

probe = report / 'display_probe'
for file in ('hub75e_rhythm_display.v', 'rhythm_game.v', 'rhythm_font.hex', 'rhythm_points.hex', 'rhythm_stats.hex', 'rhythm_judge.hex'):
    assert sha(probe / 'src' / file) == sha(target / 'src' / file), file
assert 'PASS routed display HUD:' in (probe / 'gate_check.log').read_text(encoding='utf-8-sig')
assert 'PASS routed netlist scan:' in (report / 'routed_scan.log').read_text(encoding='utf-8-sig')
scan_proof = json.loads((report / 'routed_scan_provenance.json').read_text())
assert scan_proof['label'] == args.label
assert scan_proof['netlist_sha256'] == sha(pnr / 'PCM5102_UNIFIED.vo')
assert scan_proof['testbench_sha256'] == sha(project / 'sim/tb_rhythm_netlist.v')
assert scan_proof['log_sha256'] == sha(report / 'routed_scan.log')
assert (report / 'routed_scan.log').stat().st_mtime >= (pnr / 'PCM5102_UNIFIED.vo').stat().st_mtime
check = runpy.run_path(str(project / 'tools/check_rhythm_font_netlist.py'))['check']
check(pnr / 'PCM5102_UNIFIED.vo', target / 'src/rhythm_font.hex')
check(probe / 'impl/pnr/display_probe.vo', target / 'src/rhythm_font.hex')
font_cases = json.loads((report / 'font_probe/results.json').read_text())
assert font_cases['hex']['wrong_addresses'] == 106 and font_cases['hex']['lit_pixels'] == 0
assert font_cases['vector1bin']['wrong_addresses'] == 0 and font_cases['vector1bin']['lit_pixels'] == 106
rtl_tests = []
for name in ('tb_rhythm_panel', 'tb_rhythm_tails', 'tb_hub75e_rhythm_display'):
    log = project / ('sim/build/'+name+'_quick.log')
    text = log.read_text(encoding='utf-8-sig')
    assert 'PASS ' in text and 'FATAL' not in text
    copy(log, report / 'tests' / log.name)
    rtl_tests.append(dict(name=name, source_sha256=sha(project / 'sim' / (name+'.v')), log_sha256=sha(log)))
if any(p.endswith('downloadable_song.v') for p in changes):
    for name in ('tb_song_tick', 'tb_score256', 'tb_rhythm_top', 'tb_rhythm_types_top'):
        log = project / ('sim/build/'+name+'_quick.log')
        text = log.read_text(encoding='utf-8-sig')
        assert 'PASS ' in text and 'FATAL' not in text
        copy(log, report / 'tests' / log.name)
        rtl_tests.append(dict(name=name, source_sha256=sha(project / 'sim' / (name+'.v')), log_sha256=sha(log)))
if any(p.endswith('src\\top.v') for p in changes):
    name = 'tb_boot_reset'
    log = project / ('sim/build/'+name+'_quick.log')
    text = log.read_text(encoding='utf-8-sig')
    assert 'PASS boot reset:' in text and 'FATAL' not in text
    copy(log, report / 'tests' / log.name)
    rtl_tests.append(dict(name=name, source_sha256=sha(project / 'sim' / (name+'.v')), log_sha256=sha(log)))
old_release = json.loads((project / 'reports/score256_20261028/release.json').read_text())
previous_default_sha = sha(report / 'rollback_Code46/impl/pnr/PCM5102_UNIFIED.fs')
assert sha(project / 'impl/pnr/PCM5102_UNIFIED.fs') in (previous_default_sha, sha(pnr / 'PCM5102_UNIFIED.fs'))
assert sha(project / 'sim/build/unified/score256_46e/pcm5102_pam8403/impl/pnr/PCM5102_UNIFIED.fs') == old_release['bitstream_sha256']
assert sha(pnr / 'PCM5102_UNIFIED.fs') != old_release['bitstream_sha256']
assert sha(pnr / 'PCM5102_UNIFIED.fs') != previous_default_sha

output = report / 'PCM5102_UNIFIED_SCORE_VISIBLE_FIX.fs'
copy(pnr / 'PCM5102_UNIFIED.fs', output)
for kind in ('gwsynthesis', 'pnr'):
    for file in (target / 'impl' / kind).rglob('*'):
        if file.is_file():
            copy(file, project / 'impl' / kind / file.relative_to(target / 'impl' / kind))
for name in ('PCM5102_UNIFIED.rpt.txt', 'PCM5102_UNIFIED.rpt.html', 'PCM5102_UNIFIED.tr.html', 'PCM5102_UNIFIED_tr_content.html', 'PCM5102_UNIFIED_tr_cata.html'):
    copy(pnr / name, report / name)
copy(snapshot / 'sources.json', report / 'frozen_inputs.json')
copy(target / 'tools/build_unified.tcl', report / 'frozen_synthesis.tcl')
copy(target / 'tools/resume_pnr.tcl', report / 'frozen_pnr.tcl')
copy(route_log_path, report / 'final_pnr.log')
assert sha(output) == sha(project / 'impl/pnr/PCM5102_UNIFIED.fs')
remaining = resources['CLS']['total']-resources['CLS']['used']
release = dict(date='2026-10-28', label=args.label, firmware_revision='score-visible-fix', app_compatible='Code46, unchanged',
    device='GW5A-LV25MG121NC1/I0', target_mhz=50, place=place, route=0, maxfan=23, retiming=1, native_wide_bsram=True,
    resources=resources, remaining_cls=remaining, setup_slack_ns=slacks['Setup'], hold_slack_ns=slacks['Hold'], violations=violations,
    bitstream=dict(name=output.name, sha256=sha(output)), changed_frozen_inputs_from_code46=changes,
    previous_default_bitstream_sha256=previous_default_sha, code46_named_release_sha256=old_release['bitstream_sha256'],
    production_font='PASS all512 addresses,106 lit pixels,retained one-bit pROM',
    routed_display='PASS real TAP 001000/001 then002000/002,all512 top pixels RGB5 over32 PWM phases,133 clocks/row; isolated display+judge,not full audio top',
    routed_startup_scan='PASS40 external row pairs,64 columns,known RGB,blank/latch order,133 clocks/row', rtl_tests=rtl_tests,
    routed_startup_provenance=scan_proof,
    build_tools={p:sha(project / p) for p in ('tools/check_unified_build.ps1','tools/resume_unified_pnr.ps1','tools/check_rhythm_font_netlist.py')},
    programmed_fpga=False, physical_panel_verified=False, apk_changed=False)
(report / 'release.json').write_text(json.dumps(release, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
summary = f"Logic {resources['Logic']['used']}、CLS {resources['CLS']['used']}、Register {resources['Register']['used']}、BSRAM {resources['BSRAM']['used']}、DSP {resources['DSP']['used']}；剩{remaining} CLS。50MHz完整布通，setup/hold违例均0，最差余量 {slacks['Setup']:+.3f}/{slacks['Hold']:+.3f} ns。"
timing_note = ''
if any(p.endswith('downloadable_song.v') for p in changes):
    timing_note = '整机还移除了多时钟毫秒计数器终值检测中多余的复位门控，缩短上电复位到曲谱前瞻控制的路径；每毫秒只有一个时钟的参数配置仍保留门控。独立绝对时钟相位测试覆盖1/2/3/17/50000时钟及两次复位，整机TAP/HOLD/DRAG/FLICK和256条曲谱回归通过。'
if any(p.endswith('src\\top.v') for p in changes):
    timing_note = '整机还将上电复位终值解码寄存，移除高扇出复位信号前的组合解码；实际top模块测试确认仍在第63个时钟释放复位并保持释放，256个时钟全部一致。曲谱计时模块未改变。'
(report / 'README.md').write_text(f'''# 修复实屏没有得分：计分字库硬件修复版

2026-10-28。用户提供了PLAY/S1跟谱时的实屏照片，画面没有得分。问题来自字库的标量数组写法：`reg hud_font[0:511]` 在当前 Gowin V1.9.11.03 Education 中被综合为恒0。RTL仿真能画出数字，旧路由后测试只检查启动扫描，没有进入显示分数的状态，未捕获此问题。

## 交付

- [修复位流](PCM5102_UNIFIED_SCORE_VISIBLE_FIX.fs)，SHA256 `{sha(output)}`。
- [最终资源/时序/输入指纹](release.json)
- 当前默认 `impl/pnr/PCM5102_UNIFIED.fs` 已同步同一产物。

**App Code46无需更新。** 保留256条曲谱、384000满分、四类音符、5像素TAP/十二键和粉色阶梯。计分规则、协议、引脚及音频数据通路保持原样。未烧录开发板，尚未做实体LED确认。

## 修复与资源

字库改成显式一位向量 `reg [0:0]`，按一位二进制数据加载，读取时显式选bit0。另将音符层、HUD层的像素结果单独保留，避免综合时的额外逻辑展开；扫描仍为每行133时钟。

{timing_note}

{summary} BSRAM余{resources['BSRAM']['total']-resources['BSRAM']['used']}块。最终候选 `{args.label}`，place{place}/route0/maxfan23，原生32/36位BSRAM。

## 实际验证

- [最小字库硬件复现](font_probe/results.json)：旧标量数组在hex/binary两种加载下，106个应亮像素全部变为0；显式1位/4位向量，全部512地址零错误。原故障网表的像素输出直接接GND。
- [显示模块路由后测试](display_probe/gate_check.log)：使用真实判定模块触发两次TAP，逐像素核对001000/001→002000/002；覆盖顶部512个像素、全部32档PWM及133时钟扫描。它包含显示和计分模块，未冒充整机音频门级测试。
- [RTL显示回归](rtl_display.log)：TAP/完整HOLD尾条/DRAG/粉色阶梯、跨31/32行、滚动清屏、十二键各5像素，以及旧七列6174组参考扫描行通过。
- [整机路由后扫描](routed_scan.log)：40组外部64列RGB扫描、已知像素、消隐和LAT顺序通过。
- 最终整机网表内保留字库，全部512地址和106个应亮像素一致。新增 `tools/check_rhythm_font_netlist.py`，两种统一构建入口均自动执行，丢失或错误初始化的字库将使构建检查失败。

相对Code46冻结输入，FPGA修改清单见 `release.json` 的 `changed_frozen_inputs_from_code46`。没有重新声称整局256条、模拟音频或实体面板验收通过。

## 候选与回退

直接修复a恢复了字库，但整机综合Logic23083，超过23040；b/c调整重定时或字库宽度仍23083；d固定数字槽位23095；e层次属性未改善；g并行图层选择23129，均未交付。f保留各像素层结果后综合Logic22554、BSRAM55；place2完整布通但setup为-1.107ns，place1仍有294条连线未布通，均未交付。共享状态字库h停止；毫秒脉冲寄存版j虽通过相位测试，但Logic23218超限。最终只交付上文列出的通过资源、时序及字库检查的候选。

k移除多余节拍门控，通过了节拍、256条曲谱和两项整机音游RTL回归，但最终仍有262条连线未布通，未交付。r将复位终值解码寄存，完整布通并满足原50MHz约束，成为最终候选；f的place4尝试和更紧凑的上电计数器s在r通过后停止，未交付。完整日志保留在本目录。

`rollback_Code46/` 保存修复前默认位流、相关源码、构建工具及文档，保留了备份时的原样。该默认位流哈希与Code46命名交付记录不同，实际哈希分别记录在 `release.json` 的 `previous_default_bitstream_sha256` 和 `code46_named_release_sha256`；Code46命名交付仍保存在原冻结目录中。源代码比较以Code46的冻结输入为基线。恢复上述备份会撤回本次修复。没有Git提交、推送或烧录。

font_probe、display_probe、shared_probe、area_probe均为隔离实验；交付使用本目录命名的整机位流。
''', encoding='utf-8')
entries = {
    project.parent / 'README.md': '**2026-10-28 计分字库硬件修复版：** 已复现并修复“仿真有分数、实屏无分数”的字库综合缺陷。'+summary+'App Code46无需更新，保留256条曲谱。默认位流已同步，未上板验证。见[修复位流与验证](pcm5102_pam8403/reports/score_visible_20261028/README.md)。以下为此前记录。',
    project / 'README.md': '**2026-10-28 当前FPGA为计分字库修复版：** 修复标量字库在综合中变成恒0的问题，右上六位得分与左上连击恢复。'+summary+'App Code46无需更新；未烧录。见[交付与验证](reports/score_visible_20261028/README.md)。以下为历史记录。',
    project / 'VERIFICATION.md': '**2026-10-28 实屏计分字库修复：** '+summary+'最小硬件字库512地址、实际TAP后1000→2000的显示模块路由后RGB/PWM测试、RTL显示回归及整机启动扫描均通过。未做实物验收。见[报告](reports/score_visible_20261028/README.md)。以下为历史轮次。',
    project / 'RHYTHM_GAME.md': '**得分显示修复（2026-10-28）：** PLAY/S1跟谱时没有数字的字库综合缺陷已修复；请使用[计分字库修复位流](reports/score_visible_20261028/PCM5102_UNIFIED_SCORE_VISIBLE_FIX.fs)，App Code46无需更新。[硬件复现与验证](reports/score_visible_20261028/README.md)。\n',
}
for path, text in entries.items():
    old = path.read_text(encoding='utf-8-sig')
    if path.name == 'RHYTHM_GAME.md':
        old = old.replace('使用 Code44 APK 和配套位流', '使用 Code46 APK 和计分字库修复位流')
    if text not in old:
        path.write_text(text+'\n\n'+old, encoding='utf-8', newline='\r\n')
print(json.dumps(release, ensure_ascii=False, indent=2))
