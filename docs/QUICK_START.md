# 快速上手

[首页](../README.md) · [文档索引](README.md)

## 1. 获取完整仓库

```powershell
git clone https://gitee.com/yxy0818/cloud-audio-based-on-fpga.git
cd cloud-audio-based-on-fpga
```

主工程为 `pcm5102_pam8403/PCM5102_PAM8403.gprj`，顶层 `top`，器件 `GW5A-LV25MG121NC1/I0`。保留同级 `pmod_hub75e/`，工程直接引用其中的触摸输入模块。

## 2. 准备工具和接线

- FPGA：已有构建记录使用 Gowin V1.9.11.03 Education，需安装 IDE、Programmer 和开发板下载驱动。
- RTL 仿真：Icarus Verilog；脚本默认路径为 `C:/iverilog/bin`，可用 `-IverilogDir` 覆盖。
- 手机：Android 10+，安装[HC-05通信版 APK](../pcm5102_pam8403/android_app/dist/FPGA-Score-hc05-only.apk)，使用HC-05经典蓝牙SPP，无需USB或OTG。
- 修改 App 时再配置 JDK 和 Android SDK，步骤见 [App 文档](../pcm5102_pam8403/android_app/README.md)。现成 APK 可直接安装。

安装当前 **App v1.11 / Code12**，手机与FPGA只连接HC-05。接线先查[完整引脚表](../pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md)，键盘改接与跳线查[8/16键迁移说明](../pcm5102_pam8403/REFERENCE_MIGRATION.md)；[USB高速音频方案](../pcm5102_pam8403/AUDIO_RECORDING.md)保留备用，当前不接USB模块、RTS或OTG。关闭App的USB初始化不需要修改或重烧FPGA；LED和板上事件录制各自仍需支持对应命令的固件。

| 使用方式 | 接线与操作 |
| --- | --- |
| 默认8键直连 | OUT1～OUT8沿用原接线；原SCL接GND时F6不接，上电前600ms不触摸 |
| 16键串行 | 拆掉全部OUT直连线及SCL固定接地/接3.3V连接；SCL接F6/J3-37，SDO接F7/J3-38；设置模块16键/多键选项，App先应用匹配的串行极性，再切16键 |
| FSR或滑杆 | 同一ADC输入二选一；AO/滑杆中点经22kΩ/4.7kΩ衰减，ADC输入保持0～1V；滑杆需在App读取实际ADC两端并标定 |

16键模式下OUT脚复用为电极，不能保留原直连。App不会改变模块硬件跳线；模块配置后重新上电，校准期间保持松键。详细电气说明见 [主工程说明](../pcm5102_pam8403/README.md) 与 [FSR文档](../pcm5102_pam8403/FSR402.md)。

## 3. 仿真与构建

在仓库根目录运行指定模块测试：

```powershell
& ./pcm5102_pam8403/tools/run_sim.ps1 -Tests tb_hc05_extensions,tb_analog_expression,tb_touch_tdm_synth
```

完整 RTL 回归省略 `-Tests`。仅检查自动试听时可指定 `-Tests tb_top_audition`；这些顶层音频仿真耗时较长。软件核心测试入口为 `./pcm5102_pam8403/android_app/test-core.ps1`。

用 Gowin IDE 打开主工程并执行完整综合、布局布线与位流生成，或使用命令行（将下面路径替换为本机安装路径）：

```powershell
$gowinShell = 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe'
& $gowinShell ./pcm5102_pam8403/tools/build.tcl
```

生成位流：`pcm5102_pam8403/impl/pnr/PCM5102_PAM8403.fs`。该文件不在源码仓库中。检查构建日志和时序报告，最近已记录构建见 [VERIFICATION.md](../pcm5102_pam8403/VERIFICATION.md)；重新构建后的指纹可能不同。

当前 HC-05 默认配置可用 `& $gowinShell ./pcm5102_pam8403/tools/build_hc05_only.tcl` 生成独立的 `PCM5102_HC05_ONLY.fs`。同条件资源对比、固定源码和验证范围见 [HC-05 资源优化](../pcm5102_pam8403/HC05_RESOURCE_OPTIMIZATION.md)。此配置综合时移除备用 USB 录音硬件，手机仍使用 App v1.11 和现有 HC-05。

## 4. 下载开发板

在 Programmer 中选择主工程新生成的 `.fs`，执行 **SRAM Program**。也可运行脚本，按本机路径和已连接的线缆位置修改参数：

```powershell
& ./pcm5102_pam8403/tools/program_sram.ps1 -ProgrammerDir 'C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin' -CableLocation 385
```

`385` 是现有开发机记录的线缆位置，其他电脑需按 Programmer 检测结果调整。脚本下载后读取 UserCode 并与位流头比较。SRAM 配置断电丢失；重新编译不会自动更新板上程序。

## 5. 首次演奏和曲谱试听

1. 默认8键模式先用K1～K7演奏C4～B4，K8切压力用途。16键接线和配置完成后K1～K16全部演奏，K8～K16固定C5～D6，压力用途改由App选择。
2. 手机系统配对 HC-05，再在 App 中连接已配对设备。Android 12+ 需允许“附近的设备”。
3. 载入示例或导入 CSV/MIDI，点击“校验键位并下载”，等待显示已提交。
4. 自己演奏使用 `PLAY` 或板上 S1：预备1.5秒后显示无声曲谱指引，按键实时发声。
5. 自动试听使用当前App“自动演奏 · 已下载曲谱”：`AUDITION` 使用前七个触摸声部合成声音，曲谱结束自动停止；`STOP` 提前停止曲谱，保留现场音符。
6. 空闲时LED显示总览，播放时显示曲谱。S2长按约1秒依次切换总览/曲谱、波形、XY、FFT；XY页短按选图，其他页短按重启曲谱。
7. 在App应用音效、总音量或延音后查看设备读回和LED状态；需要关闭锁存并清除声音/尾音时使用`PANIC`，随后松开实体键再重按。

曲谱、自动试听和七列指引仍使用前七键；K8～K16没有独立手机滑音。16键、延音锁存或滑杆模式会拒绝事件录制，回到8键、关闭锁存并选择FSR用途后再录制。

曲谱和运行时配置掉电丢失；只在手机载入文件不会替换板上曲谱，必须完成下载。`ERR,CMD` 可能表示位流不支持新命令，`ERR,STATE` 表示没有有效曲谱，`ERR,MAP` 表示七键映射未覆盖曲谱音高。完整流程见 [App 说明](../pcm5102_pam8403/android_app/README.md)。
