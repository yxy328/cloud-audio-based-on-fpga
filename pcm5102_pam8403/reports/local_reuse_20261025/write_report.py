from pathlib import Path
import json,difflib
H=Path(__file__).resolve().parent
a=json.loads((H/'build_audit.json').read_text(encoding='utf-8'))
rows=a['builds']
def wns(b):
    t=b['timing']
    if b['status']=='routing_failed':return '不可验收'
    if not t or not t.get('setup_worst_path') or not t.get('hold_worst_path'):return '未提供'
    return f"{t['setup_worst_path']['slack_ns']:+.3f} / {t['hold_worst_path']['slack_ns']:+.3f}"
def table():
    s='| 构建 | Logic | CLS | Register | BSRAM | DSP | 未布线 | setup/hold WNS ns | 判定 |\n|---|---:|---:|---:|---:|---:|---:|---|---|\n'
    for b in rows:
        vals=[str(b['metrics'].get(k,{}).get('used','—')).removesuffix('.0') for k in ['Logic','CLS','Register','BSRAM','DSP']]
        result={'validated':'布线/时序通过','routing_failed':'淘汰：布线失败','timing_failed':'淘汰：时序失败','incomplete':'未完成'}.get(b['status'],b['status'])
        if b['label']!='engine_share_base_20261024' and b['status']=='validated' and not b['meets_resource_route_timing_target']:result='淘汰：未达 500 CLS 目标'
        s+='| '+' | '.join([b['label']]+vals+[str(b['unrouted_nets']),wns(b),result])+' |\n'
    return s
finished=all(b['status'] not in ['incomplete','synthesis_only'] for b in rows)
qualified=[b for b in rows[1:] if b['meets_resource_route_timing_target']]
if qualified:lead='存在达到资源/布线/时序门槛的实验候选，尚须必要集成回归；未接入生产。'
elif finished:lead='本轮两个候选均淘汰，尚无可交付的 CLS 净收益；至少回收 500 CLS 的第一阶段目标未达成。'
else:lead='实验进行中；已结束的失败候选不计交付收益，未完成项不得据此验收。'
hashes=''
for b in rows[1:]:
    for f,x in b['changed_input_hashes'].items():hashes+=f"| {b['label']} | {f} | `{x['baseline']}` | `{x['candidate']}` |\n"
local=a['isolated']
lt='| 独立综合 | 自身 LUT | 自身 ALU | 自身 LUT+ALU | 自身 FF | 乘法原语 |\n|---|---:|---:|---:|---:|---|\n'
for name,v in local.items():lt+='| '+' | '.join([name,str(v['LUT']),str(v['ALU']),str(v['LUT_plus_ALU']),str(v['FF']),', '.join(f'{n} x {c}' for n,c in v['multipliers'].items()) or '无'])+' |\n'
delta=''
for b in rows[1:]:
    d=b['delta_vs_baseline']
    delta+=f"- `{b['label']}`："+'、'.join(f'{k} {v:+g}' for k,v in d.items())+f"；未布线 {b['unrouted_nets']}，setup/hold {wns(b)}。\n"
text=f'''# 2026-10-25 局部资源复用实验

**{lead}**

{table()}
差值为候选减基线，失败构建中的下降只作诊断：

{delta}
所有本轮候选都是隔离实验。资源/布线/时序全部达标的新增候选：{len(qualified)}；已经接入生产的新增版本：0。保留 `engine_share_base_20261024` 为已验证基线，未修改交付位流、APK 或烧录设备。未达到全工程门槛，按停止条件未投入整套顶层长回归、未准备生产接入补丁。

## 输入、工具与单变量

先读取 resource_audit_20261024 的 README、hierarchy_audit.json、build_audit.md/json，并复核原基线的 98 项输入哈希。基线直接从原已验证冻结包复制，未混入生产树的后续修改。APDS 和 Flash 各自只改一个源文件，互不叠加；每份 sources.json 均逐项重新校验。Gowin V1.9.11.03 Education、GW5A-LV25MG121NC1/I0；resource_sharing=1、retiming=1、global_freq=50、place/route/maxfan=0/0/23。实际综合 prj、PnR cmd.do 和 device.cfg 也在路径归一化后与基线逐项一致，见 build_audit.json 的 effective_build_configuration。

| 实验 | 唯一改动文件 | 基线 SHA256 | 候选 SHA256 |
|---|---|---|---|
{hashes}
`freeze.json` 和 `evidence_hashes.json` 保存构建输入、测试激励、脚本与工具可执行文件哈希；各实验 sources.json 为原 98 项清单。`production_after_check.json` 记录启动时 286 项生产源/测试/工具输入的后续漂移：目前有 {len(a['production_drift'])} 项，其前后哈希均保留。它们由并发工作改变，本实验只在此报告目录内写文件，没有覆盖或还原其他工具的修改。

## 实际结构、周期及功能证据

APDS 增加 2 位通道选择、四选一累加器/商输入、共享 16 位加减与进位比较、共享 8 位递增及条件写回。没有减少通道、精度或音频引擎。FIFO n=1..32，通道总和 0..8160，商 0..255；保留原 16 位累加和 8 位商。平均值循环从 max(q)+1 改为 sum(q)+4，最大 256→1024 拍，新增最多 768 拍（15.36 µs）。raw_* 中间更新次序不同，只保证测试中的完整批次与事件序列一致，不宣称逐拍等价。

APDS 功能矩阵经过初始化、32-poll 校准和真实控制器状态机，覆盖正反 U/D、L/R、归一化对角分类、同比亮度、纯饱和及饱和端点排除、空 FIFO、平衡噪声、短读、溢出、NACK 清理后恢复；新旧命令、完整 poll、首末端点和有效输出共 1108 条记录相同。另用默认 2ms 活动轮询/15ms 释放保护检查正向手势，两者最后有效采样到分类分别为 800396/800569 拍，未提前释放；此项加速了空闲/启动等待。NACK 与 pin-level I2C ACK/重复起始/读/NACK/释放分别另测。不能将这些结果表述为完整默认时序回归或实板验证。

Flash 将现有 128 位头部循环移位，固定低 8 位输出，替代动态字节选择；前 11 字节元数据 CRC 后增加 5 拍恢复位序（每次 100ns），完整 16 字节写出/回读后原位恢复。新增恢复 FSM/计数器和写回选择均计入资源。两槽、所有权与擦除授权、原串行 CRC、body/header 回读、最后 commit 字节及掉电恢复均保留。新旧 `tb_take_nor_store` 覆盖跨页保存/重启、编程掉电、旧槽恢复、未知槽禁擦除、删除 tombstone、外来 padding、写保护、program 失败、WIP watchdog 与错误 JEDEC。首次保存镜像逐字节相同，SHA256 为 `E77400F1572D08748FC3AEE807963A16123A6325BE262BE58CDAFEF055CFC901`。行为 NOR 模型测试不是实物掉电验收。

录制模块审查发现基线已经同拍锁存 528 位 live_state 后移位输出，未把它包装成新优化。单一普通双口 BSRAM 无法同拍写入 33 路 16 位独立字段；未采用破坏原子性的串行 live_state 采样，录制模块无改动。

## 局部综合口径

{lt}
APDS 自身 LUT+ALU 净少 98、FF +2。Flash 自身净少 166、FF +6；含 SPI 子模块的独立综合为 1452 LUT/66 ALU/635 FF → 1250 LUT/66 ALU/643 FF，其中子模块源文件未变，不能将其额外映射变化归为删掉头部选择器的收益。局部 LUT/ALU 与整机 Logic/CLS 不混算。完整自身层级差异见 hierarchy_delta.json，包含未改动模块的变化。

整机综合层级：APDS 自身 LUT+ALU 减少 124，整机合计减少 167；Flash 自身由 1317 LUT/52 ALU 变为 1366 LUT/52 ALU，反而增加 49，整机合计增加 60。Flash 的局部改善没有在整机综合中复现；原始 XML 和 hierarchy_delta.json 保留了这个反向结果，不能只摘取独立综合的下降数字。

## 可审阅证据

- [位宽、周期预算和行为边界](design_notes.md)
- [全工程资源、布线、时序、输入差异及完整哈希](build_audit.json)
- [局部原始 XML 计数汇总](isolated_results.json)
- [功能结果、轨迹对比及镜像哈希](functional_results.json)
- [层级自身资源差异](hierarchy_delta.json)
- [冻结工具与输入](freeze.json)
- [生产树并发变化记录](production_after_check.json)
- `apds_serial.diff`、`flash_rotate.diff`：仅供审阅实验结构，禁止据此直接接入当前生产树。

复核：在报告目录运行 `python collect.py`、`python write_report.py`。原始构建脚本分别位于候选的 `pcm5102_pam8403/tools/build_unified.tcl`，日志为 full_build.log；不要复用旧输出目录追加运行。新的完整复现实验须从原已验证冻结包重新校验并创建空目录，保留相同工具与选项。测试激励的当前工作区版本与旧基线 I2C 接口不同，fixtures 中已仅移除新接口的两条写扩展端口连接，主机 RTL 未修改。
'''
(H/'README.md').write_text(text,encoding='utf-8')
(H/'build_audit.md').write_text(lead+'\n\n'+table()+'\n完整源文件哈希、实际命令对比和时序端点见 build_audit.json。\n',encoding='utf-8')
for name,file in [('apds_serial','apds9960_ctrl.v'),('flash_rotate','take_nor_store.v')]:
    rel='pcm5102_pam8403/src/'+file
    x=(H/'baseline'/rel).read_text(encoding='utf-8-sig').splitlines(True)
    y=(H/name/rel).read_text(encoding='utf-8-sig').splitlines(True)
    (H/f'{name}.diff').write_text(''.join(difflib.unified_diff(x,y,fromfile='a/'+rel,tofile='b/'+rel)),encoding='utf-8')
print(lead)
