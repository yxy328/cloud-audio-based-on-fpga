# HUB75E 显示工程：S2 选择 8 键直读 / 16 键串口

> 2026-10-18：音频主工程已加入手机 App v1.4 控制的 8/16 键切换，S2 仍用于点阵屏操作。音频接线、两种串行极性和演奏功能请看 [音频迁移说明](pcm5102_pam8403/REFERENCE_MIGRATION.md)。下文“音频固定 8 键”为此前记录。

2026-10-10：音频主工程 `pcm5102_pam8403/PCM5102_PAM8403.gprj` 已复用同一份
`pmod_hub75e/src/ttp229_gpio_input.v` 实现八键弹奏。音频工程固定使用 8 键直连，
S2 用于《小星星》重播；OUT1 改接 K4/J3 第 5 脚，其余直连引脚沿用下表。
音频工程的完整接线和操作见 [音频 README](pcm5102_pam8403/README.md)。
音频直连模式 SCL 也不能悬空：用户已实测接 GND 后消除误响，保持接地时不接 F6，SDO 不接。
可选接法为 SCL 接模块 3.3V 或音频顶层 F6 固定高输出，各接法互斥。

2026-10-07：两个主工程都加入板载 **S2 / H10** 模式选择。上电默认
`mode_16=0`（8 键），S2 每次连续按下 20 ms 切换一次；松开后保持模式。
长按不重复切换，松开也必须连续稳定 20 ms，才能接受下一次按下。
模式值始终为 **0=8 键、1=16 键**。S1 仍是屏幕工程的复位键。

| 工程 | mode_16=0 | mode_16=1 | LED 点阵显示 |
| --- | --- | --- | --- |
| pmod_hub75e | OUT1～OUT8 直读，SCL 保持空闲 | SCL/SDO 串口读取 K1～K16，忽略 OUT 输入 | 两种模式都控制 HUB75E |
| ttp229_gpio | OUT1～OUT8 直读，SCL 保持空闲 | SCL/SDO 串口读取 K1～K16，忽略 OUT 输入 | 无，仅 GAO 调试 |

S2 不会改变触摸芯片的硬件配置。TP2 开路选择芯片 8 键，TP2 配置为低选择
芯片 16 键；选项在上电时锁存，改变焊盘后必须重新给模块上电。
芯片 16 键模式只能串口输出，不能用 OUT1～OUT8 读取低八键。

**使用带显示的双模式功能，请打开 `pmod_hub75e/HUB75E.gprj`。**
OUT1～OUT8 读取逻辑已从独立 GPIO 工程提取为 `src/ttp229_gpio_input.v`，
接入屏幕工程的 `mode_16=0`。8 键模式不读取任何串口位。
接线由用户在中途手动切换，模块配置为 8 键时选择直读，配置为 16 键时选择串口。

## 接线

- S2 使用底板现有按键 H10，按下为高，FPGA 开启下拉，无需另接模式线。
- 两个工程的串口都是 FPGA **F6 输出 SCL、F7 输入 SDO**，SDO 上拉。
- 改为串口接线时：**先拆掉 SCL 到 GND 或 3.3V 的固定连接**，
  再把模块 SCL 接到 FPGA F6，SDO 接到 F7。
- 屏幕工程新增 OUT1～OUT8 输入，沿用 GPIO 工程的 K1/L2/J4/G1/G2/L3/L4/J2。
  这些引脚不设置内部上下拉，因为芯片 16 键时它们复用为触摸电极输入。
- 模块供电使用 3.3V，GND 共地。首次上电保持 600 ms 等待，不触摸校准中的按键。

| 模块直出 | FPGA J3 物理脚号 | FPGA 球号 | 屏幕顶层端口 |
| --- | ---: | --- | --- |
| OUT1 | 2 | K1 | touch_out[0] |
| OUT2 | 4 | L2 | touch_out[1] |
| OUT3 | 6 | J4 | touch_out[2] |
| OUT4 | 7 | G1 | touch_out[3] |
| OUT5 | 8 | G2 | touch_out[4] |
| OUT6 | 9 | L3 | touch_out[5] |
| OUT7 | 10 | L4 | touch_out[6] |
| OUT8 | 21 | J2 | touch_out[7] |

## 状态机与数据提交

共享 `pmod_hub75e/src/ttp229_mode_select.v` 使用两个同步寄存器和 `case` 状态机：

`S_LOW → S_CONFIRM_HIGH → S_HIGH → S_CONFIRM_LOW → S_LOW`

高、低确认状态各要求 20 ms 连续稳定电平，回弹回到前一稳定状态并清零计数。
只有高电平确认完成时翻转模式，`mode_changed` 是一个主时钟周期的脉冲。
两个顶层默认 `S2_TOGGLE_MODE=1`；设为 0 可使用电平直接选择。

串口状态为 `S_IDLE / S_ACTIVE / S_VALID / S_REARM / S_OFF`。
进入串口时保持 SCL 空闲 3 ms，再从 K1 开始；离开串口时丢弃未完成帧、
清除串转并寄存器和旧键值，并停止串口时钟。600 ms 启动计时独立于所选输入源，
切换不能提前接受触摸输入。未选输入源不驱动 UI。

屏幕工程的直读模块保留每键独立 20 ms 防抖；每 1 ms 提交一帧，valid 宽 20 μs。
UI 对直读结果再确认 3 个采样，对串口结果确认 3 个完整串口帧。
模式切换清除旧键值及未完成的确认，保留当前图案和亮度。
K1/K2 切图；8 键时 K7/K8 减/加亮度，16 键时 K15/K16 减/加亮度。
GPIO 工程保留每键独立 20 ms 防抖，原始和稳定键值统一为 16 位，8 键时高八位为 0。

## 构建与检查

两个工程均通过 `tools/run_sim.ps1` 仿真；各自 `tools/build.tcl` 生成
`impl/pnr/ao_0.fs`，使用本次生成的 `.gao` 文件配套采集。未下载或进行本轮实板采集。
详细测试、时序报告及 SHA256 见两个工程的 `VERIFICATION.md`。

核对来源：[Sipeed Dock 原理图](https://dl.sipeed.com/fileList/TANG/Primer_25K/02_Schematic/Tang_Primer_25K_Dock_60033_Schematic.pdf)、
[TonTek TTP229-BSF 原厂手册](https://www.tontek.com.tw/uploads/product/97/TTP229-BSF_V1.1_EN.pdf)。
