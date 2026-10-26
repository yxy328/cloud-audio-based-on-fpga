# 快速上手

[首页](../README.md) · [文档索引](README.md)

## 1. 获取完整仓库

```powershell
git clone https://gitee.com/yxy0818/cloud-audio-based-on-fpga.git
cd cloud-audio-based-on-fpga
```

主目录唯一工程为 `pcm5102_pam8403/PCM5102_UNIFIED.gprj`，顶层 `top_unified`，器件 `GW5A-LV25MG121NC1/I0`。保留同级 `pmod_hub75e/`，工程直接引用其中的触摸输入模块。合并前的三个工程及专用脚本已[归档](../pcm5102_pam8403/archive/legacy_projects/README.md)。

## 2. 准备工具和接线

- FPGA：已有构建记录使用 Gowin V1.9.11.03 Education，需安装 IDE、Programmer 和开发板下载驱动。
- RTL 仿真：Icarus Verilog；脚本默认路径为 `C:/iverilog/bin`，可用 `-IverilogDir` 覆盖。
- 手机：Android 10+，安装[当前安装包](../pcm5102_pam8403/android_app/dist/FPGA-Music-Unified.apk)（内容为 **v1.38-scorebend / Code39** 的 2026-10-27 构建，SHA256 `4BF0C69A…`，与命名包 `dist/FPGA-Music-ScoreBend-Code39.apk` 字节相同）；回退可用 `dist/FPGA-Music-Performance-Code35.apk`（`C53E3A02…`）、三效果首轮 `dist/FPGA-Music-FX3-Code27.apk` 与固定十六键首轮 `dist/FPGA-Music-Touch16-Code26.apk`，更早的 `FPGA-Music-Hue33-Code25.apk`、`FPGA-Music-LinkDiag-Code24.apk`、`FPGA-Music-Chromatic.apk` 与 `FPGA-Music-Pedal.apk` 继续保留；Code28～Code34、Code36～Code38 外观包未入库。使用HC-05经典蓝牙SPP，无需USB或OTG。
- 修改 App 时再配置 JDK 和 Android SDK，步骤见 [App 文档](../pcm5102_pam8403/android_app/README.md)。现成 APK 可直接安装。

安装当前 **App v1.38-scorebend / Code39**，配套 `PCM5102_UNIFIED.fs`（当前默认位流为 2026-10-27 曲谱弯音构建，Logic 22453 / CLS 11439 / BSRAM 55 / DSP 26.5，SHA256 `EBAEAD00…`，本轮未记录 UserCode，尚未烧录验收），手机与FPGA只连接HC-05。触摸输入已固定为 TTP229 十六键串行：八键 GPIO 模式与 App 的 8/16 键切换入口在 2026-10-26 删除，接线、上电校准与 `SERIAL,0/1` 极性恢复见[固定十六键](../pcm5102_pam8403/TOUCH16.md)。接线先查[完整引脚表](../pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md)，其余改接与跳线查[8/16键迁移说明](../pcm5102_pam8403/REFERENCE_MIGRATION.md)（其中的键数切换部分已是历史说明）；16 键串行的默认音高、K13～K16 高音条与实机测频待办见[B1 半音阶说明](../pcm5102_pam8403/CHROMATIC_KEYS.md)；踏板 `HOLD,2`、复音上限 `POLY,n`、`PITCH` / `VIB` / `EFFECT2,tap`、`EFFECT,3,m,s,w` 三效果、`SONG_CHORD` 弯音比率与 `SONGBEND` 能力位、`KLIVE_ON` / `KLIVE_OFF`、`ANALOG,n` / `CAL` 与 `CTRL2?` 回报见[键位与协议](../pcm5102_pam8403/HC05_KEYMAP.md)，参数公式、四档回声范围与未完成的实物对录见[演奏参数与四档回声](../pcm5102_pam8403/PERFORMANCE_PARAMS.md)，三效果逐项行为见[合唱 / 延迟 / 混响](../pcm5102_pam8403/FX3.md)，曲谱弯音 CSV 与试听行为见[曲谱弯音](../pcm5102_pam8403/SCORE_BEND.md)，App 上的一步一操作见[常用演奏操作](../pcm5102_pam8403/PERFORMANCE_QUICKSTART.md)，连接失败时先按[HC-05 连接与超时定位](../pcm5102_pam8403/HC05_CONNECTION.md)核对设备页显示的已安装版本和新版超时提示，界面分区见[侧边栏说明](../pcm5102_pam8403/android_app/SIDEBAR.md)，手机色环频谱见[HUE33 说明](../pcm5102_pam8403/android_app/HUE33.md)，录制与重放见[录制说明](../pcm5102_pam8403/android_app/UNIFIED_RECORDING.md)。当前构建按用户授权关闭板上 Flash 原音 PCM 录制；板上录放使用 `TAKE` 通道（App「板上 TAKE」），旧 `REC_START` 事件日志在当前统一固件（`ENABLE_EVENT_TAKE=1`）中直接返回错误，因此不存在“回到八键再录制”的步骤，新增演奏参数也不写入事件快照。压力与滑杆是两条独立通道，`ANALOG,0` 只关闭滑杆而不影响压力，换上这份位流后旧 App 的“滑杆替换 FSR”界面文字已是旧说法。

| 使用方式 | 接线与操作 |
| --- | --- |
| 十六键串行（当前唯一输入方式） | 拆掉全部 OUT1～OUT8 直连线及 SCL 固定接地/接 3.3V 连接；SCL 接 F6/J3-37，SDO 接 F7/J3-38；模块按 16 键与多键焊盘配置后重新上电，约 0.6 秒校准期间保持松键，之后先松键再按。八键 GPIO 直连方式已于 2026-10-26 从生产中删除，`TOUCH,8` 返回 `ERR,RANGE`。极性不对时可在松键且曲谱、下载、音符、录制均空闲、延音关闭时用 `SERIAL,0/1` 修正，再等待校准，设置不跨 FPGA 断电。自 v1.16 起 K1～K12 默认 C4～B4 半音阶，K13～K16 暂作 C5/D5/E5/F5 |
| 压力 FSR | 片内 ADC：AO 经 22kΩ/4.7kΩ 衰减到 0～1V 接 J3-36（J8），J3-35（K8）接 GND；始终有效 |
| 滑杆 | 独立通道：两端接 3.3V/GND，中点直连 ADS1115 AIN1（不分压）；模块 SCL/SDA 接 **J3-31/32**（K10/L10），与 APDS 的 J3-23/24 分开；在 App 读取两端 ADC 后 `CAL` 标定 |

16键模式下OUT脚复用为电极，不能保留原直连。App不会改变模块硬件跳线；模块配置后重新上电，校准期间保持松键。详细电气说明见 [主工程说明](../pcm5102_pam8403/README.md) 与 [FSR文档](../pcm5102_pam8403/FSR402.md)。

## 3. 仿真与构建

在仓库根目录运行指定模块测试：

```powershell
& ./pcm5102_pam8403/tools/run_sim.ps1 -Tests tb_hc05_extensions,tb_analog_expression,tb_touch_tdm_synth
```

完整 RTL 回归省略 `-Tests`；默认列表已含本轮新增的 `tb_ads1115_bus`、`tb_top_dual_analog`、`tb_key_live_stream`、`tb_synth_shared_arith`、`tb_synth_shared_equivalence`，以及此前的 `tb_performance_params`、`tb_command_protocol`、`tb_vibrato_params`、`tb_tuning_params`、`tb_echo_params`、`tb_top_performance` 与显示用的 `tb_audio_scope`。`tb_fx_frame_budget` 与 `tb_engine_merge_baseline` 是核验用 bench，不进默认列表，按[效果器前置核验](../pcm5102_pam8403/FX_PREFLIGHT_20261024.md)给出的命令单独运行。2026-10-26～27 为三效果、固定十六键与曲谱弯音新增的 `tb_audio_fx_chain`、`tb_fx_protocol`、`tb_fx3_frame_take`、`tb_fx3_replay_decode`、`tb_fx3_reset`、`tb_fx_take_atomic_528`、`tb_top_touch16_recovery`、`tb_hc05_download_current`、`tb_score_legacy` 与 `tb_score_bend_` 六个 bench 同样不在默认列表内，按各轮交付报告里的 `-Tests` 命令单独运行，例如 `& ./pcm5102_pam8403/tools/run_sim.ps1 -Tests tb_fx_protocol,tb_fx3_replay_decode,tb_fx3_frame_take,tb_fx_take_atomic_528`。仅检查自动试听时可指定 `-Tests tb_top_audition`；这些顶层音频仿真耗时较长。软件核心测试入口为 `./pcm5102_pam8403/android_app/test-core.ps1`，其中包含纯 Java 的 `PerformanceParams` 换算、`LedHue` 色环对照，以及本轮新增的 `FxState`（可交叉读取 `sim/build/fx_protocol_replies.txt` 的 RTL 回复夹具）、`FxScene` / `FxSceneStore` 与 `ScoreBends` 检查。

用 Gowin IDE 打开主工程并执行完整综合、布局布线与位流生成，或使用命令行（将下面路径替换为本机安装路径）：

```powershell
$gowinShell = 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe'
& $gowinShell ./pcm5102_pam8403/tools/build.tcl
```

生成位流：`pcm5102_pam8403/impl/pnr/PCM5102_UNIFIED.fs`。当前默认构建（2026-10-27 曲谱弯音版，Logic 22453 / CLS 11439 / BSRAM 55 / DSP 26.5，SHA256 `EBAEAD00…`）的资源、时序与验证范围见 [验证记录](../pcm5102_pam8403/VERIFICATION.md) 顶部；`tools/build_unified.tcl` 的放置选项为 **`-place_option 2 -route_option 0 -route_maxfan 23`**，这是当前唯一同时满足“0 未布通、0 setup/hold 违例”的默认策略，换策略或改动 `src/` 后必须重测。注意 2026-10-26 第一轮 HC-05 回收的 -83 CLS 里含 `place_option 1` 的贡献，而 2026-10-27 默认构建回到 `place_option 2`——CLS 收益属于 RTL 与物理策略的联合结果，不能只按 RTL 记账。上一份入库的冻结交付为 [LED_HUE33_20261023](../pcm5102_pam8403/deliveries/LED_HUE33_20261023/README.md)（UserCode `0x00002176`，已被后续构建取代为默认输出），更早的 [LED_SCOPE_WEAK_FIX_20261022](../pcm5102_pam8403/deliveries/LED_SCOPE_WEAK_FIX_20261022/README.md)、同日的 [LED_SCOPE_20261022](../pcm5102_pam8403/deliveries/LED_SCOPE_20261022/README.md) 与[四档回声优先版](../pcm5102_pam8403/deliveries/ECHO_PRIORITY_20261022/README.md)保留为历史冻结位流，[统一版交付包](../pcm5102_pam8403/deliveries/UNIFIED_RECORDING_20261020/) 是包含 PCM 录制但不含踏板、半音阶与演奏参数的更早位流，各版本的功能与指纹不要混用。2026-10-26～27 各轮的命名位流与回退副本只留在本机 `reports/` 目录（`.fs` 与回退 `.apk` 不入库），入库的是报告正文、脚本与 JSON 证据。重新构建后的指纹可能不同。上一版的 RAM 与等价验证保留在 [RAM_GEOMETRY_VERIFICATION.md](../pcm5102_pam8403/RAM_GEOMETRY_VERIFICATION.md)。

当前默认构建就是统一工程（含四档回声与 LED 波形显示），无需再分别构建 HC-05、事件录制或 PCM 录音目标。默认脚本仅编译，不自动烧录。

## 4. 下载开发板

在 Programmer 中选择主工程新生成的 `.fs`，执行 **SRAM Program**。也可运行脚本，按本机路径和已连接的线缆位置修改参数：

```powershell
& ./pcm5102_pam8403/tools/program_sram.ps1 -ProgrammerDir 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin' -CableLocation 385
```

`385` 是现有开发机记录的线缆位置，其他电脑需按 Programmer 检测结果调整。脚本下载后读取 UserCode 并与位流头比较。SRAM 配置断电丢失；重新编译不会自动更新板上程序。

## 5. 首次演奏和曲谱试听

1. 上电即为串行十六键：约 0.6 秒校准后先松键再按，K1～K16 全部用于演奏，自 v1.16 起 K1～K12 依次 C4～B4 半音阶、K13～K16 暂作 C5/D5/E5/F5；K8 也是音符键，压力用途改由 App 选择，不再有八键/十六键切换。
2. 手机系统配对 HC-05，再在 App 中连接已配对设备。Android 12+ 需允许“附近的设备”。
3. 载入示例或导入 CSV/MIDI（需要逐事件弯音时用三列 CSV，第三列为 `bend_target_cents`），点击“校验键位并下载”，等待显示已提交；设备弯音范围不满足时先在进阶演奏参数里扩大范围，再重新下载。
4. 自己演奏使用 `PLAY` 或板上 S1：预备1.5秒后显示无声曲谱指引，按键实时发声。
5. 自动试听使用当前App“自动演奏 · 已下载曲谱”：`AUDITION` 使用前七个触摸声部合成声音，曲谱结束自动停止；`STOP` 提前停止曲谱，保留现场音符。带弯音目标的曲谱在事件边界选用目标并经现有音高扫描进入，首帧可能仍停在先前音高，滑入时间由进阶参数里的滑音速率决定；`PLAY` 仍是无声指引，不自动套用曲谱目标。
6. 空闲时LED显示总览，播放时显示曲谱。S2长按约1秒依次切换总览/曲谱、波形、XY、FFT；波形页显示 48 箱约 10.486ms 的完整混音，纵轴量程随 FSR 音量增益在建议 X8 /X16 /X32 间选择（超出时自动扩到 X4 /X2 /X1），非零波形按真实峰值走 33 档青→蓝→紫→品红→红色环（每 64 个 PCM 计数一档，一帧内同色）、静音为低亮白，底部 PK 用固定满幅刻度，读数含义见 [LED 波形量程与色环](../pcm5102_pam8403/SCOPE_DISPLAY.md)；XY页短按选图，其他页短按重启曲谱。
7. 在App应用音效、总音量或延音后查看设备读回和LED状态；需要关闭锁存并清除声音/尾音时使用`PANIC`，随后松开实体键再重按。

曲谱、自动试听和七列指引仍使用前七键；K8～K16没有独立手机滑音。旧的事件日志命令 `REC_START` 在当前统一固件（`ENABLE_EVENT_TAKE=1`）里一律返回错误，也不存在“回到八键再录制”的步骤；板上录放直接使用 `TAKE`（App「板上 TAKE」，528 位事件格式与旧记录兼容），手机页面录制不依赖蓝牙。

曲谱和运行时配置掉电丢失；只在手机载入文件不会替换板上曲谱，必须完成下载。`ERR,CMD` 可能表示位流不支持新命令，`ERR,STATE` 表示没有有效曲谱，`ERR,MAP` 表示七键映射未覆盖曲谱音高。完整流程见 [App 说明](../pcm5102_pam8403/android_app/README.md)。
