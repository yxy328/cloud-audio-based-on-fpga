# 历史快照：第一步单声部 DDS（当前开发使用原工程）

后续开发已合并到原工程 [pcm5102_pam8403](../pcm5102_pam8403/README.md)。当前统一在原工程编译下载；本目录保留第一步早期验证快照。

**当前音频工程是 `../pcm5102_pam8403/PCM5102_PAM8403.gprj`，位流是该工程的
`impl/pnr/PCM5102_PAM8403.fs`。本目录的 `DDS_STEP1.fs` 只包含第一步，不包含 ADSR 或四声部。
下面的下载、操作和 UserCode 均为 2026-10-09 的历史记录。**

独立 Gowin 工程：`DDS_STEP1.gprj`，器件 `GW5A-LV25MG121NC1/I0`，顶层 `top`。
已生成位流 `impl/pnr/DDS_STEP1.fs`，RTL 仿真、布局布线及布局布线后的功能仿真通过。
2026-10-09 已下载到开发板 SRAM，回读 UserCode 为 `0x00005C06`，与本版本位流一致。
当时用户已报告此前版本能够发声；该历史版本的音高切换在本记录结束时仍待现场试听。

## 1. 历史版本下载与操作（用于复现第一步）

1. 在 Gowin Programmer 中选择本目录的 `impl/pnr/DDS_STEP1.fs`，执行 **SRAM Program**。
   该历史位流 UserCode 为 `0x00005C06`；当时尚未合并变调的旧主工程位流为 `0x00007A8C`。
   这两个编号不代表当前主工程；当前版本见主工程 README。
   在 Programmer 中按 Configure Device，确认 File name 后保存；仅打开新的源码文件不会改变 Programmer 中旧的下载路径。
2. **按住板载 S1：持续发声；松开 S1：静音。** 默认音高为 A4，440Hz。
3. 每按下并松开一次板载 S2，切换一个音高：**440 → 523.25 → 659.26 → 880 → 440Hz**。
4. 可以一直按住 S1，同时用 S2 改变音高。长按 S2 只切换一次，不自动重复。

S1、S2 都采用两级同步和约 1ms 稳定确认，短于确认时间的脉冲会被忽略。
S2 在静音期间也可以选择下一音高，再按住 S1 听到选择后的音。
本步骤只有一个声部；S2 是音高选择键，不能作为第二个并发声部。
S1 目前直接控制音量开关，渐强、渐弱的 ADSR 在第二步加入。

默认数字音量为满幅的 1/16，左右声道输出相同音频。试听时先调低功放电位器，再逐步调高。

## 2. FPGA 与音频模块接线

E2、H11 等是 FPGA **封装球号**，不是排针物理序号。前三项是板载信号，不需要外接线。

| 端口 | FPGA 球号 | 连接 / 功能 |
| --- | --- | --- |
| `clk` | E2 | 板载 50MHz 晶振 |
| `key_s1` | H11 | 板载 S1，按下高有效，内部下拉 |
| `key_s2` | H10 | 板载 S2，按下高有效，内部下拉 |
| `i2s_bck` | K2 | PCM5102 BCK / BCLK |
| `i2s_lrck` | K1 | PCM5102 LRCK / LCK / WS |
| `i2s_din` | L1 | PCM5102 DIN |
| GND | 底板 GND | FPGA、DAC、功放电源和功放输入共地 |

沿用原音频工程的三根数字音频线即可。K1 当前是 FPGA 的 LRCK 输出，不能同时连接 TTP229 OUT1。
S1/H11、S2/H10 对应关系可核对 [Sipeed 官方 Dock 原理图第 1 页](https://dl.sipeed.com/fileList/TANG/Primer_25K/02_Schematic/Tang_Primer_25K_Dock_60033_Schematic.pdf)。

PCM5102 按实际模块标注供电；FPGA 数字信号为 3.3V。
没有外部 MCLK 输出，PCM5102 的**芯片 SCK 输入保持低电平**，利用内部 BCK PLL。
如果模块没有自带 SCK 下拉，将 SCK 接 GND。

| PCM5102 配置 | 电平 |
| --- | --- |
| FMT | LOW：I2S |
| XSMT | HIGH，3.3V：解除静音 |
| DEMP | LOW |
| FLT | LOW：沿用普通滤波配置 |

[PCM510xA 原厂数据手册](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf)

模拟通路：PCM5102 的 L/R/GND → PAM8403 的 L/R/输入 GND。
PAM8403 按模块标注供电，常见模块为 5V；一个喇叭接对应声道的 `+`、`−` 两端。
功放的 `L−`、`R−` 属于桥接输出，不接公共 GND。单喇叭使用一个声道即可。

## 3. 生成方式与接口

全部音频样本由 FPGA 实时生成：

`S1/S2 → 硬件同步与确认 → 实时音高寄存器 → 32位相位累加器 → 正弦表 → 音量门控 → I2S`

波表是一个周期的数学正弦值，有效 1024 点、16 位有符号，使用包含端点的 257 项四分之一周期表。
没有歌曲录音、预录 PCM、整段音频播放或自动音符序列。

`dds_voice.v` 提供运行时 `phase_inc[31:0]` 输入，后续键盘事件可以直接改变它：

`phase_inc = round(frequency_hz * 2^32 / 48828.125)`

| S2 选择序号 | 音符 | 目标频率 | `phase_inc` |
| --- | --- | --- | --- |
| 0 | A4 | 440Hz | 38702809 |
| 1 | C5 | 523.2511306Hz | 46025656 |
| 2 | E5 | 659.2551138Hz | 57988693 |
| 3 | A5 | 880Hz | 77405619 |

相位只在每个音频采样使能时累加。变调保持相位连续，静音时也继续运行相位。
采样率为 **48,828.125Hz**，每帧 20.48µs；BCK 为 **3.125MHz**。
所有内部逻辑使用同一个 50MHz 主时钟，没有软件逐样本运算。

I2S 每声道 32 个 BCK：第 0 位为一拍延迟，第 1～16 位为 MSB 到 LSB，其余补零。
每个立体声帧只锁存一次样本，左右声道一致；DIN 和 LRCK 在 BCK 下降沿更新。

## 4. 文件与工具

```text
pcm5102_dds_step1/
  DDS_STEP1.gprj
  src/
    top.v
    button_filter.v
    pitch_control.v
    dds_voice.v
    sine_rom.v
    clk_div.v
    i2s_tx.v
    DDS_STEP1.cst
    DDS_STEP1.sdc
  sim/
    tb_dds_voice.v
    tb_button_filter.v
    tb_top.v
  tools/
    run_sim.ps1
    build.tcl
    program_sram.ps1
  impl/
    DDS_STEP1_process_config.json
    project_process_config.json
    pnr/DDS_STEP1.fs
  VERIFICATION.md
```

在此工程目录打开 PowerShell：

```powershell
# RTL 自检；日志保存在 sim/build/*.log。
./tools/run_sim.ps1

# 综合、布局布线，生成位流及原语网表。
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build.tcl

# 布局布线后的功能仿真，未标注 SDF。
./tools/run_sim.ps1 -Netlist

# 开发板连接并上电后，下载到 SRAM。
./tools/program_sram.ps1
```

仿真脚本可传入 `-IverilogDir` 和 `-GowinDir`。下载脚本默认 USB Debugger A、位置 385；
连接位置变化时用 `-CableLocation` 指定实际位置，也可以直接使用图形界面选择下载器。
脚本的操作为 SRAM Program，并自动回读 UserCode 与实际下载文件比较。
没有修改 Flash；重新上电需要再次下载本目录的新位流，否则可能恢复原来的固定音高程序。

## 5. E2 管脚复用配置

工程的两份完整配置 JSON 都保存 `CPU=true`、`SSPI=true`、`JTAG=false`，构建脚本也指定相同设置。
E2 已在本次布局布线中成功放置为 `clk`；H10、H11 也已按约束放置。

如果图形界面使用了其他配置，进入 Configuration 的 Dual-Purpose Pin：

- 勾选 **Use CPU as regular IO**。
- 勾选 **Use SSPI as regular IO**。
- 保留 JTAG 下载接口，**Use JTAG as regular IO 不勾选**。
- 点击 Apply / OK 后重新运行。

## 6. 验收范围

已验证可变音高、相位连续、门控静音、短脉冲过滤、长按不重复、音高循环和 I2S 格式。
布局布线满足 50MHz，具体资源和测试结果见 [VERIFICATION.md](VERIFICATION.md)。

测试中的 S1 数字输入到首个解码非零 PCM 样本为 **1.023564ms**，是仿真中一次起音的结果。
它不包含实际按键触点抖动、DAC 滤波/静音恢复、功放或模拟输出延迟，不能当作整机 ≤10ms 的实测验收。
当前已完成 SRAM 下载和版本回读；仍需现场试听音高切换和静音，确认新版本的模拟发声。
