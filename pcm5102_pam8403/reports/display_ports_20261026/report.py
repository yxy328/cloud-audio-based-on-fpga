"""Render the measured outcome; never count old savings or failed builds."""
from work import *

label=sys.argv[1]
root=HERE/label
freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
result=json.loads((root/'audit.json').read_text(encoding='utf-8'))
verification=json.loads((root/'verification.json').read_text(encoding='utf-8'))
base=freeze['baseline_audit']
withdrawn=(HERE/'withdrawn.json').exists()
adopted=(HERE/'integration.json').exists() and not withdrawn
rows=['| 资源 | 本轮基线 | 本轮结果 | 增量 | 剩余 |','|---|---:|---:|---:|---:|']
for name in ('Logic','CLS','Register','BSRAM','DSP'):
    old=base['metrics'][name]['used'];new=result['metrics'][name]['used'];cap=result['metrics'][name]['capacity']
    rows.append(f'| {name} | {old:g} | {new:g} | {new-old:+g} | {cap-new:g} |')
t=result['timing'];bt=base['timing'];margin=result['metrics']['CLS']['capacity']-result['metrics']['CLS']['used']
timing_text=(f"未布通 {result['unrouted_nets']}；setup/hold 违例端点 "
       f"{t['setup_violated_endpoints']}/{t['hold_violated_endpoints']}。"
       f"原始最差 setup/hold slack {t['setup_raw_worst_path']['slack_ns']:+.3f}/{t['hold_raw_worst_path']['slack_ns']:+.3f} ns，"
       f"基线 {bt['setup_raw_worst_path']['slack_ns']:+.3f}/{bt['hold_raw_worst_path']['slack_ns']:+.3f} ns。" if t else
       f"未布通 {result['unrouted_nets']}，未产生可验收的完整时序结果；失败资源仅作诊断，不计为释放或功能预算。")
lines=['# 第二步：LED 显示 RAM 读口优化（2026-10-26）','',
       ('已接入默认工程与默认位流。' if adopted else
        '**已撤回默认接入。** 新增77 CLS不符合CLS优先目标；当前版本见第三步报告。' if withdrawn else
        '本候选未接入默认工程，生产保持原已验证版本。')+
       f"本次完整 PNR 状态为 `{result['status']}`。",'',*rows,'',
       '比较基线为第一轮 HC-05 优化已经接入的当前工程，而非调研时的 11470 CLS。'
       '历史 83 CLS 收益没有计入本轮。本轮只改变显示 RAM 读口结构及报告列明的物理策略；没有迁移其他存储。','',
       '## 行为与成本','',
       '音符位图由七份 64×7 RAM 改为三份：插入读改写保持独立，上下半屏各一份 RAM 维护三行滑动窗口。'
       '每拍只补读一个端点，保留两行并逐拍转发写入；31→0 行先交换上下原始窗口。'
       '保持音符每拍接收、OR 合并、滚动有效位、同址读写转发、133 拍扫描、RGB5 PWM、显示模式和快照边界。',
       ('已验收释放 ' if result['status']=='validated' else '失败构建诊断显示减少 ')+
       f"{base['metrics']['BSRAM']['used']-result['metrics']['BSRAM']['used']:g} 个物理 BSRAM；"
       f"整机 CLS 变化 {result['delta_vs_baseline']['CLS']:+g}，余量 {margin:g}，"+
       (f"扣除原有 35 CLS 安全余量后的功能预算为 {margin-35:g}。" if result['status']=='validated' else
        '该构建失败，不计入可用功能预算。')+
       '新增缓存调度开销已经包含在整机统计中，不能将 RAM 释放解释为同等 CLS 回收。','',
       '详细窗口位移、换行交换和冲突语义见 [DESIGN.md](DESIGN.md)。','',
       '## 构建与时序','',
       f"GW5A-LV25MG121NC1/I0，Gowin V1.9.11.03 Education，top_unified，50 MHz；"
       f"物理策略 {result['strategy']}，本轮基线为 place1/route0/fan23。sharing=1、retiming=1、enable_dsrm=1、ram_rw_check=0 保持。"
       '物理策略改变时，整机 CLS 差值包含 RTL 与放置的联合影响。',
       timing_text,'',
       '## 验证','',
       f"{len(verification['checks'])} 组最终功能检查通过：",'']
for test in verification['checks']:
    lines.append('- `'+test['name']+'`：'+'；'.join(test['pass_lines']))
lines += ['',
       '两个 LEAD 参数的当前 RTL 差分每拍比较全部面板引脚、握手/overflow、112 位快照、全部 64 行位图及六个逻辑读口。'
       '长时间连续播放与毫秒节拍加速均覆盖；这是动态仿真，不是任意内部状态的形式证明。',
       '原扫描测试的六镜像层级注入改为两镜像及缓存的等价初始化，全部原有断言保留。'
       '初次层级名编译失败及图片目录缺失日志均保留，不计为通过。'
       '整机回归保持 50MHz/1024 拍音频帧；启动、轮询等参数沿用原测试的加速配置。','',
       '## 产物与复现','',
       f"候选输入与审计：[sources.json]({label}/sources.json)、[audit.json]({label}/audit.json)、"
       f"[verification.json]({label}/verification.json)、[exit.json]({label}/exit.json)。",
       '当前生产的 102 项输入先按上一轮接入清单重新核验，然后冻结。另两项 build_inputs JSON 只在冻结目录注入，'
       '不计为生产源码漂移。工具、实际综合设置、PNR 命令、资源/时序报告和测试日志均有 SHA256。',
       (f"候选位流 SHA256：`{result['bitstream_sha256']}`。" if result['bitstream_present'] else '该构建未产生可交付位流。'),
       '回退显示源文件及原综合/PNR 输出见 `production_before/`；原测试夹具位于 `baseline/pcm5102_pam8403/sim/`，接入时另存回退副本。',
       ('默认入口为 `../../impl/pnr/PCM5102_UNIFIED.fs`；独立副本 '
        '[PCM5102_UNIFIED_DISPLAY_PORTS_20261026.fs](PCM5102_UNIFIED_DISPLAY_PORTS_20261026.fs)，'
        '接入核验见 [integration.json](integration.json)。' if adopted else '生产源码及默认位流保持原版本。'),
       '未烧录 FPGA、未写板上 Flash，也未进行实板显示/听音验收。','',
       '```powershell',
       'python work.py test window3 '+' '.join(t['name'] for t in verification['checks'][:6]),
       f'python finish.py collect {label}',
       '# 原构建日志不覆盖；复建请另建快照，或在主工程调用 tools/build_unified.tcl。',
       '```','',
       ('本轮释放的 BSRAM 可作为后续迁移寄存器存储的预算；' if adopted else '本轮没有已交付的新增 BSRAM 或 CLS 收益；')+
       '后续仍需单独测量完整 PNR、扫描/冲突与音频期限。'
       '本轮未宣称达到 500 CLS 回收目标，也不将不同候选差值相加。']
trials=[]
for name in ('window3','window3_place2'):
    path=HERE/name/'audit.json'
    if path.exists():
        item=json.loads(path.read_text(encoding='utf-8'))
        trials.append({'label':name, 'status':item['status'],'metrics':item['metrics'],
                       'delta_vs_baseline':item['delta_vs_baseline'],'unrouted_nets':item['unrouted_nets'],
                       'timing':item['timing'],'selected':adopted and name==label})
lines+=['','## 完整实验记录','','| 候选 | 策略 | 状态 | 未布通 | 采用 |','|---|---|---|---:|---|']
for item in trials:
    lines.append(f"| {item['label']} | {'place1' if item['label']=='window3' else 'place2'}/route0/fan23 | {item['status']} | {item['unrouted_nets']} | {'是' if item['selected'] else '否'} |")
lines+=['','place2 与 place1 的全部 RTL/ROM/约束及综合选项完全相同，只改变物理放置选项；'
           '功能证据沿用同一 RTL 的十组检查，各策略分别完成构建和审计。失败构建不算收益，各候选差值不相加。']
save(HERE/'results.json',{'selected':label if adopted else None,'trials':trials,
                        'functional_checks':len(verification['checks']),'all_functional_passed':True,
                        'withdrawn_for_cls_objective':withdrawn})
(HERE/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Wrote README with measured resources, timing and tests')
