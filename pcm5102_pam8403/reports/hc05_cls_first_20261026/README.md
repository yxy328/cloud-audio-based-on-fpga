# 第一轮 HC-05 CLS 优化（2026-10-26）

采用 `reply_place1`，实际净回收 **83 CLS**。已接入默认工程和默认位流。
全部既有功能、命令、参数范围、引脚和存储格式保留；RTL 只改变 HC-05 回复数据寄存器的选择结构，并据完整时序更新物理实现策略。

| 资源 | 基线 | 本轮 | 增量 | 剩余 |
|---|---:|---:|---:|---:|
| Logic | 22624 | 22447 | -177 | 593 |
| CLS | 11470 | 11387 | -83 | 133 |
| Register | 10726 | 10732 | +6 | 12548 |
| BSRAM | 53 | 53 | +0 | 3 |
| DSP | 26.5 | 26.5 | +0 | 1.5 |

同一器件与工具，50MHz、sharing=1、retiming=1；基线 place2/route0/maxfan23，候选实际策略 {'place_option': 1, 'route_option': 0, 'route_maxfan': 23}；未布通 0。
setup/hold 违例端点 0/0；原始路径 WNS +0.081/+0.153 ns，基线为 +0.018/+0.144 ns。CLS 净收益使用完整 PNR 对比，包含 RTL 与物理策略的联合变化；不将局部 LUT 减少直接换算成 CLS，也不将全部收益归因于 RTL。

## 实现与功能边界

保持原命令状态机、所有校验和回复时机；将 17 个原有回复载荷来源改由独立时序块选择，仍在同一 EXECUTE 边沿锁存完整 112 位载荷。错误/设置命令可能更新无效载荷，但静态回复不读取它；所有动态回复均重新锁存完整载荷。仲裁、背压和每字节节奏保持原条件。详见 [DESIGN.md](DESIGN.md)。

## 验证

共 17 组最终检查，全部通过：12 组串口差分、4 组整机/TAKE 检查及 1 组未改基线的当前曲谱合同检查。
差分测试以本轮冻结的原 RTL 为参考，每个时钟比较全部 67 个输出；原有字节回复/状态断言继续运行。范围包括映射/音高、错误帧、竞争、扩展控制、三效果、TAKE、ADSR、弯音、视觉/XY、曲谱及旧音频录制参数分支。这不是任意内部状态的形式等价证明。

物理策略重试与 reply_parallel 的全部 RTL/ROM/约束哈希一致，只有构建脚本的物理选项不同，功能证据沿用该完全相同 RTL 的测试；每个策略重新完成资源、布线和时序核验。

整机测试包括固定 16 键极性恢复，以及真实 50MHz/1024 拍音频帧下的 UART/TTP229/双 ADC/三效果/曲谱并行与 TAKE 回放。旧新 TAKE 字段 2075 检查和完整 528 位原子快照 34 检查通过。启动/轮询/包络等加速参数沿用原有测试，不能当作全默认墙钟实板验收。

历史 tb_hc05_download 仍允许旧七键日志录制，与本轮开始前的固定16拒绝 REC_START 的源码不符。原文件和失败日志保留；新增 current 版本明确检查既有半音阶和固定16合同，并在未修改基线与候选上均通过。该曲谱用例采用合法 2ms 和弦/休止替代 50ms 等待，其余原有曲谱原子性/重试/范围检查以及显式自然音映射断言保留。补充测试初稿误将十进制145当作十六进制且忽略用例显式重设映射，导致错误掩码预期；未改基线也复现，已修正测试，RTL未据此修改。诊断日志保留，不计为通过证据。

## 未采用的实验

- 全命令 case 分发：放置失败，26 LUT 等价单元未放入，不构成可交付资源统计。
- 共享 MAP 十进制格式化：完整布通且时序通过，但 Logic +49、CLS +13，未接入。

- 回复数据拆分的原 place2/route0/fan23 构建：少 50 CLS、180 Logic，但有 9 个 setup 端点违例，原始 WNS -1.586 ns，不交付该位流。

## 产物与复现

默认入口：`../../impl/pnr/PCM5102_UNIFIED.fs`；独立命名副本 [PCM5102_UNIFIED_CLS_FIRST_20261026.fs](PCM5102_UNIFIED_CLS_FIRST_20261026.fs)。
位流 SHA256：`ACC17F2F956BBE26400E84E3E09AAB82EDECCDFFCFCD9902203E6C34ACFD2F8A`。
回退源文件、原默认位流和原构建报告位于 `production_before/`；未烧录 FPGA、写板上 Flash 或做实板听音。

核验链：[freeze.json](freeze.json)、所选候选 sources.json/exit.json/audit.json/verification.json、[integration.json](integration.json)。102 项生产输入与所选构建逐项匹配，相对基线仅 hc05_keymap.v 和物理构建选项改变。

```powershell
& 'E:/300_IDE_Compiler/Python313/python.exe' finish.py checks reply_place1
# 原候选证据不覆盖；新建快照后再构建，或直接在主工程使用标准 build_unified.tcl。
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' ../../tools/build_unified.tcl
```

本轮未达到 500 CLS 回收；后续以新基线继续评估其他结构，不能将历史回收或失败候选差值相加。

## 全部策略的结束状态

| 候选 | 资源/物理结果 | 采用 |
|---|---|---|
| parallel_dispatch | 放置失败，26 LUT 等价单元未放入 | 否 |
| map_serial | 完整通过，但 CLS +13 | 否 |
| reply_parallel：place2/route0/fan23 | CLS -50，9 个 setup 端点违例，原始 WNS -1.586ns | 否 |
| reply_place1：place1/route0/fan23 | CLS -83，完整布通，setup/hold 端点违例0/0，WNS +0.081/+0.153ns | 是 |
| reply_fan12：place2/route0/fan12 | 仍有相同9个 setup 端点违例，原始 WNS -1.586ns | 否 |
| reply_route1：place2/route1/fan23 | 3925 条网络未布通 | 否 |

各候选独立差值不相加；未布通和时序失败版本均未交付。
接入过程中遇到默认生成 .bin/.fs 的 Windows 只读属性，确认回退副本完整后仅清除指定目标的只读位并续传。
源码、构建脚本及24项输出全部逐项哈希核对完成；未修改文件ACL或任何板上存储。
