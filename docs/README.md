# 文档索引

[返回仓库首页](../README.md)

当前主工程是 `pcm5102_pam8403/PCM5102_UNIFIED.gprj`，顶层 `top_unified`，当前固件为 2026-10-21 B1 半音阶版。首次使用按“快速上手 → 接线 → [App 说明](../pcm5102_pam8403/android_app/README.md) → [验证记录](../pcm5102_pam8403/VERIFICATION.md)”的顺序阅读。合并前的工程及专用脚本见[历史归档](../pcm5102_pam8403/archive/legacy_projects/README.md)。

## 使用与调试

| 文档 | 内容 |
| --- | --- |
| [快速上手](QUICK_START.md) | 克隆、工具准备、仿真、构建、SRAM 下载和首次演奏 |
| [主工程说明](../pcm5102_pam8403/README.md) | 整体架构、触摸操作、音频接口和默认参数 |
| [引脚与功能验收表](../pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md) | 完整接线、功能实现状态、赛题口径和现场验收步骤 |
| [8/16 键与参考功能迁移](../pcm5102_pam8403/REFERENCE_MIGRATION.md) | 模式、串行极性、16 键和弦、音效、延音、滑杆标定、64×64 状态页图例 |
| [B1 半音阶与高音条](../pcm5102_pam8403/CHROMATIC_KEYS.md) | K1～K16 扫描序号、音名、MIDI 与 DDS 步进对照，改动边界及实机测频待办 |
| [安卓曲谱助手](../pcm5102_pam8403/android_app/README.md) | App v1.16-chromatic 安装入口、半音阶钢琴键盘、制音踏板与复音上限控件、曲库与 LED 控制 |
| [App 侧边栏阶段 A](../pcm5102_pam8403/android_app/SIDEBAR.md) | 六分区侧边栏、三源七分组、草稿与设备确认三态、事件录制一键切可录配置 |
| [侧边栏方案审查](../pcm5102_pam8403/SIDEBAR_REVIEW.md) | 阶段 A 边界与后续阶段的资源 / 命令号预算复核，明确哪些数字未重新综合 |
| [录制操作与限制](../pcm5102_pam8403/android_app/UNIFIED_RECORDING.md) | 手机本地录制、板上事件录制重放；PCM 原音回传章节属于 2026-10-20 历史统一版 |
| [备用高速音频录制](../pcm5102_pam8403/AUDIO_RECORDING.md) | 当前停用；保留2Mbps USB/RTS与FAR1协议，不改走现有9600bps |
| [蓝牙曲谱与事件日志](../pcm5102_pam8403/BLUETOOTH_MEDIA.md) | 曲谱协议、PLAY/AUDITION/STOP、日志与错误码 |
| [HC-05 与键位映射](../pcm5102_pam8403/HC05_KEYMAP.md) | UART 接线、通信参数和改键，含 `HOLD,2` 踏板与 `POLY,n` 命令及查询 |
| [压力输入](../pcm5102_pam8403/FSR402.md) | FSR402、ADC 分压、力度和音高模式 |
| [运行时 ADSR](../pcm5102_pam8403/ADSR_RUNTIME.md) | 两套音源包络、App 编辑与生效时机；踏板四段尾音与制音参数 |
| [七声部独立滑音](../pcm5102_pam8403/VOICE_PITCH.md) | 每键音分调节与 FSR 叠加 |
| [七轨曲谱指引](../pcm5102_pam8403/RHYTHM_GUIDE.md) | 下落音符、和弦、休止及显示范围 |
| [音频可视化](../pcm5102_pam8403/AUDIO_VISUAL.md) | 波形、参考/混音 XY、FFT、S2 切页与 XY 命令 |
| [LED 视觉与 App 联动](../pcm5102_pam8403/LED_VISUAL_APP_PLAN.md) | 功能总表、现有联动、手机 LED 控件建议、带宽与资源边界 |
| [手机 LED 轨迹控制](../pcm5102_pam8403/android_app/LED_CONTROL.md) | App v1.9 安装、六个 XY 预设、频率比/相位与设备确认 |
| [手机切页与实时预览](../pcm5102_pam8403/LED_REMOTE.md) | App v1.10 与配套位流、四页切换、实际状态、频谱与幅度回传 |
| [统一版历史验证](../pcm5102_pam8403/RAM_GEOMETRY_VERIFICATION.md) | 2026-10-20 含 PCM 录制版本的 RAM 优化、逐时钟等价与吞吐结果，含构建复查脚本 |
| [验证记录](../pcm5102_pam8403/VERIFICATION.md) | 顶部为当前 B1 半音阶版的构建、UserCode、SHA256 与仿真范围；其余按时间倒序记录踏板版及更早构建和未完成的实板验证 |
| [FPGA 资源优化](../pcm5102_pam8403/RESOURCE_OPTIMIZATION.md) | 日志缓存定宽、曲谱行选择共享、同条件快照对比与独立位流 |
| [HC-05 资源优化](../pcm5102_pam8403/HC05_RESOURCE_OPTIMIZATION.md) | 默认裁掉 USB 硬件、共享 53 命令译码、曲谱计时缩位、最新位流与 19 组 RTL 验证 |
| [仓库维护](REPOSITORY.md) | Git 更新、目录约定、文档维护和上传范围 |
| [版本记录](CHANGELOG.md) | App/FPGA 配套版本、升级要点与兼容范围 |

完整接线以验收表及统一工程实际引用的 `src/PCM5102_EVENT_TAKE.cst`、`src/PCM5102_UNIFIED.sdc` 为依据。最新位流和 App 配套信息以[验证记录](../pcm5102_pam8403/VERIFICATION.md)顶部为准；历史段落与上一版[统一版历史验证](../pcm5102_pam8403/RAM_GEOMETRY_VERIFICATION.md)中的编号不代表当前版本。

## 独立工程与历史资料

| 文档 | 适用范围 |
| --- | --- |
| [合并前工程归档](../pcm5102_pam8403/archive/legacy_projects/README.md) | 三个旧 `.gprj` 模板、专用构建与打包脚本的原始副本，不作为当前入口 |
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
