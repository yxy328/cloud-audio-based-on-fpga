from delivery import *

rows=json.loads((HERE/'build_audit.json').read_text(encoding='utf-8'))
by={r['label']:r for r in rows}
final=json.loads((HERE/'final_production_audit.json').read_text(encoding='utf-8'))
assert final['status']=='validated'
assert by['fx_apds']['status'] not in ('incomplete','snapshot_integrity_failed')
reserve={'Logic':1650,'CLS':365,'BSRAM':4}
def used(row,key):return row['metrics'][key]['used']
def wns(row,kind='setup'):
    t=row.get('timing') or {}
    return (t.get(kind+'_raw_worst_path') or t.get(kind+'_worst_path') or {}).get('slack_ns')
def fmt(n):return f'{n:g}' if isinstance(n,(int,float)) else str(n)
def counts(row):return '/'.join(fmt(used(row,k)) for k in ('Logic','CLS','Register','BSRAM','DSP')) if row['metrics'] else '未形成PnR资源报告'
def gaps(row):return {k:max(0,used(row,k)+r-row['metrics'][k]['capacity']) for k,r in reserve.items()} if row['metrics'] else None
ledger={
    'capacity':{k:final['metrics'][k]['capacity'] for k in final['metrics']},
    'future_reserve':reserve,'future_register_dsp_reserve':'not individually quantified; not assumed zero',
    'final_production':{k:used(final,k) for k in final['metrics']},
    'final_remaining':{k:v['capacity']-v['used'] for k,v in final['metrics'].items()},
    'final_gap_to_reserve_without_new_fx':gaps(final),
    'prototype_after_apds':{k:used(by['fx_apds'],k) for k in by['fx_apds']['metrics']},
    'prototype_increment_vs_apds':{k:used(by['fx_apds'],k)-used(by['apds'],k) for k in by['fx_apds']['metrics']},
    'prototype_gap_to_future_reserve':gaps(by['fx_apds']),
    'delivered_recovery':{k:used(by['base'],k)-used(final,k) for k in final['metrics']},
    'full_three_effect_delivery_complete':False,
    'do_not_add_apds_savings_to_prototype_a_second_time':True,
    'full_E_280_CLS_instead_of_E100_adds_to_CLS_gap':180,
}
write_json(HERE/'resource_ledger.json',ledger)
ap=HERE/'functional/apds'
regressions={}
for label in ('base','apds'):
    regressions[label]=json.loads((HERE/'functional'/label/'results.json').read_text())
    log=(HERE/'functional'/label/'integration.log').read_text()
    regressions[label]['pass_lines']=[s for s in log.splitlines() if s.startswith('PASS')]
regressions['display_differential']=json.loads((HERE/'functional/display_pair/results.json').read_text())
regressions['fx_sample_model']=json.loads((HERE/'functional/fx_sync/results.json').read_text())
regressions['fx_frame_guarded']=json.loads((HERE/'functional/fx_apds/frame_guarded_results.json').read_text())
regressions['flash']=[s for s in (HERE/'flash_regression.log').read_text(encoding='utf-8-sig').splitlines() if s.startswith('PASS')]
write_json(HERE/'functional_results.json',regressions)
timing=json.loads((HERE/'apds_event_timing.json').read_text())
fs=PROJECT/'impl/pnr/PCM5102_UNIFIED.fs';apk=PROJECT/'android_app/dist/FPGA-Music-Unified.apk'
freeze=json.loads((HERE/'freeze.json').read_text())
assert sha(apk)==freeze['previous_apk_sha256']
gap=ledger['prototype_gap_to_future_reserve']
increment=ledger['prototype_increment_vs_apds']
lines=[
'# 三效果落地与资源回收：本轮交付记录', '',
'**任务尚未全部完成。已接入经验证的 APDS 运算复用；完整三效果及其 App 未接入。资源与既定后续预留尚不能同时满足。**', '',
f"生产目录重新完整综合/PnR通过：**{counts(final)}**（Logic/CLS/Register/BSRAM/DSP），0未布通，setup/hold违例0/0，WNS {wns(final):+.3f}/{wns(final,'hold'):+.3f} ns。",
f"相对本轮冻结当前基线，实际净回收 **{fmt(ledger['delivered_recovery']['Logic'])} Logic、{fmt(ledger['delivered_recovery']['CLS'])} CLS**；BSRAM与DSP不变。只修改生产 `src/apds9960_ctrl.v`。没有将历史95 CLS或其他失败候选相加。", '',
'## 完成与未完成阶段', '',
'- 已冻结全部当前源码、ROM、约束、工程、工具、仿真与起始未提交修改，保存git二进制diff。未发现AGENTS.md；接手时只有IDE，无运行构建。未用Git HEAD替代工作区。',
'- 已新建当前完整基线，并完成APDS当前工程A/B、手势语义/完整事件时刻/保护边界、双模拟与I²C回归。APDS迁移前当前源与历史原基线逐字节相同，只迁局部算术。',
'- 已验证显示上下半屏配对存储的功能、碰撞和外部扫描；单独及叠加APDS均测整机。它不满足本轮CLS回收目标，未接入。',
'- 已尝试Flash FSM取消显式onehot属性；层级综合XML和最终资源与APDS版本完全相同，无收益，未接入。原子快照、NOR提交/掉电模型回归仍通过。',
'- 已完成隔离最小三效果原型、同步块RAM修正、独立样本模型、8组合回归与同帧期限测试。它用于测成本，并非正式三效果交付。',
'- 独立参数/湿度、插值及噪声、整体RT60、最终兼容协议/TAKE与App三卡/APK、最终完整联合验收未完成。字段、兼容与TAKE位域提案见 [ARCHITECTURE.md](ARCHITECTURE.md)。未修改协议生成物或App。', '',
'## 同策略实际构建', '',
'全部完整构建使用 Gowin V1.9.11.03 Education / GW5A-LV25MG121NC1/I0 / 50MHz / resource_sharing=1 / retiming=1 / place2-route0-maxfan23。未靠追加布局策略取得跨条件数字。', '',
'| 构建 | Logic/CLS/Reg/BSRAM/DSP | 相对当前基线 | 未布通 | setup/hold违例 | setup WNS ns | 判定 |',
'|---|---|---|---:|---|---:|---|']
decisions={'base':'当前冻结基线','apds':'通过并接入','display_pair':'功能通过；时序/面积拒绝',
           'combo':'布线时序通过；相对APDS多186CLS，拒绝','flash_default':'与APDS资源完全相同，无收益',
           'fx_proto':'RAM推断失败，淘汰','fx_sync':'原型通过PnR；未满足未来预留','fx_apds':'APDS上的原型实际增量；未交付'}
for label in ('base','apds','display_pair','combo','flash_default','fx_proto','fx_sync','fx_apds'):
    r=by[label];t=r.get('timing') or {}
    delta='/'.join(f'{r["delta_vs_baseline"].get(k,0):+g}' for k in ('Logic','CLS','Register','BSRAM','DSP')) if r['metrics'] else '不计入'
    violations=f"{t.get('setup_violated_endpoints','-')}/{t.get('hold_violated_endpoints','-')}"
    lines.append(f"| {label} | {counts(r)} | {delta} | {r.get('unrouted_nets')} | {violations} | {wns(r)} | {r['status']}: {decisions[label]} |")
lines += ['',f"最终生产 APDS：{counts(final)}。实际 `.prj`、`cmd.do`、`device.cfg`、资源报告、STA HTML与原始 timing_paths 的哈希及输入差异在 [build_audit.json](build_audit.json)、[final_production_audit.json](final_production_audit.json)。源码输入在各构建 `sources.json` 与 [final_inputs.json](final_inputs.json)。",
'', '早期部分快照包含Gowin自动写出的.gprj.user及测试日志；审计保留这些条目，不将其误称RTL差异。失败fx_proto的.gprj.user被工具重写，原始不一致也保留；失败候选没有交付。', '',
'## 资源账与具体缺口', '',
'C/B1已实现，不再预留。D/B2/E100/安全垫沿用最低1650 Logic /365 CLS /4 BSRAM。完整E280口径还需额外180 CLS。尚未逐项量化未来Register/DSP，不能据此宣称所有未来需求已验收。', '',
'| 资源 | 最终已用/容量 | 现在剩余 | 后续最低预留 | 当前不加新FX的缺口 |',
'|---|---:|---:|---:|---:|']
for k in ('Logic','CLS','Register','BSRAM','DSP'):
    v=final['metrics'][k]
    lines.append(f"| {k} | {fmt(v['used'])}/{fmt(v['capacity'])} | {fmt(v['capacity']-v['used'])} | {reserve.get(k,'未逐项量化')} | {gaps(final).get(k,'未判定')} |")
lines += ['',f"在同一APDS基线上加入最小三效果，实测增量为 **{counts({'metrics':{k:{'used':v} for k,v in increment.items()}})}**。按该原型实测总量再保留后续额度，仍缺 **{fmt(gap['Logic'])} Logic / {fmt(gap['CLS'])} CLS / {fmt(gap['BSRAM'])} BSRAM**。完整参数、协议及插值成本尚未包含，也未以独立综合或Logic/2冒充可兑现CLS。",
'', '以上缺口直接由原型最终资源加预留计算；其中已经包含APDS，不能再次扣减134 CLS。显示配对省3块BSRAM，但它的同机面积代价也已实测，不能只拿内存收益拼入这张表。', '',
'本轮没有找到同时填平这些缺口的可交付组合。继续原定功能与预留，必须先取得相应净回收，并验证更紧凑存储或其它BSRAM回收。改变器件、降低后续预留、移除功能均需用户另行决定；本轮未自行采用。', '',
'## APDS功能与真实事件时刻', '',
'四路累加/平均、端点、方向归一化、饱和/噪声、32轮校准、空FIFO、短读、溢出、NACK恢复的完整语义轨迹相同：快速矩阵1108条、默认活动轮询/释放保护矩阵305条。均值最坏256→1024拍。默认活动等待100000拍，释放保护750000拍；只加速启动/空闲等待。', '',
'| 活动轮询参数 | 原/候选分类poll | 原/候选最后有效样本后拍数 | 从同一启动计算的分类时刻差 |',
'|---:|---|---|---:|']
for active,row in timing.items():
    a=row['base']['classified_guard_cycles'][0];b=row['apds']['classified_guard_cycles'][0]
    lines.append(f"| {active} | {a[0]}/{b[0]} | {a[1]}/{b[1]} | {row['classified_timing_delta_cycles']:+d}拍 |")
lines += ['', '93750/93700是刻意逼近保护边界的定向参数，不是生产100000拍。93700时，候选在本次检查跨过15ms阈值，原版差4拍而等下一轮；可提前91364拍（1.82728ms）分类。两者均不提前于750000拍。原型不承诺逐拍事件等价，也没有把768拍均值增加量冒充整个事件的变化上界。完整命令及事件时间戳在 [apds_event_timing.json](apds_event_timing.json)。', '',
'本轮基线与候选均重跑：tb_top_dual_analog、tb_ads1115_bus、tb_analog_expression、tb_apds_nack、tb_i2c_master_bus、tb_top_idle。NACK恢复另由完整控制器事务激励覆盖；未宣称完成真实光学/I²C任意锁死场景验收。', '',
'## 显示、最小三效果与期限证据', '',
'- 显示既有回归：6174对行掩码、3002组位置算术、133拍外部扫描；音频页/FFT启动/页边界测试通过。',
'- 新旧冻结RTL逐拍对比：599985次检查、446264次写、25802次配对碰撞（1719次跨半屏同字）、222976次滚动同拍写、3324次ROW_PREP同拍写、45次在途STOP、15次复位；全部逻辑行、行快照、外部输出相同。',
'- 同步RAM原型与独立采样队列模型：259200个输入/输出，逐样本误差0，8组合/四档延迟/四档混响/配置切换/湿度钳位/复位/满幅覆盖，最长37拍，overrun 0。早期29拍原型因RAM推断失败被弃用。',
'- 同帧压力的guarded用例：1416完整帧，触摸1012、弯音43、效果37、传感器535拍；338压力帧、4次16声部包络边界、每完整帧恰一个效果结果、RTL overrun/超限/合成混音clipped均0。效果自身空闲987拍；三引擎并集1012拍。',
'- 顶层原型测试保持50MHz/1024拍；UART 500k、TTP启动100µs、短ADSR/60ms前视，进入播放后一次跳过视觉预滚。FSR关闭、滑杆/回放未联合，因此不是最终完整验收。',
'- Flash回归：528位同拍原子快照5项、NOR行为模型114项、事件状态机25项通过。它们没有带来新资源收益。', '',
'原始日志、向量/样本哈希和汇总见 [functional_results.json](functional_results.json)、[functional/](functional/)、[resource_ledger.json](resource_ledger.json)。', '',
'## 可复现步骤与交付指纹', '',
'在本工程目录使用本机Python运行。prepare/candidate/build均应使用新目录/标签；不要覆盖本轮证据。新label的构建只读取该label快照，和工具只改输出Label的行为不同。', '',
'```powershell',
"$py = 'E:/300_IDE_Compiler/Python313/python.exe'",
"# 重验本轮现有证据，不启动构建",
"& $py reports/fx_delivery_20261025/delivery.py audit apds display_pair combo flash_default fx_proto fx_sync fx_apds",
"# 在新任务目录复制当前未提交源码；完成快照哈希核对后，使用该副本的tools/build_unified.tcl",
"# 每个已冻结构建的原命令均为：",
"# gw_sh.exe <label>/pcm5102_pam8403/tools/build_unified.tcl",
"# 生产重新构建已执行：gw_sh.exe tools/build_unified.tcl",
'```', '',
f"- 最终默认码流：`impl/pnr/PCM5102_UNIFIED.fs`；SHA256 `{sha(fs)}`。源码/ROM/约束/工程等{final['verified_inputs']}项输入构建前后不变，逐项匹配已验证APDS快照。",
f"- 生产APDS源码SHA256：`{sha(PROJECT/'src/apds9960_ctrl.v')}`。本轮冻结基线与旧默认输出分别在 `base/`、`previous_default/`，未删除。",
f"- App未改、未发新版APK；现有 `android_app/dist/FPGA-Music-Unified.apk` SHA256 `{sha(apk)}`，与开始时一致，不能把它说成三卡App。",
f"- 起始工具、git状态/完整diff与源清单：[freeze.json](freeze.json)、[starting_status.txt](starting_status.txt)、[starting_diff.patch](starting_diff.patch)、[base_inputs.json](base_inputs.json)。最终生产审计：[final_production_audit.json](final_production_audit.json)。",
'', '**本轮未烧录FPGA、未安装手机、未做DAC模拟对录或实体面板/光学验收。**', '',
'## 后续边界', '',
'只有APDS回收已经交付。整体三效果任务未完成，不能把原型码流或协议提案称为“准备好了”。下一步应以本报告实测缺口为准取得更多净回收；若选择改变硬件或功能预留，必须明确变更对象再继续。',
]
(HERE/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
verification=PROJECT/'VERIFICATION.md'
raw=verification.read_bytes()
heading='## 2026-10-25：APDS资源回收与三效果原型（整体任务未完成）'
if heading.encode('utf-8') not in raw:
    section='\n'.join([
        heading,'',
        f"只接入APDS局部累加/均值运算复用，其余既有修改保留。当前生产完整PnR：Logic {fmt(used(final,'Logic'))}、CLS {fmt(used(final,'CLS'))}、Register {fmt(used(final,'Register'))}、BSRAM {fmt(used(final,'BSRAM'))}、DSP {fmt(used(final,'DSP'))}；place2/route0/maxfan23，未布通0、setup/hold违例0/0，WNS {wns(final):+.3f}/{wns(final,'hold'):+.3f} ns。相对本轮冻结当前基线净回收211 Logic/134 CLS。",
        f"默认位流SHA256 `{sha(fs)}`；{final['verified_inputs']}项源码/ROM/约束/工程等输入逐项匹配已验证快照，构建前后未变。旧默认输出及新建冻结基线保留在 `reports/fx_delivery_20261025/previous_default/` 和 `base/`。",
        '',
        '本轮APDS矩阵与双模拟/ADS1115/I²C/NACK/静默回归通过。均值最坏256→1024拍；15ms释放保护仍满足，但边界参数可跨到相邻轮询，不能称完整事件逐拍等价。生产100000拍活动轮询下分类相对最后有效样本延后173拍，详细绝对时间与边界见报告。',
        '',
        '显示上下半屏配对存储功能通过，少3块BSRAM；单独版本时序失败，叠加APDS虽时序通过但面积变大，均未接入。Flash FSM编码候选无新增收益。隔离三效果原型保持独立2048/4096/4096存储及4comb+2allpass，259200帧与独立模型逐样本相同；1416同帧压力帧的触摸/弯音/效果最坏1012/43/37拍，overrun/超限/合成混音clipped均0。原型有明确快速参数与功能边界，不代表最终联合验收。',
        f"在APDS上加入该原型后，按D/B2/E100/安全垫最低预留1650 Logic/365 CLS/4 BSRAM，仍缺{fmt(gap['Logic'])} Logic/{fmt(gap['CLS'])} CLS/{fmt(gap['BSRAM'])} BSRAM。三效果正式RTL、兼容协议/TAKE、三卡App与新版APK未交付；没有削减功能或预留，也未把最小原型写成完成。",
        '',
        '完整资源账、输入和码流指纹、可复现命令及尚未完成项见 [本轮报告](reports/fx_delivery_20261025/README.md)。本轮未烧录、未安装APK、未做实体光学/面板/模拟音频验收。',''])
    newline=b'\r\n' if b'\r\n' in raw else b'\n'
    end=raw.index(b'\n')+1
    addition=newline+section.replace('\n',newline.decode()).encode('utf-8')+newline
    verification.write_bytes(raw[:end]+addition+raw[end:])
evidence={p.relative_to(HERE).as_posix():sha(p) for p in HERE.rglob('*') if p.is_file() and p.name!='evidence_hashes.json'
          and p.suffix in ('.json','.md','.py','.v','.sv','.log')
          and p.relative_to(HERE).parts[0] not in ('base','apds','display_pair','combo','flash_default','fx_proto','fx_sync','fx_apds','app_frozen','previous_default')}
write_json(HERE/'evidence_hashes.json',evidence)
print('Report written. Prototype resource gap:',gap)
