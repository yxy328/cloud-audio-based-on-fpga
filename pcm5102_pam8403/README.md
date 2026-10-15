# Tang Primer 25K：TTP229 七键弹奏 / K8 模式切换 + FSR402 + PCM5102 / PAM8403

一直使用的原 Gowin 工程：`PCM5102_PAM8403.gprj`，器件 `GW5A-LV25MG121NC1/I0`，顶层 `top`。
2026-10-14 已在同一工程接入 **HC-05 手机改键**：`PING`、`MAP?`、`MAP,1,67`、`MAP_RESET`。
七键支持 MIDI 60～72，K8 保留压力模式切换；设置在空闲时生效，重新下载/断电恢复默认。
手机发送须追加 LF/CR/CRLF，接线与文件清单见 [HC-05 改键说明](HC05_KEYMAP.md)。

2026-10-11 同一个生产顶层使用 TTP229 OUT1～OUT7 直连弹奏，OUT8 切换压力音量/音高模式，同时保留《小星星》播放。
触摸输入直接引用 `../pmod_hub75e/src/ttp229_gpio_input.v`，两个工程共用同一份同步、防抖和启动代码。
`top.v` 使用两组四声部核心生成七个触摸音（第八声部关闭），另一组四声部核心生成歌曲，最后饱和混音后送入 I2S。
四个声部在 FPGA 中逐样本计算，分别为一条旋律和三条伴奏。完整旋律 42 个音，48 拍，播放约 19.59 秒后自动停止。

2026-10-10 当前 FSR402 方案为 **一路信号转换模块 AO → 分压 → GW5A-25 片内 ADC → FPGA 力度动态**。
无需外接 ADC 芯片，MCP3008 驱动和四根 SPI 接线已从主工程移除。
本说明书模块 AO 随压力增大而升高；默认音量模式轻压约 100%、重压约 25%，K8 切到音高模式后轻压原音高、重压低一个八度。歌曲独立。
**片内 ADC 仅接受 0～1V，模块 AO 必须先分压。** 接线、参数和 FSR402 实物标定见 [FSR402 接入说明](FSR402.md)。

下载文件仍是本工程的 **`impl/pnr/PCM5102_PAM8403.fs`**；HC-05 改键版 **UserCode=`0x0000A575`**，50MHz 时序通过，Fmax=57.409MHz；完整构建结果见 [验证记录](VERIFICATION.md)。此前音符键响应修订版 UserCode=`0x0000C6A5`，Fmax=56.344MHz，为改键前的历史构建。
2026-10-12 已验证默认参数下的 1～7 键：本场景 OUT 到首次非零 I²S 样本最大 1.884151ms，松开到确认严格静音最大 11.950392ms。8 键继续切换压力音量/音高。
2026-10-11 已消除 ADSR 的两条 EX3791 位宽警告；106459 个样本及边界测试通过，修改前后增益/状态输出逐字节一致。位流已重新生成，最新 SHA256 见验证记录。
此前 `0x0000B215`、`0x0000C09D` 为外接 ADC 的历史版本；`0x00008EDB` 为加入力度前的历史版本。
完整验证范围见 [验证记录](VERIFICATION.md)。
`0x00002064` 是此前的固定和弦历史版，不能播放本次旋律。
后续音频修改统一在此工程；`../pcm5102_dds_step1/`、`debug/` 和旧压缩包保留历史版本。
本次由用户自行下载。音频接线沿用原工程；新增触摸接线见下表，OUT1 已迁到 K4。

电脑参考音 [完整《小星星》试听](sim/build/music_preview.wav) 直接使用生产曲谱控制器，
渲染前逐项核对其音乐和 ADSR 参数与 `top.v` 相同；详细范围见 [试听说明](MUSIC_PREVIEW.md)。
此前约 6 秒的 14 音试听现扩充为完整曲谱，并把每句最后一个音设为两拍。

## 1. 下载后怎么操作

TTP229 使用 **8 键直连模式**：TP2 开路，TP3、TP4 短接启用多键，改变跳线后重新上电。
按键模块供电 3.3V，和 FPGA、音频模块共地；上电前 600ms 不触摸，等待模块校准。
音频工程固定读取 OUT1～OUT8，SDO 无需连接，**SCL 必须保持固定电平，不能悬空**。
当前用户已实测 **SCL 接 GND 后恢复正常**，可保持这一接法，此时不连接 F6。
也可将 SCL 接模块 3.3V，或接本工程 `touch_scl` 的 F6 固定高输出；三种接法选一种。
S2 保持歌曲重播功能。F6 是高电平输出，不得同时接 GND。

K1～K7 分别弹奏 **Do、Re、Mi、Fa、Sol、La、Si（C4～B4）**。
**K8 每按下并松开一次，在压力控制音量/音高之间切换；不再弹奏高音 Do。** 长按只切换一次，上电默认音量模式。
校准期间按住 K8 时，须松开后再按才能切换，避免启动时误切换。
按住音符键持续发声；1～7 键按下/松开使用两个 1ms 采样确认，松开后约 10ms 渐弱到零。每键独立，可同时弹奏七音和弦。
8 键仍使用 20 个 1ms 采样确认按下和松开，避免短触碰误切换模式。
歌曲播放和触摸弹奏可同时发声；停止歌曲不会停止正在按住的触摸音。
FSR402 共同控制七个触摸音，不触发音符；按住音符键后可连续改变压力。

| 当前模式 | 压力控制 | 另一项 |
| --- | --- | --- |
| 音量（上电默认） | 轻压约 100%，重压约 25% | 保持当前映射音高（默认 C4～B4） |
| 音高（按一次 K8） | 轻压原音高，重压降低一个八度；例如 C4→C3 | 音量使用原触摸增益，仍保留 ADSR |

切换时音量和音高均平滑回到对应模式的目标值，DDS 相位持续运行。
`FSR_GAIN_REVERSE=1` 控制音量方向；音高模式始终重压降低音高。`FSR_ADC_INVERT=0` 适配此说明书的 AO 方向。

1. 在 Programmer 重新选择本工程的 `impl/pnr/PCM5102_PAM8403.fs`，执行 **SRAM Program**。
   若 Gowin 已打开旧文件列表，请关闭并重新打开同一个 `PCM5102_PAM8403.gprj`；新列表应包含新增的 `uart_8n1.v`、`hc05_keymap.v`、`midi_note_lut.v`，以及 `gowin_fsr_adc.v`、`fsr_dynamics.v`、`fsr_mode_select.v`、`fsr_pitch_scaler.v`、`twinkle_sequencer.v` 和共享的 `ttp229_gpio_input.v`。
2. 下载完成后保持静音。**按下并松开一次 S1：从头演奏《小星星》，无需一直按住。**
3. 播放时再按一次 S1：停止演奏，约 100ms 渐弱到零。松开 S1 本身不会停止。
4. **按一下 S2：从头重播**，播放中和停止时都有效。长按 S1/S2 只触发一次。
5. 全曲结束后自动静音，不循环；再按 S1 或 S2 可重新播放。

应听到：

```text
C C G G A A G— | F F E E D D C—
G G F F E E D— | G G F F E E D—
C C G G A A G— | F F E E D D C—
```

每个字母是一个旋律音，`—` 表示句尾延长为两拍；另有三个低音伴奏声部。
旋律音位于 C5～A5，音色为数学正弦；每个普通音起音约 300ms，间隔约 100ms。
伴奏先起音约 40ms，然后旋律进入。整曲含约 350ms 的尾音等待。

S1/S2 使用两级同步和约 1ms 稳定确认；触摸沿用共享输入模块，但音符键为 2ms 确认、模式键为 20ms 确认。
七个触摸声部和四个歌曲声部各自保留相位、包络和乘法器，
默认每路峰值为满幅的 1/16，维持约 60%；左右声道输出相同混音。
先调低功放电位器，再逐步调高。仅编译不会更新板上的 SRAM 程序，需要下载新的位流。

### 当前参数

参数位于 `src/top.v` 顶部，修改后重新编译和下载：

| 参数 | 默认值 | 时间 / 含义 |
| --- | --- | --- |
| `ADSR_ATTACK_SAMPLES` | 98 | 起音 2.00704ms |
| `ADSR_DECAY_SAMPLES` | 3906 | 衰减 79.99488ms |
| `ADSR_SUSTAIN_LEVEL` | 39321 | 维持约 60% |
| `ADSR_RELEASE_SAMPLES` | 4883 | 歌曲释放 100.00384ms |
| `TOUCH_ADSR_RELEASE_SAMPLES` | 488 | 音符键释放 9.99424ms |
| `TOUCH_STARTUP_US` | 600000 | 触摸上电等待 600ms |
| `TOUCH_DEBOUNCE_MS` | 2 | 1～7 键独立按下/松开确认两个 1ms 采样 |
| `TOUCH_MODE_DEBOUNCE_MS` | 20 | 8 键按下/松开确认 20 个 1ms 采样 |
| `TOUCH_ACTIVE_LOW` | 0 | OUT1～OUT8 高有效，与原屏幕工程默认一致 |
| `SONG_BEAT_SAMPLES` | 19531 | 一拍 399.99488ms |
| `SONG_GAP_SAMPLES` | 4883 | 两次旋律起音之间的释放间隔 |
| `SONG_INTRO_SAMPLES` | 1953 | 伴奏先奏 39.99744ms |
| `SONG_TAIL_SAMPLES` | 17100 | 曲末等待 350.208ms |

每句最后一个音占两拍，音符起音时间为 `拍数×SONG_BEAT_SAMPLES−SONG_GAP_SAMPLES`。
音符门控与所有 DDS/ADSR/混音由同一个 50MHz 时钟驱动，音乐计时仅在音频帧使能时推进。
十一条发声路径共用起音、衰减和维持参数，触摸与歌曲的释放时长分开配置，各路包络状态独立。修改为低有效时，应同时把 CST 的触摸下拉改为上拉。

此前和弦试听及独立释放说明保存在 [第三步历史说明](STEP3.md)。
`polyphony_reference.wav`、`polyphony_rtl.png` 和旧 ADSR 图属于历史试听，不代表当前曲谱控制。

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
| TTP229 SCL | GND | 当前用户实测有效的直连接法，不接 F6 |
| `touch_scl`（可选） | F6 | 固定高输出；改用此接法时先拆除 SCL 到 GND 的连接 |
| GND | 底板 GND | FPGA、DAC、功放电源和功放输入共地 |

沿用原音频工程的三根数字音频线。**TTP229 OUT1 从屏幕工程的 K1/J3 第 2 脚改到 K4/J3 第 5 脚**，避免与 LRCK 冲突；OUT2～OUT8 沿用原位置。

| 触摸输出 | 顶层端口 | FPGA 球号 | J3 物理脚号 | 音符 |
| --- | --- | --- | ---: | --- |
| OUT1 / K1 | `touch_out[0]` | K4 | 5 | C4 / Do |
| OUT2 / K2 | `touch_out[1]` | L2 | 4 | D4 / Re |
| OUT3 / K3 | `touch_out[2]` | J4 | 6 | E4 / Mi |
| OUT4 / K4 | `touch_out[3]` | G1 | 7 | F4 / Fa |
| OUT5 / K5 | `touch_out[4]` | G2 | 8 | G4 / Sol |
| OUT6 / K6 | `touch_out[5]` | L3 | 9 | A4 / La |
| OUT7 / K7 | `touch_out[6]` | L4 | 10 | B4 / Si |
| OUT8 / K8 | `touch_out[7]` | J2 | 21 | 压力音量 / 音高模式切换 |

八路均为输入，默认弱下拉使未接触摸模块时保持静音。此约束用于 8 键 OUT 直出，不能用来接 16 键电极模式。
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

`S1/S2 → 硬件同步与确认 → 硬件曲谱计时/音符查表 → 四组门控/音高 → DDS + ADSR + 包络乘法 → 混音/饱和 → I2S`

`TTP229 OUT1～7 → GPIO 同步/600ms 等待/2ms 确认 → 七组独立 DDS + ADSR（10ms 释放） → 与歌曲混音 → 同一个 I2S`

`TTP229 OUT8 → GPIO 同步/600ms 等待/20ms 确认 → 压力音量/音高模式切换`

`FSR402 / 一路转换模块 AO → 22k/4.7k 分压 → 片内 ADC / 1kHz 请求 → 校准 → K8 模式选择 → 音量增益或 DDS 音高比例平滑`

`twinkle_sequencer.v` 存储音高和伴奏的相位步进，按 42 个音符事件控制四个声部。
全部 PCM 样本由 FPGA 每帧实时计算；ROM 中只有一个周期的数学正弦，不存歌曲 PCM 或录音。
触摸路径已提供现场弹奏入口；歌曲路径仍用于试听。七个音符键使用固定独立声部，超过四键也不会抢音；第八键选择压力模式。
此前 20ms 确认加 100ms 触摸尾音会造成发声偏慢、松键拖音，本版分别缩短至 2ms 和 10ms。
FPGA 的 OUT 到 I²S 响应与实际触摸到喇叭响应分开记录。TTP229-BSF 的 8 键工作响应典型值为 16ms，
休眠唤醒还取决于扫描设置；FPGA 参数无法消除这一前端等待，总延迟仍需上板测量。
见 [TTP229-BSF 原厂数据手册第 5 页](https://www.tontek.com.tw/uploads/product/97/TTP229-BSF_V1.1_EN.pdf)。

`dds_voice.v` 使用运行时输入 `phase_inc[31:0]`，变调保持相位连续：

`phase_inc = round(frequency_hz * 2^32 / 48828.125)`

旋律使用 C5 / D5 / E5 / F5 / G5 / A5；第 1 声部为旋律，第 2～4 声部为伴奏。
`poly_synth` 的 128 位音高总线从低到高排列这四路，门控位 0 对应旋律。
旋律间隔时门控为 `1110`，旋律起音时为 `1111`，停止和曲尾为 `0000`。
停止时保持当前音高，让尾音在原音高上释放；重播从曲首开始，振荡器相位连续。

采样率 **48,828.125Hz**，每帧 20.48µs；BCK **3.125MHz**。所有内部逻辑使用 50MHz 主时钟。
`adsr_env.v` 在每段开始时用 16 个主时钟计算斜率，之后逐样本作整数步进和余数累加。
四路包络乘法后先符号扩展至 24 位，进行平衡混音及 16 位饱和，不随声部数量改变总增益。
三组四声部混音再经过一次饱和混音，增加一帧 20.48µs 管线延迟。
默认每声部峰值 1/16，即使十一声部同时起音也有数值余量，不按同时按键数量改变增益。

I2S 每声道 32 个 BCK，第 0 位为延迟，第 1～16 位为 MSB 到 LSB，其余补零。
左右声道一致；DIN 和 LRCK 在 BCK 下降沿更新。没有外部 MCLK 输出。

## 4. 文件与工具

```text
pcm5102_pam8403/
  PCM5102_PAM8403.gprj
  src/
    top.v
    button_filter.v
    twinkle_sequencer.v
    dds_voice.v
    sine_rom.v
    adsr_env.v
    envelope_gain.v
    synth_voice.v
    audio_mixer.v
    poly_synth.v
    gowin_fsr_adc.v
    fsr_dynamics.v
    fsr_mode_select.v
    fsr_pitch_scaler.v
    clk_div.v
    i2s_tx.v
    PCM5102_PAM8403.cst
    PCM5102_PAM8403.sdc
  sim/
    gowin_adc_model.v
    tb_gowin_fsr_adc.v
    tb_fsr_adc_capture.v
    tb_fsr_dynamics.v
    tb_fsr_modes.v
    tb_top_fsr_modes.v
    tb_top_fsr.v
    tb_fsr_pipeline.v
    tb_dds_voice.v
    tb_button_filter.v
    tb_adsr_env.v
    tb_envelope_gain.v
    tb_audio_mixer.v
    tb_poly_synth.v
    tb_twinkle_sequencer.v
    i2s_pcm_monitor.v
    tb_top_song.v
    tb_top_touch.v
    tb_music_preview.v
    tb_top.v
    tb_audio_units.v        原诊断模块的单元回归
  tools/
    run_sim.ps1
    render_music_preview.ps1
    pcm_to_wav.py
    check_pcm_equivalence.py
    build.tcl
    program_sram.ps1
  impl/
    PCM5102_PAM8403_process_config.json
    project_process_config.json
    pnr/PCM5102_PAM8403.fs
  VERIFICATION.md
  FSR402.md
```

共享依赖：`../pmod_hub75e/src/ttp229_gpio_input.v`；`run_sim.ps1` 同时复用
`../pmod_hub75e/sim/tb_ttp229_gpio_input.v`。移动工程时保留这两个目录的相对位置。

在此工程目录打开 PowerShell：

```powershell
# RTL 自检；日志保存在 sim/build/*.log。
./tools/run_sim.ps1

# 综合、布局布线，生成位流及原语网表。
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build.tcl

# 同一短场景 RTL 与布局布线网表功能仿真，未标注 SDF。
./tools/run_sim.ps1 -Tests tb_top -Quick
./tools/run_sim.ps1 -Netlist
python ./tools/check_pcm_equivalence.py

# 片内 ADC 行为模型及采样控制的 RTL 场景。
./tools/run_sim.ps1 -Tests tb_gowin_fsr_adc,tb_fsr_adc_capture,tb_fsr_pipeline

# K8 模式切换、两种压力映射、七音频率比例及外部 I2S 音高/音量。
./tools/run_sim.ps1 -Tests tb_fsr_dynamics,tb_fsr_modes,tb_top_fsr_modes

# 开发板连接并上电后，下载到 SRAM。
./tools/program_sram.ps1
```

仿真脚本可传入 `-IverilogDir` 和 `-GowinDir`。下载脚本默认 USB Debugger A、位置 385；
连接位置变化时用 `-CableLocation` 指定实际位置，也可以直接使用图形界面选择下载器。
脚本的操作为 SRAM Program，并自动回读 UserCode 与实际下载文件比较。
默认 RTL 测试覆盖当前参数的停止释放到零；网表默认使用短场景逐样本对照。
需要很慢的完整网表长场景时使用 `./tools/run_sim.ps1 -Netlist -FullNetlist`。
没有修改 Flash；重新上电需要再次下载本目录的新位流，否则可能恢复原来的固定音高程序。

## 5. E2 管脚复用配置

工程的两份完整配置 JSON 都保存 `CPU=true`、`SSPI=true`、`JTAG=false`，构建脚本也指定相同设置。
E2 已在本次布局布线中成功放置为 `clk`；H10、H11 也已按约束放置。

如果图形界面使用了其他配置，进入 Configuration 的 Dual-Purpose Pin：

- 勾选 **Use CPU as regular IO**。
- 勾选 **Use SSPI as regular IO**。
- 保留 JTAG 下载接口，**Use JTAG as regular IO 不勾选**。
- 点击 Apply / OK 后重新运行。

## 6. 验证范围

当前片内 ADC 版的采样控制、归一化、增益及音频使用 RTL 行为模型检查；
PnR 确认一套片内 ADC 和 J8/K8 的 ADC_IN 配置。Gowin 原语 ADC 模型为空，不能验证真实模拟采样。
FSR402 实物电压与演奏量程尚待上板校准。
K8 模式版通过两种压力映射的全部 1024 个码、七音全部 32768 个音高比例及 21240 帧外部 I²S 检查：
音量模式 C4 幅度约 1228→307；音高模式 C4→C3 幅度基本不变，切回后恢复重压小声。
启动已按住、短脉冲、长按、相位连续、七键与歌曲共 11 声部无削顶、歌曲 C5 独立、最终静音均通过。
响应修订后重跑 `tb_fsr_modes`，并新增 `tb_top_touch_response`：真实 50MHz/I²S、默认输入确认及 ADSR，
只把一次性启动等待缩短至 3ms。7491 个立体声帧通过七键按下/松开、短脉冲拒绝、独立释放/重按、
20ms 模式键短按拒绝/长按一次/短松开不重置、最终静音；歌曲 100ms 释放参数也核对未变。
本次未重跑此前的压力频谱长场景；完整范围与位流 SHA256 见验证记录。
下述 DCC1 / 8EDB 的网表及实板记录属于历史版本，详情见 [验证记录](VERIFICATION.md)。

新增测试覆盖 42 个音符的独立曲谱参考、按采样数计时、六个两拍句尾、重复音符间隔、
一遍播放后自动结束、停止、重播及复位。完整曲谱试听共享生产控制器，并检查输出范围和最终严格归零。
顶层外部 I2S 检查真实时钟周期、左右一致、开始/停止/重播及旋律与三路伴奏频率。
八键初版 `0x0000DCC1` 的布局布线网表对照仅完成启动及首次 S1 发声的 360 个样本，全部与 RTL 相同；
完整 65ms 场景有意提前停止，触摸发声通过 RTL 验证，具体范围见 [验证记录](VERIFICATION.md)。
SCL 修订版通过同一 RTL 短场景及新增固定高电平断言、综合和静态时序；没有重跑其网表动态仿真。
此前八音版本测试覆盖原模块的实际 600ms 启动、20ms 防抖及两种极性，并在真实 I2S 时钟下验证
全部八个音的频谱、独立松键、重触发、短脉冲拒绝、八音与歌曲并行以及最终静音。

电脑 WAV 属于仿真参考，经过固定增益归一化和 48kHz 重采样，不是 DAC/功放模拟录音。
本次由用户自行下载并试听；整机触发到模拟输出的总延迟仍须上板测量。

## 7. 当前源码与历史诊断

主工程使用 `dds_voice.v` 和 `sine_rom.v`，不再使用固定音高的 `nco_sine.v`、`volume_key.v`。
后两份文件、旧 `pitch_control.v` 和 `poly_demo_control.v` 保留给历史诊断或回归，未加入当前主工程综合文件列表。
`debug/audio_gao`、`debug/audio_autoplay` 使用各自保存的旧顶层或约束，保留原诊断用途。

之前的 `pcm5102_dds_step1` 是第一步的独立验证版本。后续开发与编译统一使用当前 `pcm5102_pam8403` 工程。

## 8. EX3937：新增模块没有进入 Gowin 当前窗口

本工程磁盘文件列表已启用 `src/twinkle_sequencer.v` 和 `../pmod_hub75e/src/ttp229_gpio_input.v`。若 Gowin 在更新前已经打开工程，
窗口仍可能保留旧的 `poly_demo_control.v` 列表，而读取到新的 `top.v`，导致 EX3937。
重新打开顶层代码标签页不能更新工程文件列表。

在 Gowin 选择 **文件 → 关闭工程**，再打开本目录同一个 `PCM5102_PAM8403.gprj`。
确认 Design 的 Verilog Files 中出现 `twinkle_sequencer.v` 和 `ttp229_gpio_input.v`，再 Run All。
模块层次应出现 `twinkle_sequencer(u_control)`、`ttp229_gpio_input(u_touch_input)` 和两组 `touch_voices`。

## 9. 9～16 误响：用户确认 SCL 接地后解决

用户已反馈全部选项焊盘开路、SCL 悬空；JTAG 读回确认板上为八键版 `0x0000DCC1`。
此前本说明写“SCL/SDO 无需连接”有误：手册第 14 页要求不用串口时 SCL 仍必须接 VDD 或 VSS。
用户随后反馈“我把 SCL 接地就可以了”，确认固定低电平接法已恢复正常；当前保持 SCL 接 GND、SDO 不接。
修订后的顶层增加 F6 固定高输出，可用 F6 保持 SCL；SDO 才是无需连接的信号。
选择已验证的 SCL 接地接法时不连接 F6；这项硬件接线修正不需要修改八路音符映射。
本项结果来自用户实板反馈，未新增波形或模拟输出测量。

FPGA 的 `touch_out[7:0]` 只表示八根输入线，不能设置 TTP229 的 8/16 键硬件选项。
芯片的 TP8～TP15 与 TPQ0～TPQ7 共用引脚，对应模块的 9～16 触摸区和 OUT1～OUT8。
在 16 键模式下，这些是触摸电极，八根排针不提供有效的直接按键输出；接入 GPIO 后，
电极信号变化可能被当作门控，表现为后八键也发声或声音相同。声音相同本身不能证明实际模式。
来源：[TTP229-BSF 原厂手册第 3、7、9 页](https://www.tontek.com.tw/uploads/product/97/TTP229-BSF_V1.1_EN.pdf)。

先确认板上连接芯片 TP2/KYSEL 的 16 键选择焊盘已断开，并给 TTP229 实际断电重新上电。
单纯重新下载 FPGA 不等于给触摸芯片断电。上电等待至少 600ms，期间不碰任何触摸区。
不同模块的焊盘编号可能不同，应核对 KYSEL/8-16 选项，不能把芯片 TP2 名称当作所有模块通用的丝印。
若确认已处于八键模式后仍出现该现象，需要检查 OUT1～OUT8 的实际电平、接线、供电和共地。
