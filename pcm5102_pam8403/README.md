# Tang Primer 25K：触摸 / 压力 / 红外 / 手势 / 吉他 / 蓝牙 / 64×64 LED

**2026-10-27 曲谱弯音已接入：[完整交付与回退](reports/score_bend_integration_20261026/README.md)。** App Code39；Logic 22453、CLS 11439、BSRAM 55、DSP 26.5。剩余 81 CLS，保留35后可用 46。50MHz 完整布通，setup/hold 违例0/0，原始 WNS +0.265/+0.149ns。默认入口已更新，未安装或烧录。以下旧版本记录保留。

**2026-10-26 CLS 优先复核：[第三步实测、失败记录与回退](reports/control_pack_20261026/README.md)。** 第二步增加77 CLS的显示方案已撤回，实验与命名位流保留。第三步已完成多组结构与物理实现对照，尚未找到满足净减CLS与时序要求的候选，均未接入。当前默认保持第一轮 HC-05 版本：Logic 22447、CLS 11387、BSRAM 53、DSP 26.5；剩余133 CLS，保留35后预算98。第三步新增收益为0。未烧录。以下资源和位流指纹为历史记录。

**2026-10-26 演奏体验版：[Code35 / 1.34-performance APK](android_app/dist/FPGA-Music-Performance-Code35.apk) · [常用操作](PERFORMANCE_QUICKSTART.md) · [逐项结果、资源与回退](reports/performance_experience_20261026/REPORT.md)。** 新增常用演奏入口与手机本地三效果场景，保留现有外观素材和演奏功能。硬件保持已验证三效果基线，剩余50 CLS、其中35保留；本轮震音、D/E候选均未满足资源准入，B2依赖未满足。编译、数字音频与协议测试范围见报告；手机、蓝牙和听音待实机验收。未安装或烧录。以下为历史记录。

**2026-10-23 App 色环版：[Code25 /1.24-hue APK](android_app/dist/FPGA-Music-Hue33-Code25.apk) · [界面效果与说明](android_app/HUE33.md)。** “显示”分区顶部加入青蓝紫红色环、深色频谱与渐变幅度条；本次只改手机端，无新增 FPGA 资源。核心测试、排版检查和签名构建通过，手机实机联调待验。

**2026-10-23 33 档音量色环：[已验证位流、完整 PASS 与资源对比](deliveries/LED_HUE33_20261023/README.md) · [显示说明](SCOPE_DISPLAY.md)。** 每 64 PCM 计数一级，青→蓝→紫→品红→红；±1 青色、零信号灰色。五项仿真逐个通过（含完整顶层），无新增 BSRAM/DSP；50MHz、WNS +0.198ns。整机 Logic21503 /CLS11202 /BSRAM47 /DSP26.5；相对本任务前 8 档为 -87 Logic、+122 CLS。默认位流已同步，尚未烧录；后续规划预留差113 Logic /47 CLS，详见报告。以下为历史记录。

[仓库首页](../README.md) · [文档索引](../docs/README.md) · [快速上手](../docs/QUICK_START.md) · [完整接线与验收](PIN_FUNCTION_REQUIREMENTS.md)

**2026-10-22 弱信号修正版：[新版位流与验证](deliveries/LED_SCOPE_WEAK_FIX_20261022/README.md) · [FSR 量程与颜色标定](SCOPE_DISPLAY.md)。** 基础显示倍率提高八倍，FSR X8/X16/X32；非零信号为饱和蓝至红，静音白色。整机 Logic 21394、CLS 11087、BSRAM 47、DSP 26.5，50MHz 时序通过；后续规划的 Logic 预留少4个，报告已标明。尚未烧录。以下数字为历史版本的数据。

**2026-10-22 HC-05连接排查：[Code24独立APK](android_app/dist/FPGA-Music-LinkDiag-Code24.apk) · [安装版本与超时定位](HC05_CONNECTION.md)。** 设备页显示实际安装版本，超时显示具体命令与收发情况。旧四档回声冻结包内的Code22 APK有回复识别缺陷，不再作为安装入口。

**E 预算修订：[100 CLS 范围复核](E_SCOPE.md)。** 保留 B2、D 与安全垫；撤销三源七族全覆盖承诺，按 E0 → E4 → E2 → E3 → E1 逐项测量准入。

**2026-10-22 四档回声优先版：[演奏参数与验证](PERFORMANCE_PARAMS.md) · [当前App Code24 /1.23-linkdiag](android_app/dist/FPGA-Music-Unified.apk)。** 保留84 /168 /336 /504 ms回声，长档仅湿声降采样；移调 /A4缩为红外与手势共享，触摸键保持原音高。合唱速率维持旧固定值。通过版本PnR为Logic21088、CLS11060、BSRAM44、DSP26.5、Register10239，Fmax50.096 MHz；满足C的400 /100预算，保留D、B2、E100和安全垫。完整107项RTL回归与实机对录状态见该文档。

**2026-10-21 B1半音阶：[接线 / 音高表与验证](CHROMATIC_KEYS.md) · [App v1.16-chromatic / Code17](android_app/dist/FPGA-Music-Unified.apk)。** 按用户确认的扫描顺序，K1～K12默认C4～B4，K13～K16暂作C5/D5/E5/F5；手机琴键和七键图形映射同步。MAP仍只支持前七个扫描键，曲谱 / LED仍为七通道。PnR为Logic20967、CLS11053、BSRAM44、DSP26.5，Fmax52.026MHz；未烧录或做实机测频。

**2026-10-21 App 阶段 A：[v1.15-sidebar / Code16 安装包](android_app/dist/FPGA-Music-Unified.apk)。** 新增六分区侧边栏、触摸 / 红外 / 手势七分组、草稿与设备确认三态、板上事件录制条件说明及一键切换；撤掉停用的 HC-05 PCM 录音与回传入口。操作和测试范围见 [SIDEBAR.md](android_app/SIDEBAR.md)，后续资源与命令号预算问题见 [方案审查](SIDEBAR_REVIEW.md)。本次不改 RTL 或协议，手机与板上联动待实机验收。

**当前工程：[PCM5102_UNIFIED.gprj](PCM5102_UNIFIED.gprj)，顶层 `top_unified`。** 2026-10-21 钢琴踏板版新增 `HOLD,2` 与 `POLY,1/2/4/8/16`，保留正常演奏、曲谱、LED 遥控及事件录制重放；按用户授权关闭 FPGA Flash PCM 原音录制，以释放演奏资源。手机本地录制仍保留，板上事件录制需先设 `HOLD,0/1`、`POLY,16`。配套 [踏板版 APK](android_app/dist/FPGA-Music-Pedal.apk)，当前验证见[验证记录](VERIFICATION.md)。[2026-10-20 交付包](deliveries/UNIFIED_RECORDING_20261020/)是包含 PCM 录制的历史版本，不含新踏板功能；[统一录制说明](android_app/UNIFIED_RECORDING.md)保留其操作说明。合并前工程及专用脚本已[归档](archive/legacy_projects/README.md)。

最新 [HC-05 资源优化](HC05_RESOURCE_OPTIMIZATION.md)：默认综合移除备用 USB 录音电路，现有 53 个命令共享译码，曲谱计时缩位；同条件综合 Logic 减少 7.91%，独立位流 `PCM5102_HC05_ONLY.fs` 完成 50MHz 布局布线，尚未烧录。

新增 [App v1.10 手机 LED 联动与配套主工程位流](LED_REMOTE.md)：四页直接切换、请求/实际显示状态和频谱/幅度预览。需要同时更新 APK 与位流；手机和面板实物联调待验。

历史[App v1.11 / Code12](android_app/dist/FPGA-Score-hc05-only.apk)已采用**手机与FPGA仅通过HC-05通信**的方式。USB高速数字录音[保留备用，暂不启用](AUDIO_RECORDING.md)，无需新增USB模块、RTS或OTG，也不把完整PCM改走现有9600bps链路。曲库、LED联动、演奏控制及8/16键等功能保留；板上事件录制回放的开发状态单列于[说明](RECORD_PLAYBACK.md)。当前位流与验证见[验证记录](VERIFICATION.md)。

支持[最终混音波形、参考李萨如、混音延时XY、实时FFT频谱与三组音源幅度条](AUDIO_VISUAL.md)。S2长按约1秒按“总览/曲谱→波形→XY→频谱”循环；XY页短按轮换八字、多瓣、圆、椭圆、直线、实际混音，其他页短按重启曲谱。`XY,r,p`可通过蓝牙独立设置频率比和相位；REF与AUD标签区分数学参考与真实混音。上电显示总览，曲谱播放时自动显示七轨指引。构建与实测范围见[验证记录](VERIFICATION.md)。

2026-10-16：新增 [手机运行时ADSR编辑](ADSR_RUNTIME.md)，支持触摸与红外/手势独立配置、四滑块及曲线控制点拖动。

2026-10-16：保留 LED 全部引脚，接入八路红外对管；红外与 APDS 手势共享 32 复音 TDM 引擎。
七键触摸、FSR、手机曲谱、64×64 指引、S1/S2 曲谱控制和物理弦吉他保留。
新增 `TEST32` 现场频谱验证命令和 App 按钮。完整接线、基础/拓展要求完成情况、
核心评分口径和现场验证步骤见 [引脚与赛题验收表](PIN_FUNCTION_REQUIREMENTS.md)。
构建、时序与测试结果见 [验证记录](VERIFICATION.md)。

2026-10-15 修正：赛题要求输出由 FPGA 根据实时演奏指令逐音、逐样本生成，基础复音数 ≥4，支持实时变调、ADSR 与混音，禁止预录 PCM 播放、预置推流和整段录音触发。
此前将《结算画面》转成 PCM 下载播放的方案违反该要求，已撤回。**旧位流 UserCode=0x00009C48 不用于比赛或本轮验收**；当前曲谱与屏幕版本的位流标识、时序、测试及 SHA256 统一见 [验证记录](VERIFICATION.md)。

当前使用 `PCM5102_UNIFIED.gprj`，器件 `GW5A-LV25MG121NC1/I0`，顶层 `top_unified`，内部实例化 `src/top.v`。
PCM5102 可以保留，它只把 FPGA 实时合成的 I²S 采样转换为模拟声音；PAM8403 负责功率放大。

```text
TTP229 8键直连 / 16键串行 → 同步/防抖 → 16路独立 DDS / ADSR 上下文 → 实时混音
FSR402 → 22k/4.7k 分压 → GW5A 片内 ADC → 压力音量/压音
滑杆中点 → ADS1115 AIN1 → I²C（与 APDS 共用）→ 全局音量/音高/颤音/湿度
实时混音 → 原声/回声/合唱 → 平滑总音量 → I²S → PCM5102 → PAM8403
HC-05 → 键位配置 / 音符曲谱暂存 / 演奏事件日志
红外8路 + APDS-9960 → 32复音TDM / 八音色 / 颤音 ───────────────→ 实时混音
HC-05 GUITAR → Karplus–Strong 单弦拨弦 ───────────→ 实时混音
备用、当前停用：最终实时采样副本 → FIFO/CRC/2Mbps UART → USB/OTG → 手机WAV
```

16 键各占独立声部，可同时发声；正弦 ROM 只存一个周期的数学波形，不存歌曲录音。
手势和吉他同样由 FPGA 实时计算采样，不播放预录音频。
生产默认 `ENABLE_DEMO_SCORE=0`，上电和普通 `PLAY` 不自动发声。下载谱用于 HUB75E 七轨下落指引；App自v1.3起可用 `AUDITION` 显式启动实时合成试听。
蓝牙协议和日志见 [蓝牙曲谱与演奏记录](BLUETOOTH_MEDIA.md)，接线与改键见 [HC-05 说明](HC05_KEYMAP.md)。
安卓手机继续使用现有 HC-05：[安装曲谱助手与下载步骤](android_app/README.md)。支持内置示例、CSV、标准 MIDI0/1；手机文件经蓝牙下载到 FPGA RAM，首版没有互联网曲库。

## 现场操作

以下触摸接线与K8操作针对默认8键模式。16键必须先按[迁移说明](REFERENCE_MIGRATION.md)拆除OUT直连和SCL固定连接；K1～K16均演奏，K8不再切压力用途。锁存、滑杆、PANIC及七键曲谱兼容范围也见该页。

默认 TTP229 使用 **8 键直连模式**（16 键请按 [迁移说明](REFERENCE_MIGRATION.md) 改接和在 App 切换）：TP2 开路，TP3、TP4 短接启用多键，改变跳线后重新上电。
模块供电 3.3V 并与 FPGA、音频模块共地；上电前 600ms 不触摸，等待校准。
默认 8 键读取 OUT1～OUT8，SDO 可不接。16 键另接 F7/SDO，切勿把 8 键固定 SCL 接法直接用于串行模式。**SCL 不可悬空**；当前用户实测 SCL 接 GND 后恢复正常，保持此接法且不接 F6。
也可改接模块 3.3V 或 `touch_scl` 的 F6 固定高输出，三种接法只能选一种；F6 不得同时接地。

- K1～K7 默认弹奏 Do、Re、Mi、Fa、Sol、La、Si（C4～B4）；按住持续发声，松开后约 10ms 渐弱到零，各键独立。
- K8 每次确认按下在压力音量/音高模式之间切换，长按只切换一次；K8 不发音，上电默认音量模式。
- 音量模式轻压约 100%、重压约 25%；音高模式轻压原音高、重压降低一个八度。FSR402共同控制当前触摸声部，本身不触发音符。
- 已下载有效曲谱时，S1 开始/停止指引，S2在XY页之外短按松开后从头重启。开始后预备1500ms，音符下落到判定线时按对应键；无有效谱时短按不启动曲谱，蓝牙 `PLAY` 返回 `ERR,STATE`。S2长按约1秒循环切换曲谱、波形、XY、频谱；XY页短按只选择图形。
- HUB75E 显示七轨、青色下落音符、橙色到时目标和底部触摸反馈，支持和弦与休止；首版没有计分和长音尾条。屏幕接线与显示范围见 [RHYTHM_GUIDE.md](RHYTHM_GUIDE.md)。
- APDS-9960 四方向手势发音；默认 C4～F4，可用 App 切换 G4～C5。红外与手势共享 32 声部 TDM 引擎，音色/颤音设置同时作用于两者；`BANK` 只改变手势音符组。触摸使用独立的16份DDS/ADSR上下文。
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
| `touch_scl` | F6 / J3第37脚 | 8键模式固定高，可不接；16键模式输出串行时钟 |
| `touch_sdo` | F7 / J3第38脚 | 16键串行数据输入；8键模式可不接 |
| `hc05_rx` | F2 / J3 第16脚 | HC-05 TXD |
| `hc05_tx` | F1 / J3 第15脚 | HC-05 RXD |
| `audio_rec_tx` | J7 / J3 第27脚 | 高速USB串口模块RXD，2Mbps音频上行 |
| `audio_rec_cts_n` | L8 / J3 第29脚 | 高速模块RTS低有效输出，默认上拉禁止发送 |
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
滑杆不再占用这对引脚：其中点直连 ADS1115 AIN1（3.3V 供电、地址 0x48），模块 SCL/SDA 接 **K10/L10（J3 第31/32脚）** 这组独立 I²C，
与 APDS-9960 的 H4/G4（J3 第23/24脚）完全分开，两路采样互相独立、可同时工作；接线与 `CAL` 标定见 [迁移说明](REFERENCE_MIGRATION.md)。

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
| `ADSR_RELEASE_SAMPLES` | 4883 | 旧 `ENABLE_DEMO_SCORE=1` 演示音轨释放约 100ms；`AUDITION` 使用触摸包络 |
| `TOUCH_STARTUP_US` | 600000 | 上电等待 600ms |
| `TOUCH_DEBOUNCE_MS` | 2 | K1～K7 按下/松开确认 |
| `TOUCH_MODE_DEBOUNCE_MS` | 20 | K8 模式切换确认 |
| `HC05_BAUD` | 9600 | 蓝牙数据模式 UART 波特率 |
| `GUIDE_LEAD_MS` | 1500 | 音符提前下落与首音预备时间 |

单键按住时可实时变调；FSR或滑杆音高模式统一作用于全部触摸声部，前七键另有独立手机滑音。
触摸与红外/手势支持两套独立的 [运行时 ADSR](ADSR_RUNTIME.md)，新参数在下次发音生效，触摸配置覆盖全部16键；前七路触摸还支持 [逐声部滑音](VOICE_PITCH.md)，与 FSR 全局音高控制叠加。上表列出触摸包络的编译默认值。
App v1.3 新增“自动演奏 · 已下载曲谱”（`AUDITION`）：显式启动后，七路触摸 DDS/ADSR 根据已下载音符与时长实时合成，无需人按键，和弦/休止均保留，结束自动停止。普通 PLAY 与 S1/S2 曲谱操作继续用于无声指引；上电不自动发声。试听与触摸共享声部及其表情设置，不增加计分复音数，不能作为赛题现场交互演奏验收。旧 `ENABLE_DEMO_SCORE=1` 的开发演示音轨仍保留。使用步骤见 [App 说明](android_app/README.md)。

移除违规播放路径不等于全部赛题要求已经验收。仍需板上验证至少四路独立演奏、实际输入到出声延迟、实时变调、包络表现、ADC 标定和屏幕指引。
FPGA 输入后的仿真延迟不包含 TTP229 自身扫描、DAC 和功放模拟延迟，不能直接代表整机延迟。

## 构建与验证

在本工程目录 PowerShell 运行：

```powershell
./tools/run_sim.ps1
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build.tcl
```

位流路径为 `impl/pnr/PCM5102_UNIFIED.fs`，已同步四档回声优先版。资源、时序、指纹与仍待完成的全量回归 /实物对录见 [PERFORMANCE_PARAMS.md](PERFORMANCE_PARAMS.md)；可核对 [本次交付包](deliveries/ECHO_PRIORITY_20261022/README.md)。`deliveries/UNIFIED_RECORDING_20261020/PCM5102_UNIFIED.fs` 为不含踏板的历史PCM录制版；默认烧录脚本使用标准输出路径，烧录前核对当前位流SHA256。
Gowin IDE 已打开旧工程时，关闭后打开 `PCM5102_UNIFIED.gprj`；编译不会自动更新板上 SRAM。
用户连接开发板后可用 Programmer 的 **SRAM Program**，或 `./tools/program_sram.ps1` 下载；SRAM 断电丢失，本轮不自动写 Flash。

共享输入模块为 `../pmod_hub75e/src/ttp229_gpio_input.v`，移动工程时保留相对目录。
工程持久配置与 `build.tcl` 均设置 CPU/SSPI 为普通 IO、保留 JTAG；遇到 E2 复用错误时，在 Configuration 的 Dual-Purpose Pin 中核对 CPU=true、SSPI=true、JTAG=false 后重新运行。

此前自动曲谱、录音试听和旧位流编号仅为历史记录，不适合作为本轮实时演奏验收证据。
旧工程 `../pcm5102_dds_step1/`、`debug/` 和压缩包保留历史快照；后续生产音频修改统一使用此工程。
