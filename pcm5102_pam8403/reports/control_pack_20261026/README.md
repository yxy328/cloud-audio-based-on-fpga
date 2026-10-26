# 第三步：控制装箱与局部译码（2026-10-26）

**已撤回第二步增加 77 CLS 的显示版本。** 29 项文件按哈希恢复，原显示七 RAM、扫描和默认位流恢复；实验仍在 `../display_ports_20261026/` 保留。当前主目标是减少 CLS，释放 BSRAM 本身不构成接入理由。

本轮未接入候选，默认工程保持 11387 CLS / 53 BSRAM；没有已交付的新增 CLS 收益。

收益以恢复后的第一轮 HC-05 基线 11387 CLS 为起点；历史 83 CLS 和撤回时恢复的 77 CLS 不算第三步收益。

| 构建 | Logic | CLS | Register | BSRAM | DSP | CLS 增量 | 未布通 | 状态 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| baseline | 22447 | 11387 | 10732 | 53 | 26.5 | 0 | 0 | validated |
| download_decode | 22475 | 11401 | 10732 | 53 | 26.5 | +14 | 0 | validated |
| adsr_reset | 22370 | 11418 | 10726 | 53 | 26.5 | +31 | 241 | routing_failed |
| adsr_place2 | 22369 | 11429 | 10726 | 53 | 26.5 | +42 | 0 | validated |
| parser_shared | 22352 | 11420 | 10626 | 53 | 26.5 | +33 | 0 | validated |
| parser_index | 22288 | 11390 | 10637 | 53 | 26.5 | +3 | 0 | timing_failed |
| parser_index_p2 | 22288 | 11408 | 10637 | 53 | 26.5 | +21 | 0 | validated |

四种结构候选均与同一冻结基线比较。parser_index 包含参数生命周期共享和回复索引的联合修改，其收益由完整构建单独测量。ADSR place2 只重试同一 RTL 的物理设置。固定译码功能与时序通过，但 CLS +14，明确淘汰。失败、时序违例或面积增加的候选不计收益，各候选差值不相加。

## 功能证据

| 版本 | 通过检查 | 说明 |
|---|---:|---|
| download_decode | 13/13 | 独立候选功能检查 |
| adsr_reset | 6/6 | 独立候选功能检查 |
| adsr_place2 | 6/6 | 沿用同 RTL 证据，只改物理放置 |
| parser_shared | 13/13 | 独立候选功能检查 |
| parser_index | 16/16 | 独立候选功能检查 |
| parser_index_p2 | 16/16 | 沿用同 RTL 证据，只改物理放置 |

物理重试没有另算新功能覆盖。各版本的原始日志、引用关系和输入哈希保留在各自目录。

## 实现与功能边界

`download_decode` 将曲谱动态索引改为共享的固定音高比较，保持原流水线和原子验证。35072 组组合对照、曲谱/协议逐拍差分和最长 128×60000ms 曲谱检查有独立记录，未改生产曲谱模块。

`adsr_reset` 仅移除 ADSR 换算器内部暂存的复位，配置输出、done 和状态机仍复位。每次接受请求后先覆盖输入暂存，PREPARE/LOAD 覆盖运算数，四字段均完成后才允许 COMMIT；中途复位回到 IDLE，旧数据无法提交。音频模块、运算周期、UART 接收/拒绝条件与 TAKE 格式均未改。详见 [设计与有效性证明](DESIGN.md)。

`parser_shared` 使用等待期间保持不变的解析寄存器，替代重复的曲谱/ADSR 参数锁存。子模块仍在原请求边沿采样，父模块仍等待原完成信号；restore、校验和优先级保留。初稿的前向声明不被 Icarus 接受，已停止该构建并保留记录；最终版本先通过编译检查，再完整重建。

`parser_index` 在共享参数生命周期的结构上，继续保留完整 112 位回复快照，将回复逐数字移位改成 5 位数字索引。只在原字符真正被 UART 接受且模板为动态数字时推进，标点/仲裁/背压不推进；28 位后保持零。有效回复必先在 EXECUTE 完整锁存，因此数据本体无需复位，状态、长度和游标仍复位。20000 拍直接对照和真实 UART 差分分别检查数字位置/仲裁与完整字节节奏。独立完整构建，不将差值与前一候选相加。


## 证据与复现

[回退核验](rollback.json) · [冻结输入](freeze.json) · [结果账](results.json)。各目录保存 sources.json、exit.json、audit.json、原始时序、测试日志和 verification.json。最初的端口注释识别和 force 注入镜像夹具编译错误日志保留，不计为通过；RTL 没有据此修改。

```powershell
python work.py audit download_decode
python work.py audit adsr_reset
python finish.py verify adsr_reset integration
# 原构建日志不覆盖。重新实现请另建冻结目录，或使用主工程 tools/build_unified.tcl。
```

本轮未宣称达到 500 CLS 回收目标。未烧录 FPGA、未写板上 Flash、未做实板显示或听音验收。
