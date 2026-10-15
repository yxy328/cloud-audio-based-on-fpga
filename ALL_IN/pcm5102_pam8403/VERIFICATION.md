# 本地验证记录

2026-10-11：顶层已切换到 Karplus–Strong 拨弦模型。以下正弦 RTL、网表与板上
结果仅适用于旧版本。现已将 Icarus Verilog 12.0 解压至工程 `tools/local_sim`，
执行新版 `tools/run_sim.ps1` 全部通过：`tb_karplus` 比较 40000 个采样并验证再次触发，
`tb_guitar_top` 短测试检查 595 个立体声帧，`tb_audio_units` 基础模块测试通过。
随后 `vvp sim/build/tb_guitar_top.vvp +long_wave` 长测试通过：49423 个立体声帧，
其中 48896 个为松键后的非零尾音帧。输出 `guitar_wave.vcd`、`guitar_samples.csv`，
从 I2S 解码 CSV 绘制 `guitar_wave.png`。这些文件位于 `sim/build`。
仿真器编译在沙箱内异常退出，在沙箱外运行同一脚本通过；长测试运行也通过。
尚未完成吉他版综合或下载。
`tools/run_netlist_sim.ps1` 仍是旧正弦网表检查脚本，不适用于吉他版。
现有位流与 GAO 探针配置也未重新生成。

最近更新：2026-10-08（Asia/Shanghai）。最新检查包含板上 GAO 采集；
2026-10-07 的图形界面构建与配置修复记录保留在下文。

## 2026-10-08 无声问题排查

再次执行 RTL 顶层和模块自检，通过。另使用 `tools/build_audit.tcl` 生成
Gowin 布局布线后的 `impl/pnr/PCM5102_AUDIT.vo`，并使用
`tools/run_netlist_sim.ps1` 与原厂 `IDE/simlib/gw5a/prim_sim.v` 运行功能仿真。
独立 I2S 引脚解码仍通过：146 个立体声对、131 个静音声道字、162 个非零声道字。
这次网表仿真**未标注 SDF 延迟**，不是时序仿真。
网表也确认自动复位计数器 INIT=0、正弦 ROM 初始化内容存在。

为区分仿真结果和板上实际行为，新增 `debug/audio_gao/AUDIO_GAO.gprj`，
引用主工程原来的五个 RTL 源文件及约束，加入四路 GAO 探针。
该调试工程关闭输出寄存器放入 IOB，以便 GAO 捕获输出节点。
构建通过，并已通过官方 Programmer CLI 将 `debug/audio_gao/impl/pnr/ao_0.fs`
下载到实际 FPGA SRAM：USB Location 385、扫描器件 GW5A、下载返回成功。
本次没有烧写 Flash，也没有改写原来的 `PCM5102_PAM8403.fs`。

GAO 以板载 50MHz 时钟采集，导出时设置 20ns。
16,384 个有效采样点解码结果如下：

| 信号 | 本次板上结果 |
| --- | --- |
| H11 / S1 | 捕获窗口内始终为低；实际按下后的高电平尚待验证 |
| K2 / BCK | 1,023 个完整周期均为 320ns，即 3.125MHz |
| K1 / LRCK | 30 个完整周期均为 20,480ns，即 48.828125kHz |
| L1 / DIN | H11 为低时整段为零；31 个完整声道字均解码为 PCM=0 |
| I2S | 每声道 32 个 BCK；延迟位、16bit 数据和补零通过；15 对左右声道一致 |

原始数据位于 `debug/audio_gao/captures/key_low.csv`，解码结果位于
`debug/audio_gao/captures/key_low_analysis.json`，复现方法见该调试目录 README。
频率按照板载 50MHz 标称值换算，片内捕获未独立测量晶振绝对频率，
也不能代替 DAC 接收端的电压、边沿和负载测量。

### 随后的自动播放诊断：数据链路实测通过

用户离开后，在 `debug/audio_autoplay` 增加独立诊断工程，引用原来的四个音频模块及约束。
诊断顶层将音频使能固定为高、默认音量改为 1/16，并以单独寄存器观测 H11。
65,536 深度 GAO 构建通过并下载到 SRAM，User Code=0x000051B2，
Status Code=0x70026020，下载日志保存在该目录 `programmer_sram.log`。

本次实际捕获 65,536 个有效点、跨度 1.3107ms。BCK 的 4,095 个完整周期全部为 320ns，
LRCK 的 126 个完整周期全部为 20,480ns。DIN 确实存在非零数据，
解出 64 个左声道采样（63 个非零），数值范围 -2048～1375；63 对完整左右声道全部相等。
32 BCK/声道、一位延迟、MSB 优先、补零和下降沿更新均通过。

独立数学模型验证 64 个采样均符合原相位增量和 1/16 缩放，并能对应同一个连续相位序列。
没有读取 RTL 波表或硬件内部相位寄存器作为期望值。
原始 CSV、解码 JSON 及实际波形图保存在 `debug/audio_autoplay/captures`，
复现和试听说明见 `debug/audio_autoplay/README.md`。
本次说明中的约 440Hz 根据通过逐点验证的相位模型及 50MHz 标称时钟计算。

采集后已恢复原按键行为的 GAO 位流 `debug/audio_gao/impl/pnr/ao_0.fs`，
恢复下载 User Code=0x00002E44、Status Code=0x70026020、Finished，
日志为 `debug/audio_gao/restore_key_sram.log`。当前板上没有自动持续播放。

**目前结论：静音路径与绕过按键后的正弦生成/I2S 发送均实测通过；
原版实际按键使能及 DAC 到喇叭的出声情况仍未闭环。**
主工程音频 RTL 没有因未经证实的推测而修改。

## Verilog-2001 编译与自检：通过

2026-10-06 执行 `tools/run_sim.ps1`；两组测试均使用 Icarus 的 `-g2001 -Wall` 编译，
编译和仿真退出码均为 0。
本次仅修复工程配置，RTL 保持该次通过仿真的版本。

```text
PASS [top 3ms]: BCK=3.125MHz LRCK=48.828125kHz ratio=64, I2S one-bit delay/MSB/padding, 146 stereo pairs, 131 muted words, 162 nonzero words
PASS [units]: all 256 sine values and phase wrap, two-stage key sync, signed half/quarter gain, 7 adversarial stereo TX frames
PASS: PCM5102 + PAM8403 audio simulations completed.
```

顶层仿真覆盖两次按下和松开，包括非时钟对齐的按键变化。解码只使用外部
BCK/LRCK/DIN，与独立的数学正弦及按键同步模型比较，检查以下行为：

- BCK 周期 320ns、半周期 160ns，LRCK 完整周期 20,480ns，BCK/LRCK=64。
- 每声道 32 个 BCK，首位为延迟位，随后 16bit MSB 优先，其余补零。
- DIN 与 LRCK 只在 BCK 下降沿变化，在上升沿采样得到正确 PCM。
- 同一帧左右相等，按键松开后下一帧提交零数据，按住时有正负非零采样。
- 默认右移一位后的 PCM 在 -16384～16383 范围。

模块级测试检查 256 点完整正弦表、相位累加回绕、两级输入同步、
有符号 1/2 与 1/4 缩放，发送 `8000、7FFF、A501、5A80、0001、FFFF、0000`
七种帧，并刻意改变帧中途和右声道边界的输入，验证帧锁存与使能停顿。

## Gowin 综合、布局布线与位流：通过

工具：Gowin **V1.9.11.03 Education**。
器件：**GW5A-LV25MG121NC1/I0**，顶层 `top`。
2026-10-07 在用户已经打开的 Gowin 图形界面中修改 CPU 复用配置，点击 Apply / OK，
随后通过该窗口的 **Run All** 重新编译。综合、布局布线、时序分析和位流生成完成，
实际 PnR 日志没有 ERROR，生成了新的位流。此次验证不依赖命令行脚本覆盖参数。

### CPU/SSPI 持久配置修复

图形界面报 `PR2028` / `PR2017` 的原因是此前 CPU/SSPI 复用仅在 `build.tcl`
中设置，缺少图形界面使用的持久配置。报错时实际生成的 `device.cfg` 显示
`CPU regular_io = false`，E2 因此仍被保留为 CPU 专用脚。

现已补充并保留以下两个工程配置文件：

- `impl/PCM5102_PAM8403_process_config.json`
- `impl/project_process_config.json`

第一次仅补充磁盘配置并通过命令行构建，不能证明当前图形界面的设置已经同步。
00:12:13 再次失败的日志及配置显示，图形界面已重新写入 `CPU=false`。
随后直接检查实际 Configuration → Place & Route → Dual-Purpose Pin 窗口，
确认 **Use CPU as regular IO** 未勾选，而 SSPI 已勾选。

已直接在该窗口勾选 CPU 复用并保存，以图形界面生成的完整配置同步上述两个文件。
两者均保存 `CPU=true`、`SSPI=true`、`JTAG=false`，顶层自动识别为 `top`。
图形界面 Run All 完成后，实际 `impl/pnr/device.cfg` 确认
`CPU regular_io = true`、`SSPI regular_io = true`、`JTAG regular_io = false`，
E2 正确放置为 `clk`，原来的五个引脚约束均正确落实。
`.gitignore` 只忽略构建产物，明确保留这两个配置文件。

| 检查项 | 结果 |
| --- | --- |
| 主时钟约束 | 50MHz / 20ns |
| 内部时钟域 | 一个，板载 `clk` |
| 分析路径 / 端点 | 232 / 322 |
| Setup 违规端点 | 0 |
| Hold 违规端点 | 0 |
| 最小 Setup 裕量 | 11.281ns |
| 最小 Hold 裕量 | 0.278ns |
| Logic | 163 / 23040 |
| Register | 102 / 23280 |
| BSRAM | 1 / 56 |
| I/O | 2 个输入、3 个输出 |

引脚报告确认 E2=clk、H11=key_s1、K2=BCK、K1=LRCK、L1=DIN；
全部为 LVCMOS33，音频输出 BANK2=3.3V、DRIVE=8，S1 下拉。
源码保持参考提示词的五条引脚分配、整数分频、相位增量和默认 1/2 音量。

结果文件：

- `impl/pnr/PCM5102_PAM8403.fs`：可供 Gowin Programmer 使用的位流。
- `impl/pnr/PCM5102_PAM8403.pin.html`：引脚报告。
- `impl/pnr/PCM5102_PAM8403.tr.html`：时序报告入口，需保留配套 HTML 文件。
- `impl/pnr/PCM5102_PAM8403.rpt.txt`：布局布线和资源报告。
- `sim/build/tb_top.vcd`：3ms 顶层波形。

2026-10-08 检查时现有正式位流 SHA256（文件修改时间为 2026-10-07 00:26:58）：

```text
F63419DF95403C01A730EE28B9198B38A18EAC7CE4C65C5E6B222791FFF1825C
```

## 验证范围

2026-10-07 的构建没有下载 FPGA。2026-10-08 已下载 GAO 调试版，
并完成 H11 为低时的片内采集以及自动播放诊断版的 PCM/I2S 实测；
尚未测试原版实际按键使能、DAC 模拟输出、功放或喇叭声音。
RTL 仿真与内部 50MHz 时序通过，不代表模拟音量、失真或模块接线已经实测。
SDC 未建立 FPGA 到 DAC 之间线缆、负载及接收端的外部时序模型。

README 已依据原厂资料澄清两处参考提示词的硬件表述：芯片 SCK 需要保持低电平，
模块外部 SCK 排针是否可不接取决于板上电路；数字音量 0.5 不能保证 PAM8403 不削波。
首次播放先降低功放电位器，无电位器时按 README 调小数字音量并重新构建。
