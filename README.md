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
| 手机安装和曲谱下载 | [安卓 App 说明](pcm5102_pam8403/android_app/README.md) · [当前 APK](pcm5102_pam8403/android_app/dist/FPGA-Score-debug.apk) |
| 当前构建、位流标识和验证范围 | [验证记录](pcm5102_pam8403/VERIFICATION.md) |
| 更新代码到 Gitee | [仓库维护](docs/REPOSITORY.md) |

## 当前功能（2026-10-17）

- **现场演奏**：七路触摸 DDS/ADSR、FSR 压力音量或音高控制、八路红外与 APDS-9960 共享 32 声部 TDM 引擎，以及 Karplus–Strong 单弦吉他。
- **手机控制**：键位映射、七声部独立滑音、触摸与红外/手势独立运行时 ADSR、音色/颤音设置和演奏事件日志。
- **曲谱**：导入 CSV/MIDI，经经典蓝牙 SPP 下载音符、和弦、休止和时长。`PLAY` / S1 启动无声演奏指引；App v1.3 的 `AUDITION` 显式启动 FPGA 实时合成试听。
- **显示**：曲谱、实际混音波形、参考/实际混音 XY、实时 FFT 频谱。S2 长按约 1 秒切页；XY 页短按选图，其他页短按重启曲谱。

曲谱、参数保存在 FPGA RAM，断电需重新设置。当前 App 使用本地曲谱文件与 HC-05，尚未接入互联网曲库。默认上电不自动演奏，音频由 FPGA 逐样本生成。

当前 App 为 **v1.3 / versionCode 4**。与之配套的最近一次构建记录、SHA256 和实板验证边界均以 [VERIFICATION.md](pcm5102_pam8403/VERIFICATION.md) 顶部为准；已有仿真和布局布线结果不等同于整机实测验收。

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
