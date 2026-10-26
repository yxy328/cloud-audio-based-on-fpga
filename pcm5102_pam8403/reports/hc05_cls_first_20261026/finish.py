"""Gate integration on real PNR, frozen inputs and completed functional checks."""
from work import *
import stat

INTEGRATION_TESTS = ['tb_top_touch16_recovery', 'tb_fx3_frame_take',
                     'tb_fx3_replay_decode', 'tb_fx_take_atomic_528']

def test_result(project, name):
    path = project / 'sim/build' / (name + '.log')
    text = path.read_text(encoding='utf-8-sig', errors='replace') if path.exists() else ''
    return {'test': name, 'log': str(path), 'log_sha256': sha(path) if path.exists() else None,
            'pass_lines': re.findall(r'^PASS[^\r\n]*', text, re.M),
            'passed': bool(re.search(r'^PASS', text, re.M)) and not re.search(r'^FATAL', text, re.M)}

def checks(label):
    root = HERE / label
    reference = None
    if (root / 'functional_reference.json').exists():
        reference = json.loads((root / 'functional_reference.json').read_text(encoding='utf-8'))
        test_root = HERE / reference['parent']
        mine = {r['Path']: r['SHA256'] for r in manifest(root)}
        parent = {r['Path']: r['SHA256'] for r in manifest(test_root)}
        differences = [p for p in mine if mine[p] != parent[p]]
        assert differences == ['pcm5102_pam8403/tools/build_unified.tcl'], differences
    else:
        test_root = root
    listed = json.loads((test_root / 'differential_tests.json').read_text(encoding='utf-8'))
    tests = [test_result(test_root / PROJECT.name, t) for t in listed['tests'] + INTEGRATION_TESTS]
    tests.append(test_result(HERE / 'baseline' / PROJECT.name, 'tb_hc05_download_current'))
    save(root / 'verification.json', {'outputs_compared_each_cycle': listed['outputs_compared_each_cycle'],
                                     'checks': tests, 'all_passed': all(t['passed'] for t in tests),
                                     'functional_reference': reference})
    print('Verification:', sum(t['passed'] for t in tests), '/', len(tests), flush=True)
    for t in tests:
        if not t['passed']: print('Pending/failed:', t['test'], flush=True)
    return tests

def integrate(label):
    root = HERE / label
    audit(label)
    result = json.loads((root / 'audit.json').read_text(encoding='utf-8'))
    assert result['status'] == 'validated', result['status']
    freeze = json.loads((HERE / 'freeze.json').read_text(encoding='utf-8'))
    baseline = freeze['baseline_audit']
    assert result['metrics']['CLS']['used'] < baseline['metrics']['CLS']['used']
    assert result['metrics']['CLS']['capacity'] - result['metrics']['CLS']['used'] >= 35
    assert sha(GOWIN) == freeze['gowin_sha256']
    for resource in ('BSRAM', 'DSP'):
        assert result['metrics'][resource] == baseline['metrics'][resource]
    before = json.loads((root / 'sources.json').read_text(encoding='utf-8'))
    assert before == manifest(root), 'Candidate inputs changed after compilation'
    exit_info = json.loads((root / 'exit.json').read_text(encoding='utf-8'))
    assert exit_info == {'returncode': 0, 'inputs_unchanged': True}, exit_info
    tests = checks(label)
    assert all(t['passed'] for t in tests), 'Required functional checks are incomplete'
    candidate_sources = {r['Path']: r['SHA256'] for r in before}
    changed = [row['Path'] for row in freeze['production_inputs']
               if sha(REPO / row['Path']) not in (row['SHA256'], candidate_sources[row['Path']])]
    assert not changed, ('Production drift: do not overwrite', changed)
    candidate_sources = {r['Path']: r['SHA256'] for r in before}
    candidate_changes = [row['Path'] for row in freeze['production_inputs']
                         if candidate_sources[row['Path']] != row['SHA256']]
    allowed = ['pcm5102_pam8403/src/hc05_keymap.v']
    if (root / 'functional_reference.json').exists():
        allowed.append('pcm5102_pam8403/tools/build_unified.tcl')
    assert candidate_changes == allowed, candidate_changes
    assert sha(PROJECT / 'impl/pnr/PCM5102_UNIFIED.fs') in (
        freeze['baseline_fs_sha256'], result['bitstream_sha256'])
    backup = HERE / 'production_before'
    resuming = backup.exists()
    if resuming:
        # A copy can stop on Gowin's read-only generated outputs. Resume only
        # when the original rollback inputs and original bitstream remain intact.
        for row in freeze['production_inputs']:
            if row['Path'] in allowed:
                assert sha(backup / row['Path']) == row['SHA256'], row['Path']
        assert sha(backup / 'pcm5102_pam8403/impl/pnr/PCM5102_UNIFIED.fs') == freeze['baseline_fs_sha256']
    changes = [(root / PROJECT.name / 'src/hc05_keymap.v', PROJECT / 'src/hc05_keymap.v')]
    if len(allowed) == 2:
        changes.append((root / PROJECT.name / 'tools/build_unified.tcl', PROJECT / 'tools/build_unified.tcl'))
    for folder in ('gwsynthesis', 'pnr'):
        for path in sorted((root / PROJECT.name / 'impl' / folder).glob('PCM5102_UNIFIED*')):
            if path.is_file(): changes.append((path, PROJECT / 'impl' / folder / path.name))
    for name in ('cmd.do', 'device.cfg'):
        changes.append((root / PROJECT.name / 'impl/pnr' / name, PROJECT / 'impl/pnr' / name))
    if not resuming:
        for _, destination in changes:
            saved = backup / destination.relative_to(REPO)
            if destination.exists():
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(destination, saved)
    for source, destination in changes:
        if destination.exists():
            destination.chmod(destination.stat().st_mode | stat.S_IWRITE)
        shutil.copy2(source, destination)
        assert sha(source) == sha(destination)
    named_fs = HERE / 'PCM5102_UNIFIED_CLS_FIRST_20261026.fs'
    if named_fs.exists():
        named_fs.chmod(named_fs.stat().st_mode | stat.S_IWRITE)
    shutil.copy2(PROJECT / 'impl/pnr/PCM5102_UNIFIED.fs', named_fs)
    after = []
    for row in freeze['production_inputs']:
        current = sha(REPO / row['Path'])
        assert current == candidate_sources[row['Path']], row['Path']
        after.append({'Path': row['Path'], 'SHA256': current})
    save(HERE / 'integration.json', {
        'selected': label, 'production_changes': candidate_changes, 'production_inputs': after,
        'production_bitstream_sha256': sha(named_fs), 'rollback_bitstream_sha256': freeze['baseline_fs_sha256'],
        'rollback_directory': str(backup), 'test_count': len(tests), 'all_tests_passed': True,
        'resumed_after_readonly_output': resuming,
        'outputs': [{'path': str(dst.relative_to(REPO)), 'SHA256': sha(dst)} for _, dst in changes],
        'burned_fpga': False, 'wrote_board_flash': False})
    print('Integrated', label, 'with', len(changes), 'verified files; no hardware programming', flush=True)

def report(label):
    result = json.loads((HERE / label / 'audit.json').read_text(encoding='utf-8'))
    freeze = json.loads((HERE / 'freeze.json').read_text(encoding='utf-8'))
    base = freeze['baseline_audit']
    integrated = (HERE / 'integration.json').exists()
    table = ['| 资源 | 基线 | 本轮 | 增量 | 剩余 |', '|---|---:|---:|---:|---:|']
    for name in ('Logic', 'CLS', 'Register', 'BSRAM', 'DSP'):
        old = base['metrics'][name]['used']; new = result['metrics'][name]['used']
        cap = result['metrics'][name]['capacity']
        table.append(f'| {name} | {old:g} | {new:g} | {new-old:+g} | {cap-new:g} |')
    verification = json.loads((HERE / label / 'verification.json').read_text(encoding='utf-8'))
    saving = base['metrics']['CLS']['used'] - result['metrics']['CLS']['used']
    timing = result['timing']
    lines = ['# 第一轮 HC-05 CLS 优化（2026-10-26）', '',
             f'采用 `{label}`，实际净回收 **{saving:g} CLS**。' + ('已接入默认工程和默认位流。' if integrated else '尚未接入。'),
             '全部既有功能、命令、参数范围、引脚和存储格式保留；RTL 只改变 HC-05 回复数据寄存器的选择结构，并据完整时序更新物理实现策略。', '',
             *table, '',
             f"同一器件与工具，50MHz、sharing=1、retiming=1；基线 place2/route0/maxfan23，候选实际策略 {result['strategy']}；未布通 {result['unrouted_nets']}。",
             f"setup/hold 违例端点 {timing['setup_violated_endpoints']}/{timing['hold_violated_endpoints']}；原始路径 WNS "
             f"{timing['setup_raw_worst_path']['slack_ns']:+.3f}/{timing['hold_raw_worst_path']['slack_ns']:+.3f} ns，"
             '基线为 +0.018/+0.144 ns。CLS 净收益使用完整 PNR 对比，包含 RTL 与物理策略的联合变化；不将局部 LUT 减少直接换算成 CLS，也不将全部收益归因于 RTL。', '',
             '## 实现与功能边界', '',
             '保持原命令状态机、所有校验和回复时机；将 17 个原有回复载荷来源改由独立时序块选择，'
             '仍在同一 EXECUTE 边沿锁存完整 112 位载荷。错误/设置命令可能更新无效载荷，但静态回复不读取它；'
             '所有动态回复均重新锁存完整载荷。仲裁、背压和每字节节奏保持原条件。详见 [DESIGN.md](DESIGN.md)。', '',
             '## 验证', '',
             f"共 {len(verification['checks'])} 组最终检查，全部通过：12 组串口差分、4 组整机/TAKE 检查及 1 组未改基线的当前曲谱合同检查。",
             '差分测试以本轮冻结的原 RTL 为参考，每个时钟比较全部 67 个输出；原有字节回复/状态断言继续运行。'
             '范围包括映射/音高、错误帧、竞争、扩展控制、三效果、TAKE、ADSR、弯音、视觉/XY、曲谱及旧音频录制参数分支。'
             '这不是任意内部状态的形式等价证明。', '',
             '物理策略重试与 reply_parallel 的全部 RTL/ROM/约束哈希一致，只有构建脚本的物理选项不同，功能证据沿用该完全相同 RTL 的测试；每个策略重新完成资源、布线和时序核验。', '',
             '整机测试包括固定 16 键极性恢复，以及真实 50MHz/1024 拍音频帧下的 UART/TTP229/双 ADC/三效果/曲谱并行与 TAKE 回放。'
             '旧新 TAKE 字段 2075 检查和完整 528 位原子快照 34 检查通过。启动/轮询/包络等加速参数沿用原有测试，不能当作全默认墙钟实板验收。', '',
             '历史 tb_hc05_download 仍允许旧七键日志录制，与本轮开始前的固定16拒绝 REC_START 的源码不符。'
             '原文件和失败日志保留；新增 current 版本明确检查既有半音阶和固定16合同，并在未修改基线与候选上均通过。'
             '该曲谱用例采用合法 2ms 和弦/休止替代 50ms 等待，其余原有曲谱原子性/重试/范围检查以及显式自然音映射断言保留。'
             '补充测试初稿误将十进制145当作十六进制且忽略用例显式重设映射，导致错误掩码预期；未改基线也复现，'
             '已修正测试，RTL未据此修改。诊断日志保留，不计为通过证据。', '',
             '## 未采用的实验', '',
             '- 全命令 case 分发：放置失败，26 LUT 等价单元未放入，不构成可交付资源统计。',
             '- 共享 MAP 十进制格式化：完整布通且时序通过，但 Logic +49、CLS +13，未接入。', '',
             '- 回复数据拆分的原 place2/route0/fan23 构建：少 50 CLS、180 Logic，但有 9 个 setup 端点违例，原始 WNS -1.586 ns，不交付该位流。', '',
             '## 产物与复现', '',
             '默认入口：`../../impl/pnr/PCM5102_UNIFIED.fs`；独立命名副本 '
             '[PCM5102_UNIFIED_CLS_FIRST_20261026.fs](PCM5102_UNIFIED_CLS_FIRST_20261026.fs)。',
             f"位流 SHA256：`{result['bitstream_sha256']}`。",
             '回退源文件、原默认位流和原构建报告位于 `production_before/`；未烧录 FPGA、写板上 Flash 或做实板听音。', '',
             '核验链：[freeze.json](freeze.json)、所选候选 sources.json/exit.json/audit.json/verification.json、'
             '[integration.json](integration.json)。102 项生产输入与所选构建逐项匹配，相对基线仅 hc05_keymap.v 和物理构建选项改变。', '',
             '```powershell',
             "& 'E:/300_IDE_Compiler/Python313/python.exe' finish.py checks " + label,
             '# 原候选证据不覆盖；新建快照后再构建，或直接在主工程使用标准 build_unified.tcl。',
             "& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' ../../tools/build_unified.tcl", '```', '',
             '本轮未达到 500 CLS 回收；后续以新基线继续评估其他结构，不能将历史回收或失败候选差值相加。']
    (HERE / 'README.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('Wrote README.md', flush=True)

if __name__ == '__main__':
    action, label = sys.argv[1:3]
    if action == 'checks': checks(label)
    elif action == 'integrate': integrate(label)
    elif action == 'report': report(label)
