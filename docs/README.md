# 文档索引

[返回仓库首页](../README.md)

当前主工程是 `pcm5102_pam8403/PCM5102_PAM8403.gprj`。首次使用按“快速上手 → 接线 → App → 验证记录”的顺序阅读。

## 使用与调试

| 文档 | 内容 |
| --- | --- |
| [快速上手](QUICK_START.md) | 克隆、工具准备、仿真、构建、SRAM 下载和首次演奏 |
| [主工程说明](../pcm5102_pam8403/README.md) | 整体架构、触摸操作、音频接口和默认参数 |
| [引脚与功能验收表](../pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md) | 完整接线、功能实现状态、赛题口径和现场验收步骤 |
| [8/16 键与参考功能迁移](../pcm5102_pam8403/REFERENCE_MIGRATION.md) | 模式、串行极性、16 键和弦、音效、延音、滑杆标定、64×64 状态页图例 |
| [安卓曲谱助手](../pcm5102_pam8403/android_app/README.md) | App v1.4 安装、蓝牙连接、CSV/MIDI 导入和自动试听 |
| [蓝牙曲谱与事件日志](../pcm5102_pam8403/BLUETOOTH_MEDIA.md) | 曲谱协议、PLAY/AUDITION/STOP、日志与错误码 |
| [HC-05 与键位映射](../pcm5102_pam8403/HC05_KEYMAP.md) | UART 接线、通信参数和改键 |
| [压力输入](../pcm5102_pam8403/FSR402.md) | FSR402、ADC 分压、力度和音高模式 |
| [运行时 ADSR](../pcm5102_pam8403/ADSR_RUNTIME.md) | 两套音源包络、App 编辑与生效时机 |
| [七声部独立滑音](../pcm5102_pam8403/VOICE_PITCH.md) | 每键音分调节与 FSR 叠加 |
| [七轨曲谱指引](../pcm5102_pam8403/RHYTHM_GUIDE.md) | 下落音符、和弦、休止及显示范围 |
| [音频可视化](../pcm5102_pam8403/AUDIO_VISUAL.md) | 波形、参考/混音 XY、FFT、S2 切页与 XY 命令 |
| [验证记录](../pcm5102_pam8403/VERIFICATION.md) | 按时间倒序记录构建、指纹、仿真结果和未完成的实板验证 |
| [仓库维护](REPOSITORY.md) | Git 更新、目录约定、文档维护和上传范围 |
| [版本记录](CHANGELOG.md) | App/FPGA 配套版本、升级要点与兼容范围 |

完整接线以验收表及 `src/PCM5102_PAM8403.cst` 为依据。最新位流和 App 配套信息查验证记录顶部；历史段落中的编号不代表当前版本。

## 独立工程与历史资料

| 文档 | 适用范围 |
| --- | --- |
| [显示/触摸模式](../MODE_SELECTION.md) | 独立 `pmod_hub75e` 工程 |
| [TTP229 GPIO](../ttp229_gpio/README.md) / [串行16键](../ttp229_serial16/README.md) | 两种独立输入验证工程，接法不同 |
| [HC-05 回显](../hc05_uart_echo/README.md) | 独立蓝牙链路测试 |
| [DDS 第一步](../pcm5102_dds_step1/README.md) | 单声部历史验证快照 |
| [ALL_IN 历史参考](../ALL_IN/README.md) | 手势/吉他融合前的参考代码 |
| [传感器融合记录](../pcm5102_pam8403/SENSOR_INTEGRATION.md) | 顶部说明当前状态，后半保留早期融合记录 |
| [红外参考审查](../pcm5102_pam8403/IR_REFERENCE_REVIEW.md) | 接入前的参考分析；外部原工程仅保留在本机 |
| [早期合成方案](../pcm5102_pam8403/SYNTH_PLAN.md) | 历史架构与开发计划 |
| [早期小星星试听](../pcm5102_pam8403/MUSIC_PREVIEW.md) / [第三步记录](../pcm5102_pam8403/STEP3.md) | 历史演示模式、位流与操作 |

历史文档中的 `sim/build/` 波形、日志、试听文件及本机参考目录不会随 Git 克隆取得，需使用对应脚本重建或在原开发机查看。
