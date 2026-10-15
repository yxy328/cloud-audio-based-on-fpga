# Tang Primer 25K：七键 / 压力 / 手势 / 吉他 / 蓝牙 / 64×64 LED

2026-10-15 融合：以本工程保留的 HC-05、安卓曲谱助手和 64×64 HUB75E 指引为基础，
接入 `ALL_IN` 的 APDS-9960 手势、五种手势音色、颤音和 Karplus–Strong 单弦吉他。
S1/S2 继续控制曲谱，新音源由蓝牙/App 控制。接线、命令与验证边界见
[融合说明](SENSOR_INTEGRATION.md)。独立红外对管尚未接入，等待型号和用途。

2026-10-15 修正：赛题要求输出由 FPGA 根据实时演奏指令逐音、逐样本生成，基础复音数 ≥4，支持实时变调、ADSR 与混音，禁止预录 PCM 播放、预置推流和整段录音触发。
此前将《结算画面》转成 PCM 下载播放的方案违反该要求，已撤回。**旧位流 UserCode=0x00009C48 不用于比赛或本轮验收**；当前曲谱与屏幕版本的位流标识、时序、测试及 SHA256 统一见 [验证记录](VERIFICATION.md)。

继续使用原工程 `PCM5102_PAM8403.gprj`，器件 `GW5A-LV25MG121NC1/I0`，顶层 `top`。
PCM5102 可以保留，它只把 FPGA 实时合成的 I²S 采样转换为模拟声音；PAM8403 负责功率放大。

```text
TTP229 K1～K7 → 同步/防抖 → 七路独立 DDS + ADSR → 实时混音 → I²S → PCM5102 → PAM8403
FSR402 → 分压 → GW5A 片内 ADC → 音量增益或音高比例 ────────────┘
HC-05 → 键位配置 / 音符曲谱暂存 / 演奏事件日志
APDS-9960 → 手势方向 → 五音色/颤音 ───────────────→ 实时混音
HC-05 GUITAR → Karplus–Strong 单弦拨弦 ───────────→ 实时混音
```

七个音符键各占独立声部，可同时发声；正弦 ROM 只存一个周期的数学波形，不存歌曲录音。
手势和吉他同样由 FPGA 实时计算采样，不播放预录音频。
生产默认 `ENABLE_DEMO_SCORE=0`，自动曲谱不会发声。下载谱用于 HUB75E 七轨下落指引，现场按键驱动音频。
蓝牙协议和日志见 [蓝牙曲谱与演奏记录](BLUETOOTH_MEDIA.md)，接线与改键见 [HC-05 说明](HC05_KEYMAP.md)。
安卓手机继续使用现有 HC-05：[安装曲谱助手与下载步骤](android_app/README.md)。支持内置示例、CSV、标准 MIDI0/1；手机文件经蓝牙下载到 FPGA RAM，首版没有互联网曲库。

## 现场操作

TTP229 使用 **8 键直连模式**：TP2 开路，TP3、TP4 短接启用多键，改变跳线后重新上电。
模块供电 3.3V 并与 FPGA、音频模块共地；上电前 600ms 不触摸，等待校准。
本工程读取 OUT1～OUT8，SDO 不接。**SCL 不可悬空**；当前用户实测 SCL 接 GND 后恢复正常，保持此接法且不接 F6。
也可改接模块 3.3V 或 `touch_scl` 的 F6 固定高输出，三种接法只能选一种；F6 不得同时接地。

- K1～K7 默认弹奏 Do、Re、Mi、Fa、Sol、La、Si（C4～B4）；按住持续发声，松开后约 10ms 渐弱到零，各键独立。
- K8 每次确认按下在压力音量/音高模式之间切换，长按只切换一次；K8 不发音，上电默认音量模式。
- 音量模式轻压约 100%、重压约 25%；音高模式轻压原音高、重压降低一个八度。FSR402 共同控制七个触摸声部，本身不触发音符。
- 已下载有效曲谱时，S1 开始/停止指引，S2 从头重启。开始后预备1500ms，音符下落到判定线时按对应键；无有效谱时 S1/S2 不动作，蓝牙 `PLAY` 返回 `ERR,STATE`。
- HUB75E 显示七轨、青色下落音符、橙色到时目标和底部触摸反馈，支持和弦与休止；首版没有计分和长音尾条。屏幕接线与显示范围见 [RHYTHM_GUIDE.md](RHYTHM_GUIDE.md)。
- APDS-9960 四方向手势发音；默认 C4～F4，可用 App 切换 G4～C5，以及正弦/钢琴/长笛/尤克里里/鼓和颤音。它们只作用于手势音源，触摸七键保持原来的 DDS/ADSR。
- App“拨弦一次”或蓝牙 `GUITAR` 触发约 442Hz 单弦，松开按键/停止曲谱不截断尾音；再次命令重新拨弦。

蓝牙断开后现场合成继续工作；已提交的 RAM 曲谱继续保留，掉电丢失。
MP3/FLAC 不能直接得到准确谱面；需要人工制谱或离线转谱后校对音高、起音和时长。外部存储若后续增加，只保存音符事件/配置，不作为预录音频播放路线。

## FPGA 与模块接线

以下 E2、K2 等是 FPGA 封装球号，不是排针物理序号。前三项为板载信号，无需外接。

| 端口 | FPGA 球号 | 连接 / 功能 |
| --- | --- | --- |
| `clk` | E2 | 板载 50MHz 晶振 |
| `key_s1` | H11 | 板载 S1，按下高有效、内部下拉 |
| `key_s2` | H10 | 板载 S2，按下高有效、内部下拉 |
| `i2s_bck` | K2 | PCM5102 BCK / BCLK |
| `i2s_lrck` | K1 | PCM5102 LRCK / LCK / WS |
| `i2s_din` | L1 | PCM5102 DIN |
| `touch_scl`（可选） | F6 | 固定高；不用此输出时不接 |
| `hc05_rx` | F2 / J3 第16脚 | HC-05 TXD |
| `hc05_tx` | F1 / J3 第15脚 | HC-05 RXD |
| `scl` | H4 / J3 第23脚 | APDS-9960 SCL，开漏、上拉到 3.3V |
| `sda` | G4 / J3 第24脚 | APDS-9960 SDA，开漏、上拉到 3.3V |
| GND | 底板 GND | FPGA、DAC、功放、触摸、蓝牙共地 |

| 触摸输出 | 顶层端口 | FPGA 球号 | J3 物理脚号 | 默认音符 |
| --- | --- | --- | ---: | --- |
| OUT1 / K1 | `touch_out[0]` | K4 | 5 | C4 / Do |
| OUT2 / K2 | `touch_out[1]` | L2 | 4 | D4 / Re |
| OUT3 / K3 | `touch_out[2]` | J4 | 6 | E4 / Mi |
| OUT4 / K4 | `touch_out[3]` | G1 | 7 | F4 / Fa |
| OUT5 / K5 | `touch_out[4]` | G2 | 8 | G4 / Sol |
| OUT6 / K6 | `touch_out[5]` | L3 | 9 | A4 / La |
| OUT7 / K7 | `touch_out[6]` | L4 | 10 | B4 / Si |
| OUT8 / K8 | `touch_out[7]` | J2 | 21 | 压力模式切换 |

OUT1 已从屏幕工程 K1/J3 第2脚迁到 K4/J3 第5脚，避免与 LRCK 冲突。
八路默认弱下拉，仅适用于 8 键 OUT 直出模式，不能套用于 16 键电极模式。

FSR402 使用一路转换模块 AO 经 **22kΩ / 4.7kΩ 分压**接 GW5A 片内 ADC，正端 J8/J3 第36脚，负端 K8/J3 第35脚接 GND。
**ADC 仅接受 0～1V，不可直连模块 AO 的 3.3V/5V。** 量程和标定见 [FSR402.md](FSR402.md)。

PCM5102 按模块标注供电，数字信号为 3.3V；芯片 SCK 保持低电平，使用内部 BCK PLL，无外部 MCLK。
模块无 SCK 下拉时接 GND。FMT=LOW（I²S）、XSMT=HIGH（3.3V 解除静音）、DEMP=LOW、FLT=LOW。
模拟 L/R/GND 接 PAM8403 对应输入；功放按模块标注供电，喇叭接同声道 `+`/`−` 两端，桥接输出 `L−`/`R−` 不接公共 GND。
先调低功放电位器，再逐步调高。

## 实时合成参数与验收边界

采样率 **48,828.125Hz**，每帧 20.48µs；BCK **3.125MHz**，内部逻辑共用板载 50MHz 时钟。
I²S 每声道 32 个 BCK：一位延迟、16 位 MSB 优先、余位补零，左右声道相同；DIN/LRCK 在 BCK 下降沿更新。
DDS 使用 32 位相位累加器：`phase_inc = round(frequency_hz × 2^32 / 48828.125)`，运行时变调保持相位连续。
每路包络和乘法独立，混音使用符号扩展与饱和处理；默认每声部峰值为满幅的 1/16。

参数位于 `src/top.v`，修改后需重新构建、下载：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `ENABLE_DEMO_SCORE` | 0 | 默认禁止自动曲谱发声 |
| `ADSR_ATTACK_SAMPLES` | 98 | 起音约 2ms |
| `ADSR_DECAY_SAMPLES` | 3906 | 衰减约 80ms |
| `ADSR_SUSTAIN_LEVEL` | 39321 | 维持约 60% |
| `TOUCH_ADSR_RELEASE_SAMPLES` | 488 | 触摸音释放约 10ms |
| `ADSR_RELEASE_SAMPLES` | 4883 | 仅启用曲谱试听时，歌曲释放约 100ms |
| `TOUCH_STARTUP_US` | 600000 | 上电等待 600ms |
| `TOUCH_DEBOUNCE_MS` | 2 | K1～K7 按下/松开确认 |
| `TOUCH_MODE_DEBOUNCE_MS` | 20 | K8 模式切换确认 |
| `HC05_BAUD` | 9600 | 蓝牙数据模式 UART 波特率 |
| `GUIDE_LEAD_MS` | 1500 | 音符提前下落与首音预备时间 |

单键按住时可实时变调；复音时 FSR 统一影响七键，尚无逐声部选择接口。
每声部 ADSR 实时运行，但 A/D/S/R 参数目前为编译期配置，没有运行时设置命令。
将 `ENABLE_DEMO_SCORE` 主动改为 1 才能自动合成下载谱/内置《小星星》，只供开发演示；预存曲谱自动演奏不能作为现场演奏验收。

移除违规播放路径不等于全部赛题要求已经验收。仍需板上验证至少四路独立演奏、实际输入到出声延迟、实时变调、包络表现、ADC 标定和屏幕指引。
FPGA 输入后的仿真延迟不包含 TTP229 自身扫描、DAC 和功放模拟延迟，不能直接代表整机延迟。

## 构建与验证

在本工程目录 PowerShell 运行：

```powershell
./tools/run_sim.ps1
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build.tcl
```

位流路径仍为 `impl/pnr/PCM5102_PAM8403.fs`。必须使用 [验证记录](VERIFICATION.md) 确认的修正版，不能根据同名路径判断旧位流已更新。
Gowin IDE 已打开旧工程时关闭再重开同一 `.gprj`，刷新新增/删除的文件清单；编译不会自动更新板上 SRAM。
用户连接开发板后可用 Programmer 的 **SRAM Program**，或 `./tools/program_sram.ps1` 下载；SRAM 断电丢失，本轮不自动写 Flash。

共享输入模块为 `../pmod_hub75e/src/ttp229_gpio_input.v`，移动工程时保留相对目录。
工程持久配置与 `build.tcl` 均设置 CPU/SSPI 为普通 IO、保留 JTAG；遇到 E2 复用错误时，在 Configuration 的 Dual-Purpose Pin 中核对 CPU=true、SSPI=true、JTAG=false 后重新运行。

此前自动曲谱、录音试听和旧位流编号仅为历史记录，不适合作为本轮实时演奏验收证据。
旧工程 `../pcm5102_dds_step1/`、`debug/` 和压缩包保留历史快照；后续生产音频修改统一使用此工程。
