# FPGA 云端曲谱与实时演奏系统

基于 **Tang Primer 25K / GW5A-25A** 的实时音频合成工程：触摸、压力、红外和手势输入驱动 FPGA 合成声音，经 PCM5102 + PAM8403 输出；安卓 App 通过 HC-05 下载音符曲谱、调整音色和演奏参数，64×64 HUB75E 屏幕提供曲谱与音频可视化。

**当前主工程：[pcm5102_pam8403/PCM5102_PAM8403.gprj](pcm5102_pam8403/PCM5102_PAM8403.gprj)**，顶层 `top`，器件 `GW5A-LV25MG121NC1/I0`。请克隆整个仓库，主工程依赖 `pmod_hub75e/` 中的共享触摸模块。

## 从这里开始

| 目的 | 文档或文件 |
| --- | --- |
| 首次下载、构建和使用 | [快速上手](docs/QUICK_START.md) |
| 查找全部功能文档 | [文档索引](docs/README.md) |
| 接线、板上操作与音频参数 | [主工程说明](pcm5102_pam8403/README.md) |
| 完整引脚、赛题要求和现场验收 | [引脚与功能验收表](pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md) |
| 手机安装和曲谱下载 | [安卓 App 说明](pcm5102_pam8403/android_app/README.md) · [HC-05通信版 APK](pcm5102_pam8403/android_app/dist/FPGA-Score-hc05-only.apk) |
| 当前构建、位流标识和验证范围 | [验证记录](pcm5102_pam8403/VERIFICATION.md) |
| 更新代码到 Gitee | [仓库维护](docs/REPOSITORY.md) |
| 版本变化与升级要点 | [版本记录](docs/CHANGELOG.md) |

## 当前功能（2026-10-19）

- **新增迁移**：[8/16 键切换、16 键和弦、滑杆标定与四种用途、回声/合唱、延音、总音量和八种红外/手势音色](pcm5102_pam8403/REFERENCE_MIGRATION.md)。
- **现场演奏**：16 路独立触摸 DDS/ADSR（默认 8 键接口）、FSR 压力音量或音高控制、八路红外与 APDS-9960 共享 32 声部 TDM 引擎，以及 Karplus–Strong 单弦吉他。
- **手机控制**：键位映射、七声部独立滑音、触摸与红外/手势独立运行时 ADSR、音色/颤音设置和演奏事件日志。
- **当前通信仅HC-05**：曲谱、参数、LED控制/低速预览及相应固件支持的事件/状态通信均走蓝牙。USB/RTS/OTG[高速音频方案保留备用，当前停用](pcm5102_pam8403/AUDIO_RECORDING.md)，不通过现有9600bps链路传完整PCM/WAV。
- **曲谱**：导入 CSV/MIDI，经经典蓝牙 SPP 下载音符、和弦、休止和时长。`PLAY` / S1 启动无声演奏指引；`AUDITION` 显式启动 FPGA 实时合成试听（自 App v1.3 起支持）。曲谱仍限前七键，16键演奏不会扩大曲谱格式。
- **64×64 LED，无需 OLED**：空闲总览显示 8/16 键、延音、音色、音量、滑杆/ADC、音效与红外；播放时自动显示曲谱。保留实际混音波形、参考/混音 XY、FFT。S2 长按约 1 秒切页；XY 页短按选图，其他页短按重启曲谱。

曲谱、参数保存在 FPGA RAM，断电需重新设置。新增 [v1.8 分级曲库安装包](pcm5102_pam8403/android_app/dist/FPGA-Score-library.apk)，青铜、白银、黄金各三首，可离线选曲并匹配七键下载，保留文件夹 CSV/MIDI 导入及曲库 CSV 导出；来源、七键改编和验证范围见[曲库说明](pcm5102_pam8403/android_app/SONG_LIBRARY.md)。尚未接入在线更新服务。默认上电不自动演奏，音频由 FPGA 逐样本生成。

当前使用 **v1.11 / Code12 HC-05通信版**，关闭USB初始化与录音入口，保留当前曲库、LED及演奏控制；此前v1.6、v1.8、v1.9和v1.10安装包保留。LED切页/预览需要[v1.10对应的配套位流](pcm5102_pam8403/LED_REMOTE.md)，板上事件录制回放另查[开发说明](pcm5102_pam8403/RECORD_PLAYBACK.md)。各版本构建、SHA256和实板验证边界见[验证记录](pcm5102_pam8403/VERIFICATION.md)。

![64×64 LED 状态总览：数字仿真预览](pcm5102_pam8403/assets/status16.png)

上图由 HUB75E 输出引脚仿真重建，屏幕标签含义见 [状态页图例](pcm5102_pam8403/REFERENCE_MIGRATION.md)。

## 工程目录

| 目录 | 定位 |
| --- | --- |
| [pcm5102_pam8403/](pcm5102_pam8403/README.md) | 当前音频、传感器、LED 与安卓 App 主工程 |
| [pmod_hub75e/](pmod_hub75e/readme.md) | 独立显示/触摸工程；同时提供主工程依赖的共享输入模块 |
| [ttp229_gpio/](ttp229_gpio/README.md) | TTP229 直连接口独立验证 |
| [ttp229_serial16/](ttp229_serial16/README.md) | TTP229 固定 16 键串行接口独立验证 |
| [hc05_uart_echo/](hc05_uart_echo/README.md) | HC-05 UART 回显与接线验证 |
| [pcm5102_dds_step1/](pcm5102_dds_step1/README.md) | 历史单声部 DDS 验证快照 |
| [ALL_IN/](ALL_IN/README.md) | 手势/吉他融合前的历史参考工程 |
| `1-2-4-按键控制LED程序/` | STM32 按键控制 LED 参考工程 |
| [docs/](docs/README.md) | 仓库文档导航、快速上手与维护说明 |

独立屏幕工程的双模式说明见 [MODE_SELECTION.md](MODE_SELECTION.md)。历史工程的引脚、位流和操作不适用于当前主工程；请按各目录说明使用。

## 获取代码

```powershell
git clone https://gitee.com/yxy0818/cloud-audio-based-on-fpga.git
cd cloud-audio-based-on-fpga
```

仓库保存源码、约束、工程配置、测试、文档和 App 安装包。主工程位流、编译缓存、SDK、工具安装包及重复备份不随源码上传，需要按 [快速上手](docs/QUICK_START.md) 在本机生成。
