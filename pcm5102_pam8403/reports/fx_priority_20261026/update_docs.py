from pathlib import Path
H=Path(__file__).resolve().parent;P=H.parent.parent
prefixes={
'VERIFICATION.md':'''# 2026-10-26 三效果优先版

当前正式工程为固定 16 键 + 合唱/延迟/混响串联 + App Code27。此前“效果器仅隔离原型、未改 App/默认码流”的结论属于历史版本；本轮完整验收以 [FX3.md](FX3.md) 和 [报告](reports/fx_priority_20261026/REPORT.md) 为准。后续 D/B2/E 预留暂缓，35 CLS 安全余量继续保留。下文历史验收记录保留。

''',
'HC05_KEYMAP.md':'''# 2026-10-26 三效果协议补充

新增 `EFFECT,3,m,s,w` 与 `EFFECT,?` → `EFFECT3,m,ss,www,a,tt,vvv`，定义见 [FX3.md](FX3.md)。原 EFFECT 0/1/2 和 EFFECT2 保留；回复 kind30 现已使用、kind31 保留，命令 ID 不变。新回复含配置和实际状态，滑杆覆盖/TAKE 回放时二者可以不同。下文旧版“kind30 空闲”与单效果说明为历史记录。

''',
'android_app/README.md':'''# 2026-10-26 三效果版：1.26-fx3 / Code27

当前安装包为 `dist/FPGA-Music-FX3-Code27.apk`，`dist/FPGA-Music-Unified.apk` 是相同文件。混音页提供独立合唱、延迟、混响卡片，可同时开启；分别显示配置/实际值，保留草稿，逐卡应用。BPM 延迟计算器位于延迟卡内。固定 16 键、手机本地 MIDI、TAKE、双模拟输入及其余控制保留。固件与协议见 [FX3.md](../FX3.md)。旧固件不支持三效果查询时显示不可用，其余控制仍可使用。

Java 全量编译、核心测试和 RTL 回复夹具交叉测试通过；未做手机界面、真实蓝牙或听音验收。命名 Code26 安装包保留供回退。下文为此前版本说明。

'''}
for name,prefix in prefixes.items():
    file=P/name;before=file.read_bytes();assert not before.startswith(prefix.encode('utf-8'))
    file.write_bytes(prefix.encode('utf-8')+before)
print('Prepended current release notes; historical document bytes preserved')
