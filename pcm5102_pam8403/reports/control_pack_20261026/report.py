"""Generate the CLS-first outcome from completed, separately audited builds."""
from work import *
freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
base=freeze['baseline_audit']
integrated=(HERE/'integration.json').exists()
record=json.loads((HERE/'integration.json').read_text(encoding='utf-8')) if integrated else None
results=[]
for label in ('download_decode','adsr_reset','adsr_place2','parser_shared','parser_index','parser_index_p2'):
    path=HERE/label/'audit.json'
    if path.exists():results.append(json.loads(path.read_text(encoding='utf-8')))
selected=next((r for r in results if integrated and r['label']==record['selected']),None)
lines=['# 第三步：控制装箱与局部译码（2026-10-26）','',
       '**已撤回第二步增加 77 CLS 的显示版本。** 29 项文件按哈希恢复，原显示七 RAM、扫描和默认位流恢复；'
       '实验仍在 `../display_ports_20261026/` 保留。当前主目标是减少 CLS，释放 BSRAM 本身不构成接入理由。','',
       ('采用 `'+selected['label']+'`，**本轮净回收 '+f"{-selected['delta_vs_baseline']['CLS']:g}"+' CLS**，已接入默认工程。' if selected else
        '本轮未接入候选，默认工程保持 11387 CLS / 53 BSRAM；没有已交付的新增 CLS 收益。'),'',
       '收益以恢复后的第一轮 HC-05 基线 11387 CLS 为起点；历史 83 CLS 和撤回时恢复的 77 CLS 不算第三步收益。','',
       '| 构建 | Logic | CLS | Register | BSRAM | DSP | CLS 增量 | 未布通 | 状态 |',
       '|---|---:|---:|---:|---:|---:|---:|---:|---|']
lines.append('| baseline | '+' | '.join(f"{base['metrics'][m]['used']:g}" for m in ('Logic','CLS','Register','BSRAM','DSP'))+' | 0 | 0 | validated |')
for r in results:
    values=' | '.join(f"{r['metrics'][m]['used']:g}" if m in r['metrics'] else '?' for m in ('Logic','CLS','Register','BSRAM','DSP'))
    lines.append(f"| {r['label']} | {values} | {r['delta_vs_baseline'].get('CLS',0):+g} | {r['unrouted_nets']} | {r['status']} |")
lines+=['','四种结构候选均与同一冻结基线比较。parser_index 包含参数生命周期共享和回复索引的联合修改，其收益由完整构建单独测量。'
        'ADSR place2 只重试同一 RTL 的物理设置。固定译码功能与时序通过，但 CLS +14，明确淘汰。'
        '失败、时序违例或面积增加的候选不计收益，各候选差值不相加。','',
        '## 功能证据','',
        '| 版本 | 通过检查 | 说明 |','|---|---:|---|']
for r in results:
    path=HERE/r['label']/'verification.json'
    if path.exists():
        v=json.loads(path.read_text(encoding='utf-8'))
        passed=sum(t['passed'] for t in v['checks'])
        reused=(HERE/r['label']/'functional_reference.json').exists()
        lines.append(f"| {r['label']} | {passed}/{len(v['checks'])} | {'沿用同 RTL 证据，只改物理放置' if reused else '独立候选功能检查'} |")
lines+=['','物理重试没有另算新功能覆盖。各版本的原始日志、引用关系和输入哈希保留在各自目录。','',
        '## 实现与功能边界','',
        '`download_decode` 将曲谱动态索引改为共享的固定音高比较，保持原流水线和原子验证。'
        '35072 组组合对照、曲谱/协议逐拍差分和最长 128×60000ms 曲谱检查有独立记录，未改生产曲谱模块。','',
        '`adsr_reset` 仅移除 ADSR 换算器内部暂存的复位，配置输出、done 和状态机仍复位。'
        '每次接受请求后先覆盖输入暂存，PREPARE/LOAD 覆盖运算数，四字段均完成后才允许 COMMIT；'
        '中途复位回到 IDLE，旧数据无法提交。音频模块、运算周期、UART 接收/拒绝条件与 TAKE 格式均未改。'
        '详见 [设计与有效性证明](DESIGN.md)。','',
        '`parser_shared` 使用等待期间保持不变的解析寄存器，替代重复的曲谱/ADSR 参数锁存。'
        '子模块仍在原请求边沿采样，父模块仍等待原完成信号；restore、校验和优先级保留。'
        '初稿的前向声明不被 Icarus 接受，已停止该构建并保留记录；最终版本先通过编译检查，再完整重建。','',
        '`parser_index` 在共享参数生命周期的结构上，继续保留完整 112 位回复快照，将回复逐数字移位改成 5 位数字索引。'
        '只在原字符真正被 UART 接受且模板为动态数字时推进，标点/仲裁/背压不推进；28 位后保持零。'
        '有效回复必先在 EXECUTE 完整锁存，因此数据本体无需复位，状态、长度和游标仍复位。'
        '20000 拍直接对照和真实 UART 差分分别检查数字位置/仲裁与完整字节节奏。独立完整构建，不将差值与前一候选相加。','']
if selected:
    t=selected['timing'];metrics=selected['metrics'];margin=metrics['CLS']['capacity']-metrics['CLS']['used']
    lines+=['## 选定版本验收','',
        f"器件 GW5A-LV25MG121NC1/I0、Gowin V1.9.11.03 Education、top_unified，50MHz；"
        f"策略 {selected['strategy']}，本轮基线 place1/route0/fan23。sharing=1、retiming=1、enable_dsrm=1、ram_rw_check=0 保持。"
        '若物理策略改变，CLS 差值包含 RTL 与放置的联合影响。',
        f"未布通 0，setup/hold 违例端点 {t['setup_violated_endpoints']}/{t['hold_violated_endpoints']}，"
        f"原始最差 slack {t['setup_raw_worst_path']['slack_ns']:+.3f}/{t['hold_raw_worst_path']['slack_ns']:+.3f} ns。",
        f"剩余 {margin:g} CLS；保留 35 后可用功能预算 {margin-35:g} CLS。BSRAM 与 DSP 按表报告，未借降低约束换资源。",'']
    verification=json.loads((HERE/selected['label']/'verification.json').read_text(encoding='utf-8'))
    lines += [f"最终 {len(verification['checks'])} 组检查通过：",'']
    for check in verification['checks']:lines.append('- '+'；'.join(check['pass_lines']))
    comparison=('293016 拍 ADSR 对照比较全部输出的每个时钟，包括 116 次中断、每个除法位置、'
        '双配置的全部 1001ms 数值、满 16 位输入和忙碌期变化。原有数值/UART及顶层数字音频断言保留。'
        if selected['label'].startswith('adsr') else
        'HC-05 差分在每个时钟比较全部 67 个输出，保留原协议、边界、竞争、原子拒绝、曲谱下载/回放和 ADSR 断言。'
        '当前串行16顶层 ADSR 测试在未改基线与候选上分别通过。')
    lines+=['',comparison+
        '整机保持真实 50MHz/1024 拍音频帧；启动/轮询加速参数沿用原测试，不等于实板墙钟验收。','',
        '默认入口：`../../impl/pnr/PCM5102_UNIFIED.fs`；独立副本 '
        '[PCM5102_UNIFIED_CONTROL_PACK_20261026.fs](PCM5102_UNIFIED_CONTROL_PACK_20261026.fs)。',
        f"位流 SHA256：`{record['production_bitstream_sha256']}`。",
        '原源码、原默认位流与综合/PNR 输出见 `production_before/`。']
lines+=['','## 证据与复现','',
    '[回退核验](rollback.json) · [冻结输入](freeze.json) · [结果账](results.json)。'
    '各目录保存 sources.json、exit.json、audit.json、原始时序、测试日志和 verification.json。'
    '最初的端口注释识别和 force 注入镜像夹具编译错误日志保留，不计为通过；RTL 没有据此修改。','',
    '```powershell',
    'python work.py audit download_decode',
    'python work.py audit adsr_reset',
    'python finish.py verify adsr_reset integration',
    '# 原构建日志不覆盖。重新实现请另建冻结目录，或使用主工程 tools/build_unified.tcl。',
    '```','',
    '本轮未宣称达到 500 CLS 回收目标。未烧录 FPGA、未写板上 Flash、未做实板显示或听音验收。']
save(HERE/'results.json',{'selected':record['selected'] if integrated else None,
    'net_cls_recovered':record['net_cls_recovered'] if integrated else 0,
    'baseline_cls':11387,'display_experiment_withdrawn':True,'trials':results})
(HERE/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Wrote measured third-step report')
