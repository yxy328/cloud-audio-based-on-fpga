# Tang Primer 25K：PCM5102 DAC + PAM8403 功放

## 2026-10-11：Karplus–Strong 吉他拨弦版（当前源码）

当前顶层已改为单音拨弦：S1 按下并稳定 5ms 后触发一次，按住不会重复触发，
松开不切断声音，下一次按下重新拨弦。原接线、采样率与 I2S 格式保持一致。
下文正弦播放、旧仿真与位流记录属于此前版本，不能作为当前吉他版的验证结果。
现有 `impl` 位流仍是旧版本，必须重新构建后才能试听吉他。

`src/geita.v` 实现 32bit LFSR、短噪声激励、16bit 有符号延迟线、
两点平均低通和反馈损耗。每次拨弦用 N 个采样填充整条延迟线，随后循环更新：
`average = (delayed + previous) / 2`，反馈幅值减去其绝对值的
`ceil(abs(average)/512)`，避免量化后的微小直流残留。噪声激励为 ±16384；
顶层仍用 `VOLUME_SHIFT` 缩放。存储器无需复位清空：填满以后才允许反馈读取。
读取与写回分两个 50MHz 周期执行；当前帧发送上次计算值，左右声道共享同一采样。

顶层参数 `STRING_LENGTH` 默认 110，频率近似 `48828.125 / (N + 0.5)`，
即约 441.9Hz。低通的相位延迟约半个采样；整数长度只能近似调音。
例如低 E2 可取 592（约 82.41Hz），A2 取 443（约 110.10Hz），
D3 取 332（约 146.85Hz），G3 取 249（约 195.70Hz），
B3 取 197（约 247.23Hz），高 E4 取 148（约 328.81Hz）。
当前只实现一根弦；长度范围为 2..1024。
`geita.LOSS_SHIFT` 默认 9，增大会延长衰减，减小会缩短衰减，支持 1..15。
`KEY_DEBOUNCE_CYCLES` 必须为正数，默认 250000。

运行 `tools/run_sim.ps1` 会执行新拨弦反馈参考模型测试、吉他顶层 I2S 解码测试，
以及保留的基础音频模块测试。`sim/tb_top.v` 是旧正弦顶层测试，不再由该脚本执行。
新反馈测试比较 40000 个采样并覆盖松键尾音和再次触发。
2026-10-11 已运行 Icarus RTL 仿真：40000 个参考采样、顶层 I2S 与基础模块测试通过。
一秒长仿真检查 49423 个立体声帧通过；尚未完成新版综合或板上试听。

### 直接查看拨弦波形

- `sim/build/guitar_wave.png`：已生成的音频曲线图，含整体衰减、起音和局部放大。
- `sim/build/guitar_wave.vcd`：用 GTKWave 打开，选择 `dut.audio_sample`，使用有符号模拟显示。
- `sim/build/guitar_samples.csv`：从真实 I2S 引脚解码的逐帧时间、按键状态和 PCM。

运行 `./tools/run_sim.ps1 -LongWave` 可重新执行自检并生成一秒长的 VCD/CSV。
脚本自动使用工程内 `tools/local_sim/icarus/app/bin` 的仿真器。
波形查看器位于 `tools/local_sim/icarus/app/gtkwave/bin/gtkwave.exe`。
用安装了 Pillow 的 Python 运行 `tools/plot_guitar_wave.py` 可刷新 PNG。
测试台将按键防抖缩短为 2μs，按下/松开时刻为 0.2/4.2ms；采样率仍为实际硬件速率。
仿真文件不要加入 Gowin 综合文件列表；仿真顶层使用 `tb_guitar_top`。

依据上级目录的 `prompt_pcm5102_25k.md` 创建的独立 Verilog-2001 工程。
目标芯片为 **GW5A-LV25MG121NC1/I0**，顶层为 `top`。按住底板 S1，
左右声道播放约 440Hz 正弦音；松开后发送全零 PCM，BCK/LRCK 持续运行。
功放接收 DAC 的模拟音频，不需要额外的 FPGA 功放驱动模块。

已通过 RTL 和布局布线后网表的功能仿真，并生成位流。2026-10-08 已下载
GAO 调试版，板上确认 BCK/LRCK 连续运行、H11 为低时 DIN=0；
另已在无需按键的独立诊断版中实测非零正弦 PCM 和正确 I2S 格式。
原版实际按键使能与最终声音还待验证。详细记录见 `VERIFICATION.md`，
板上采集见 `debug/audio_gao/README.md`，自动播放试听见 `debug/audio_autoplay/README.md`。

## 文件与打开方式

在 Gowin EDA 中打开 `PCM5102_PAM8403.gprj`，确认顶层选择 `top`。
项目文件只列出综合源码和约束，仿真文件不参与综合。

工程附带 `impl/PCM5102_PAM8403_process_config.json` 与
`impl/project_process_config.json`，保存图形界面使用的 CPU/SSPI 管脚复用设置。
这两个配置文件是工程的一部分，复制工程或清理构建结果时应保留。
若工程已经打开，直接在当前 Gowin 的 Configuration 窗口确认 CPU 复用已勾选，
点击 Apply / OK 保存。只在外部编辑 JSON 不能保证当前界面里的设置同步更新，
界面保存工程时可能重新写入旧值；具体选项位置见下面的报错排查说明。

```text
pcm5102_pam8403/
  PCM5102_PAM8403.gprj
  README.md
  VERIFICATION.md
  src/
    clk_div.v                 50MHz 整数分频与时钟使能
    i2s_tx.v                  Philips I2S 串行发送
    nco_sine.v                32bit 相位与 256 点正弦表
    volume_key.v              两级按键同步、有符号缩放与静音
    top.v                     自动复位与模块连接
    PCM5102_PAM8403.cst        原提示词的五个管脚
    PCM5102_PAM8403.sdc        50MHz 主时钟与按键同步例外
  sim/
    tb_top.v                  3ms 顶层自检
    tb_audio_units.v          波表、音量、I2S 边界自检
    build/                    仿真生成的 VCD / VVP
  tools/
    run_sim.ps1               一键仿真
    build.tcl                 Gowin 综合、布局布线、位流生成
  impl/
    PCM5102_PAM8403_process_config.json  本工程的持久配置
    project_process_config.json         默认工程配置
    pnr/PCM5102_PAM8403.fs     本次已生成的下载文件
```

## FPGA → DAC 数字接线

下表的 **E2 / H11 / K2 / K1 / L1 是 FPGA 封装球号**，不是排针物理序号。
连接外部模块时，在自己的 Dock 上确认对应引出脚；不能将 K2 理解成“排针第 2 脚”。
约束与参考提示词一致，三个音频输出位于 3.3V BANK2。

| 顶层端口 | FPGA 球号 | 方向 | 连接 |
| --- | --- | --- | --- |
| `clk` | E2 | 输入 | 板载 50MHz 晶振，外部不接线 |
| `key_s1` | H11 | 输入 | 板载 S1，按下高有效，内部下拉 |
| `i2s_bck` | K2 | 输出 | PCM5102 模块 BCK / BCLK |
| `i2s_lrck` | K1 | 输出 | PCM5102 模块 LRCK / LCK / WS |
| `i2s_din` | L1 | 输出 | PCM5102 模块 DIN |
| GND | 底板 GND | — | PCM5102 GND、PAM8403 电源 GND、音频输入 GND 共地 |

这是独立下载的音频工程。当前目录内的 HUB75E 工程把 K2/L1 用作调试输出，
TTP229 GPIO 工程把 K1 用作 OUT1 输入；切换到本工程前，移除这些脚原来的外部连接，
尤其不能让 TTP229 OUT1 和新的 LRCK 输出同时驱动 K1。

PCM5102 模块采用 3.3V 数字逻辑。芯片电源为 3.3V；模块若带稳压器和独立 VIN，
按模块标注为 VIN 供电，3V3 与 VIN 不能混用。FPGA 音频线和 DAC 配置脚不能接 5V。

## DAC 配置与 SCK

本工程没有 MCLK 输出，使用 PCM5102 内部 BCK PLL。与参考文件中
“SCK 悬空”的表述相比，需要区分模块排针和芯片输入：**芯片 SCK 必须保持低电平**，
才能进入三线模式。TI 数据手册 §9.3.5.3 说明，SCK 连续 16 个 LRCK 周期为低时，
设备由 BCK 建立内部时钟。因此，只有模块已经将 SCK 接地或可靠下拉时，外部 SCK 排针
才可以不接；否则将 SCK 接 GND。无需修改 FPGA 端口或添加 PLL。
[依据：TI PCM510xA 数据手册](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf)。

配置以芯片功能名为准，H1L～H4L 是参考提示词所用模块的焊盘标记：

| 功能 | 目标电平 | 参考模块焊盘 | 含义 |
| --- | --- | --- | --- |
| FLT | LOW | H1L | 普通延迟滤波 |
| DEMP | LOW | H2L | 关闭 44.1kHz 去加重 |
| XSMT | HIGH，3.3V | H3L | 取消芯片静音 |
| FMT | LOW | H4L | Philips I2S 格式 |

若模块丝印与上述对应关系不同，按实际电路核对功能；FMT 高电平是左对齐格式，
不能与本工程的 I2S 时序混用。芯片功能、电平与数字格式同样见
[TI 数据手册第 5 页](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf)。

## DAC → 功放 → 喇叭模拟接线

| 起点 | 终点 |
| --- | --- |
| PCM5102 OUTL / L | PAM8403 左声道输入 L / LIN |
| PCM5102 OUTR / R | PAM8403 右声道输入 R / RIN |
| PCM5102 音频 GND | PAM8403 输入 GND |
| PAM8403 L+、L− | 左喇叭的两根线 |
| PAM8403 R+、R− | 右喇叭的两根线 |

PAM8403 按模块标注使用稳定的 5V 电源，并将电源 GND 与 FPGA、DAC 共地。
不要用 FPGA GPIO 或 DAC 模拟输出给功放供电。输入使用模块的音频输入端，
确认模块包含输入隔直电容；若直接接裸芯片输入，按原厂应用电路设计输入耦合。

PAM8403 为桥接输出：**L−、R− 都不是 GND**。两个喇叭各自独立两线，
不能把 L−/R− 接公共地、相互短接，也不能当作共地耳机口使用。
单个喇叭接一个声道的一对输出即可，另一声道输出不接；不要并联两个声道。

功放供电范围和增益可核对
[Diodes PAM8403 原厂页面](https://www.diodes.com/part/view/PAM8403)。

## 音量与时钟

保留参考提示词中的整数分频和相位增量：

| 项目 | 本工程数值 |
| --- | --- |
| 主时钟 | 50MHz |
| BCK | 50MHz / 16 = 3.125MHz，周期 320ns |
| 每声道时隙 | 32 个 BCK，数据占 16bit |
| LRCK / 采样率 | 3.125MHz / 64 = 48,828.125Hz，周期 20,480ns |
| NCO 相位增量 | `32'd38_702_432` |
| 实际数字正弦频率 | 约 439.9957Hz |
| 默认缩放 | `VOLUME_SHIFT=1`，有符号算术右移一位 |

48,828.125Hz 比标准 48kHz 高约 1.725%；NCO 按实际采样率生成约 440Hz，
不是把 48kHz 音源加速播放。TI 的时钟检测支持标准频段附近 ±4% 的容差，
三线模式使用 64 倍 BCK，说明见
[TI 数据手册 §9.3.5.2～9.3.5.3](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf)。

**数字音量 0.5 不保证模拟功放不削波。** 默认值保留参考参数，首次播放应先将
功放电位器调低。PCM5102 满幅输出约 2.1Vrms，PAM8403 典型固定增益可达 24dB；
据此估算，0.5 倍输入仍可能超出 5V 功放的输出摆幅。无电位器模块可先将
`src/top.v` 的 `VOLUME_SHIFT` 默认值改为 `4`（约 1/16），重新综合，再逐步调音量。
这一估算依据 [TI 的满幅输出规格](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf)
与 [Diodes 的增益参数](https://www.diodes.com/part/view/PAM8403)，实际还取决于模块电路、
电源和喇叭。修改默认音量后，顶层仿真的参考右移量与幅值界限也需同步调整。

## I2S 与按键行为

所有寄存器在 50MHz 上升沿工作，用时钟使能控制输出，避免新增内部 BCK/LRCK 时钟域。
每个声道在 BCK 下降沿启动时隙：第 0 位为 I2S 延迟位，第 1～16 位发送 MSB～LSB，
第 17～31 位补零；DAC 在 BCK 上升沿采样。LRCK 低是左声道，高是右声道。

左声道开始时锁存一次有符号采样值，右声道复用该值，保证按键在半帧内变化也不会
破坏左右一致性。NCO 每个完整立体声帧累加一次，静音期间继续运行。
S1 经过两级同步后，在下一帧边界提交播放或静音；数字响应延迟约一个采样周期以内，
芯片滤波与模拟输出有额外延迟。

本工程未加入毫秒级机械按键防抖或音量渐变，按键回弹与突然切断正弦可能产生短暂点击声。
当前验收范围是参考提示词中的最小音频闭环。

## 仿真、构建与下载

以下命令在本工程目录执行：

```powershell
# Icarus 默认安装位置为 C:/iverilog/bin，可用参数替换。
.\tools\run_sim.ps1
# 例如：.\tools\run_sim.ps1 -IverilogDir 'D:/iverilog/bin'

# gw_sh 已加入 PATH 时：
gw_sh tools/build.tcl

# 本机实际 Gowin 安装位置：
& 'E:\130_FPGA_Verilog\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' tools/build.tcl
```

`tb_top.v` 使用 50MHz 时钟运行 3ms，从外部 I2S 端口解码并与数学正弦模型比较，
检查 64 倍时钟、32bit 时隙、一位延迟、MSB 顺序、补零、左右一致、正负半波及静音。
`tb_audio_units.v` 检查全部 256 个波表值、相位回绕、同步器、有符号 1/2 与 1/4 缩放，
并在帧中途改变输入以检查发送机锁存。波形位于 `sim/build/tb_top.vcd`。

Gowin 构建脚本指定顶层 `top`，启用器件的 CPU/SSPI GPIO 配置，保留 JTAG 下载接口。
图形界面直接编译时也使用上述持久配置，不依赖执行构建脚本。
生成的 `impl/pnr/PCM5102_PAM8403.fs` 可用 Gowin Programmer 下载到 FPGA SRAM，
随后按住 S1 验证播放。2026-10-08 排查时已经执行 GAO 调试版的 SRAM 下载，
当前已恢复原按键行为的 GAO 位流，与原音频工程共用 RTL，
采集操作见 `debug/audio_gao/README.md`。无需按键的自动播放诊断版和下载脚本见
`debug/audio_autoplay/README.md`。

若出现 `PR2028` 或 `PR2017`（E2 为 CPU/SSPI 专用脚），打开
**Project → Configuration → Place & Route → Dual-Purpose Pin**，确认
**Use CPU as regular IO** 已勾选；**Use SSPI as regular IO** 已勾选
（GW5A-25 的 MBGA121N 封装通常固定启用），**Use JTAG as regular IO** 不勾选。
保存配置后重新运行综合和布局布线。E2 是板载晶振脚，保持原约束即可。
[选项含义见高云官方用户指南 §4.3.3](https://cdn.gowinsemi.com.cn/SUG100.pdf)。

SDC 检查内部 50MHz 时序，仅排除 S1 到第一级同步器的异步输入路径。
未建立线缆和 DAC 接收端的外部时序模型；布线后仍需确认 DAC 引脚处的信号质量。

## 首次播放排查

1. 先断电接线，确认共地、功放低音量、喇叭独立两线，再上电。
2. 无声时先查 XSMT 是否高、FMT 是否低、芯片 SCK 是否保持低电平。
3. 在 DAC 端测 BCK 约 3.125MHz、LRCK 约 48.828kHz；按住 S1 后 DIN 有非零数据。
4. 数字波形正确仍无声，再查 DAC 模拟 L/R 输出、功放供电及输入、喇叭接线。
5. 有破音时降低模拟电位器或增加 `VOLUME_SHIFT`，并确认 5V 电源不会因负载下跌落。
