# 统一录制版说明（50 MHz 布局布线通过）

> 2026-10-21：当前 `PCM5102_UNIFIED.gprj` 为钢琴踏板版，按用户授权关闭 FPGA Flash PCM 原音录制，保留手机本地录制和板上事件录制。事件录制与新踏板/POLY 状态暂不兼容，录制前设 `HOLD,0/1`、`POLY,16`。配套 `dist/FPGA-Music-Pedal.apk` 会探测能力并明确提示；下文的 30 秒 PCM 和资源时序数据属于 2026-10-20 历史统一版，不能用于描述当前踏板版。当前结果见 `../VERIFICATION.md`。

## 先区分三种录制

- **手机录制**：在 APP 的“手机琴键与我的录音”中按“开始手机录制”，弹奏页面琴键，停止后可立即从手机回放、命名新增保存、改名、确认删除或导出 `.mid`。不需要蓝牙。保存数量受手机空间限制，每份最多 10000 个按键音符，保存失败保留当前草稿。
- **板上事件录制**：记录实体演奏的控制与按键事件，停止后可以从开发板立即重放；按“保存到 Flash”后才写入非易失存储。与手机录制分别保存。
- **板上原音质录音**：记录 I2S 输出对应的 48828.125 Hz、16 位单声道 PCM，最长 30 秒，停止后校验并提交，再通过 HC-05 回传为 WAV。9600bps 传输 30 秒音频约需 54 分钟，不是即时手机回放。

参考项目的“停止后立刻回放”采用第一种方案：手机记录页面琴键的音符时间，手机再次合成发声，不必等待板上 WAV 传输。参考代码：
https://gitee.com/xu-qianru/fpga-musical-magic-box/blob/03dae97ae942c0efefae4127dcede312f09058a6/1/fpga_project_1/app-preview/lib/songlib/app.mjs
https://gitee.com/xu-qianru/fpga-musical-magic-box/blob/03dae97ae942c0efefae4127dcede312f09058a6/1/fpga_project_1/app-preview/lib/songlib/audio-adapter.mjs

## 新 APP 与旧固件

`dist/FPGA-Music-Unified.apk` 可连接原 `PCM5102_PAM8403.fs`。普通固件不支持的 Flash 原音质录制会显示说明；收到完整的 `ERR,STATE` / `ERR,CMD` / `ERR,BUSY` 等设备拒绝时保留蓝牙连接。串口帧错误、连接中断和超时仍会结束有问题的连接。

手机录制和“我的录音”不依赖 FPGA 固件。普通固件未包含的板上功能不能由 APP 补出来。

## FPGA 统一工程

工程是 `../PCM5102_UNIFIED.gprj`，顶层 `top_unified`。保留正常演奏、曲谱、LED 和遥控，同时加入板上事件录制及原音质录音。16 个实体琴键保留演奏用途，录制操作由 APP 发起。事件录制与 PCM 录音互斥，Flash 操作共用同一 NOR 引擎、分别校验自己的存储分区。

2026-10-20 的 `shared_p2r0` 构建已在 GW5A-LV25MG121NC1/I0 上完整布通并生成 `PCM5102_UNIFIED.fs`。50 MHz 约束下实际 Fmax 为 **50.717 MHz**，Setup/Hold 违例端点均为 **0**。实际占用 Logic 22210/23040、CLS 11381/11520、BSRAM 46/56、DSP 26.5/28。构建使用布局算法 2、布线算法 0、最大扇出 23；未放宽主时钟约束。

交付包位于 `../deliveries/UNIFIED_RECORDING_20261020/`，包含统一位流、`FPGA-Music-Unified.apk`、源码压缩包、报告和 SHA256。烧录统一位流后可在同一固件中使用上述板上功能；手机本地录制不依赖烧录。

## 验证

- `test-core.ps1`：蓝牙命令错误恢复、能力探测、手机录制/MIDI/多份存储，以及原有 HC-05 PCM→WAV 测试。
- `build-apk.ps1`：构建和校验 APK。
- `../tools/check_unified_build.ps1 -Label <新名称>`：创建独立源码快照并使用 GW5A-25A 进行综合、布局布线。不能复用已有名称，以免覆盖验证证据。
- `../tools/run_sim.ps1 -Tests tb_top_unified`：外部 I2S 与 HC-05 逐采样比对，含板上事件录制/重放、Flash 提交、录制忙状态拒绝和后续 PING。

本轮没有替用户连接手机、安装 APK 或向开发板烧录；手机音频输出、蓝牙电气连接和板上 Flash 实测仍需真机验证。
