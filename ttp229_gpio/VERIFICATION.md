# 本地验证记录

## 2026-10-07：S2 8/16 键模式

Gowin V1.9.11.03 Education 最终构建完成时间 **21:23:06（Asia/Shanghai）**。
当前位流已包含 S2 每次按下切换一次、松开保持，0=8 键 GPIO、1=16 键串口。
共享控制器及 S2 防抖源文件通过工程中的相对路径引用 `../pmod_hub75e/src/`。

功能测试 `tb_ttp229_gpio` 和 `tb_ttp229_gpio_modes` 均通过。前者继续验证八键全部键位、
每键 20 ms 防抖、两种 GPIO 极性、默认 600 ms 等待、心跳和更新后的 59 位 GAO 快照。
后者验证 S2 长按不重复、松开保持、两种串口极性、16 位帧、K1/K9/K16 及全键位图、
忽略未选来源、中途从串口切回 GPIO、清除高八位旧键值和停止/重新对齐串口时钟。
默认 20 ms S2 按下/松开防抖和回弹测试由屏幕工程的共享模块测试 `tb_ttp229_modes` 验证。
两个测试已加入默认 `tools/run_sim.ps1`。

GAO 采集 **59 位、8192 点**，包含 mode_16、S2、SCL/SDO、串口状态/位计数和 S2 防抖状态；
使用 **30/56 个 BSRAM**。50MHz 主时钟、195.3125kHz GAO 时钟和 JTAG 时钟均进入分析。
S2 输入 H10 下拉，SDO 输入 F7 上拉，SCL 输出 F6。OUT1～OUT8 输入使用 **PULL_MODE=NONE**，
避免在芯片 16 键时给复用的触摸输入施加下拉。

时序分析 3410 条路径、3757 个端点；**setup 违规 0、hold 违规 0**。
最小 setup 裕量 **6.990ns**，最小 hold 裕量 **0.245ns**。没有新增时序例外。

当前产物是 `impl/pnr/ao_0.fs` 和配套 `src/TTP229_GPIO.gao`，本轮没有下载或实板采集。
模块 TP2 硬件模式需手动配置并重新上电；GPIO/串口不能仅靠 S2 自动改写芯片模式。
接线和使用限制见 [S2 使用说明](../MODE_SELECTION.md)。

SHA256：

```text
ao_0.fs
284A3BC6F2CA1403633A3371F2C87FAB57976B18F218E3D02FDF25FB279B22C7
TTP229_GPIO.gao
936BACB82E58A1E27EE4D70C6838E203414C6EC770EC0D7E3F30B426EE8CBCC3
```

以下为更新前的 **2026-10-06 历史记录**，旧位流哈希、29 位 GAO、输入下拉及无串口端口描述
不代表当前构建。

## 2026-10-06：原独立 8 键工程

日期：2026-10-06；最终 Gowin 构建完成时间：22:13:50（Asia/Shanghai）。

## 功能自检：通过

执行 `tools/run_sim.ps1`，Icarus 编译及仿真退出码均为 0。
测试使用 1MHz 时钟保持真实毫秒时间，仿真覆盖完整 1 秒；主功能实例将启动等待改为 3ms，
另一实例保留默认 600ms 启动等待和 20ms 防抖。

- 八个键位逐个按下、松开，位图顺序正确。
- 默认高有效；参数反转后仍得到相同归一化键值。
- 两级输入同步，第 19 次采样不提交、第 20 次采样提交。
- 每键独立防抖、多键同时、两个键相差 10ms 时分别确认。
- 19ms 回弹清零计数；100μs 短脉冲只进入原始键值。
- 63 个时钟自动复位；默认 600ms 内忽略按键，随后重新进行完整确认。
- 心跳在 500ms 和 1000ms 翻转，完成一个 1Hz 周期。
- GAO 分频在复位/启动期间运行，独立时钟寄存器延迟一个主时钟周期。
- 29 位下降沿快照及 1ms 按键变化事件正确。

共验证 24 次稳定键值变化，最终输出：

```text
PASS [eight-key GPIO]: all eight bit positions, both polarities, 20-sample press/release, simultaneous/independent keys, 19 ms bounce and short pulse; 24 confirmed changes
PASS [defaults]: 600 ms startup ignored held inputs, new 20 ms confirmation window, heartbeat edges at 500 ms and 1000 ms
PASS: direct eight-key GPIO reset, startup, synchronization, debounce, GAO clock/snapshot/event and complete 1 Hz heartbeat
PASS: standalone eight-input GPIO simulation completed.
```

## Gowin 构建与引脚：通过

Gowin V1.9.11.03 Education，`tools/build.tcl` 综合、插入 GAO、布局布线和位流生成完成。

- FPGA 业务端口：9 路输入（晶振 + 8 根触摸直出），没有输出/双向触摸端口。
- 8 根信号均位于 BANK2，LVCMOS33、3.3V、下拉、DRIVE=OFF。
- 与原 `pmod_hub75e/src/HUB75E.cst` GPIO 无重叠；三个 PMOD 网络也已按官方原理图排除。
- GAO 采集 29 位，使用 30/56 个 BSRAM。
- 50MHz 主时钟、5120ns GAO 生成时钟以及工具生成的 JTAG 时钟均进入分析。
- GAO 实际生成时钟根为 `gao_clock_s1/Q`，使用 PRIMARY 全局时钟。
- 共分析 2864 条路径、2880 个端点；**setup 违规 0，hold 违规 0**。
- 最小 setup 裕量 6.070ns，最小 hold 裕量 0.248ns。
- 没有添加时钟间 false path、异步分组或其它时序例外。

结果文件：

- 位流：`impl/pnr/ao_0.fs`
- 配套 GAO：`src/TTP229_GPIO.gao`
- 引脚报告：`impl/pnr/TTP229_GPIO.pin.html`
- 时序报告：`impl/pnr/TTP229_GPIO.tr.html`

SHA256：

```text
ao_0.fs
26F591BB47C78572DC3A51AB7726C8F03E06CC205476ACC827A9CC5928418B1C

TTP229_GPIO.gao
AF12A5784DA663FBEFEC7719AB38BB45F7CDEDAD21FAAD116DAC9A5DFC2CE762
```

## 实板状态

本次没有下载 FPGA，也没有采集模块实板波形。模块改成 8 键模式并重新接线后，
需观察松开、按键 1、松开时 `keys_stable: 00 → 01 → 00`，再逐个测试其余键。
本地验证通过证明代码和本次构建检查通过，不能代替模块接线后的实际响应。
