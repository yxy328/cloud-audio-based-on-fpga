# 文档索引

[返回仓库首页](../README.md)

当前主工程是 `pcm5102_pam8403/PCM5102_UNIFIED.gprj`，顶层 `top_unified`，器件 `GW5A-LV25MG121NC1/I0`，触摸输入固定为 TTP229 十六键串行（八键 GPIO 模式已于 2026-10-26 取消）。当前位流为 2026-10-27 曲谱弯音构建（Logic 22453 / CLS 11439 / BSRAM 55 / DSP 26.5，SHA256 `EBAEAD00…`，本轮未记录 UserCode，尚未烧录），当前 App 为 v1.38-scorebend / Code39。首次使用按“快速上手 → 接线 → [App 说明](../pcm5102_pam8403/android_app/README.md) → [验证记录](../pcm5102_pam8403/VERIFICATION.md)”的顺序阅读。合并前的工程及专用脚本见[历史归档](../pcm5102_pam8403/archive/legacy_projects/README.md)。

## 使用与调试

| 文档 | 内容 |
| --- | --- |
| [快速上手](QUICK_START.md) | 克隆、工具准备、仿真、构建、SRAM 下载和首次演奏 |
| [主工程说明](../pcm5102_pam8403/README.md) | 整体架构、触摸操作、音频接口和默认参数 |
| [引脚与功能验收表](../pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md) | 完整接线、功能实现状态、赛题口径和现场验收步骤 |
| [8/16 键与参考功能迁移](../pcm5102_pam8403/REFERENCE_MIGRATION.md) | 串行极性、16 键和弦、音效、延音、滑杆 ADS1115 接线与标定、64×64 状态页图例；其中 8/16 键切换自 2026-10-26 起取消，实际输入以[固定十六键](../pcm5102_pam8403/TOUCH16.md)为准 |
| [B1 半音阶与高音条](../pcm5102_pam8403/CHROMATIC_KEYS.md) | K1～K16 扫描序号、音名、MIDI 与 DDS 步进对照，改动边界及实机测频待办 |
| [固定十六键串行输入](../pcm5102_pam8403/TOUCH16.md) | 八键 GPIO 删除后的接线与上电校准、`CTRL?` / `CTRL2?` 模式字段恒为 1、`TOUCH,8` 拒绝、`SERIAL,0/1` 极性恢复条件 |
| [合唱 / 延迟 / 混响三效果](../pcm5102_pam8403/FX3.md) | 混音 → CHORUS → DELAY → REVERB → 总音量链路、各块参数与清尾规则、`EFFECT,3,m,s,w` 位布局、旧固件兼容行为 |
| [曲谱逐事件弯音](../pcm5102_pam8403/SCORE_BEND.md) | 三列 CSV 的 `bend_target_cents` 规则与空白 / 0 语义、`SONG_CHORD` Q2.14 比率、`SONG_BEGIN,?` 返回 `SONGBEND,1`、试听 / STOP / TAKE 行为与明确拒绝项 |
| [常用演奏操作一页](../pcm5102_pam8403/PERFORMANCE_QUICKSTART.md) | 演奏页连接、总音量、三效果场景保存与应用、紧急止音的顺序，以及「配置 / 实际 / 草稿」三种状态的区别 |
| [演奏参数与四档回声](../pcm5102_pam8403/PERFORMANCE_PARAMS.md) | 当前版本的取舍与覆盖范围、`PITCH` / `VIB` / `EFFECT2` 公式与默认值、四档回声实现、逐项资源预算、通过项与未完成的实物对录 |
| [阶段 E 范围复核](../pcm5102_pam8403/E_SCOPE.md) | E 预留改为 600 Logic / 100 CLS 后的准入范围与施工顺序，以及 2026-10-26 之后按实际余量逐项尝试的结论（全局震音与 E4/E2/E3/E1 候选均未满足资源准入） |
| [安卓曲谱助手](../pcm5102_pam8403/android_app/README.md) | 当前 v1.38-scorebend / Code39 滚动入口与 Code35 / Code27 / Code26 回退包差异、演奏页常用入口与手机本地三效果场景、三张独立效果卡、曲谱弯音导入导出、33 档色环实时预览、板键联动、半音阶钢琴键盘、制音踏板与复音上限控件、曲库与 LED 控制 |
| [手机色环频谱面板](../pcm5102_pam8403/android_app/HUE33.md) | “显示”分区顶部的青蓝紫红色环面板、33 个 RGB5 锚点与 RTL 逐项对照、数据口径与排版检查 |
| [App 侧边栏阶段 A](../pcm5102_pam8403/android_app/SIDEBAR.md) | 六分区侧边栏、三源七分组、草稿与设备确认三态、事件录制一键切可录配置 |
| [侧边栏方案审查](../pcm5102_pam8403/SIDEBAR_REVIEW.md) | 阶段 A 边界与后续阶段的资源 / 命令号预算复核，明确哪些数字未重新综合 |
| [录制操作与限制](../pcm5102_pam8403/android_app/UNIFIED_RECORDING.md) | 手机本地录制、板上事件录制重放与 `KLIVE` 板键联动写盘；PCM 原音回传章节属于 2026-10-20 历史统一版 |
| [备用高速音频录制](../pcm5102_pam8403/AUDIO_RECORDING.md) | 当前停用；保留2Mbps USB/RTS与FAR1协议，不改走现有9600bps |
| [蓝牙曲谱与事件日志](../pcm5102_pam8403/BLUETOOTH_MEDIA.md) | 曲谱协议、PLAY/AUDITION/STOP、日志与错误码 |
| [HC-05 与键位映射](../pcm5102_pam8403/HC05_KEYMAP.md) | UART 接线、通信参数和改键，含 `HOLD,2` 踏板、`POLY,n`、`PITCH` / `VIB` / `EFFECT2` 命令、`EFFECT,3` 与 `EFFECT,?` 三效果读写、`SONG_BEGIN,?` 返回的 `SONGBEND` 能力位（比率字段格式见[曲谱弯音](../pcm5102_pam8403/SCORE_BEND.md)）、`KLIVE_ON` / `KLIVE_OFF` 键值上行、`SERIAL,0/1` 与 `ANALOG` / `CAL` 双通道用法 |
| [HC-05 连接初始化与超时定位](../pcm5102_pam8403/HC05_CONNECTION.md) | Code24 /1.23-linkdiag 安装入口与设备页版本核对、Code22 握手超时根因、回复单处匹配规则、4 秒超时提示怎么读、已确认与尚未确认的边界 |
| [压力输入](../pcm5102_pam8403/FSR402.md) | FSR402、片内 ADC 分压、力度和音高模式；滑杆已迁到独立 ADS1115 通道，两路可同时采 |
| [运行时 ADSR](../pcm5102_pam8403/ADSR_RUNTIME.md) | 两套音源包络、App 编辑与生效时机；踏板四段尾音与制音参数 |
| [七声部独立滑音](../pcm5102_pam8403/VOICE_PITCH.md) | 每键音分调节与 FSR 叠加 |
| [七轨曲谱指引](../pcm5102_pam8403/RHYTHM_GUIDE.md) | 下落音符、和弦、休止及显示范围 |
| [音频可视化](../pcm5102_pam8403/AUDIO_VISUAL.md) | 波形、参考/混音 XY、FFT、S2 切页与 XY 命令 |
| [LED 波形量程与色环](../pcm5102_pam8403/SCOPE_DISPLAY.md) | 当前波形页读数：FSR 联动 X8 /X16 /X32 六档量程、有符号 10 位极值、48 箱 512 采样时间轴、PCM/64 的 33 档青→红色环与整帧同色规则、静音白色、PK 固定满幅刻度、`scope_style.hex` 样式表与复现命令 |
| [LED 波形外观候选设计稿](../pcm5102_pam8403/design/led_scope_20261022/README.md) | 依据 `Photograph/` 七张实拍照片制作的 A～D 四种横轴与配色效果图、FSR 量程方案对照、8 档与 33 档色环映射图与原始像素图；仅设计参考，不代替生产 RTL 输出 |
| [效果器帧预算与资源前置核验](../pcm5102_pam8403/FX_PREFLIGHT_20261024.md) | 2026-10-24 的前置核验：50MHz / 1024 拍帧内触摸、弯音、效果器并行占用实测与额度缺口结论；三效果正式 RTL 已于 2026-10-26 接入，见[三效果说明](../pcm5102_pam8403/FX3.md) |
| 2026-10-26～27 各轮交付报告 | [固定十六键](../pcm5102_pam8403/reports/touch16_delivery_20261026/README.md) · [三效果优先版](../pcm5102_pam8403/reports/fx_priority_20261026/REPORT.md) · [演奏体验与后续候选](../pcm5102_pam8403/reports/performance_experience_20261026/REPORT.md) · [第一轮 HC-05 CLS 回收](../pcm5102_pam8403/reports/hc05_cls_first_20261026/README.md) · [第二步显示读口（已撤回）](../pcm5102_pam8403/reports/display_ports_20261026/README.md) · [第三步控制装箱](../pcm5102_pam8403/reports/control_pack_20261026/README.md) · [CLS 只读调研](../pcm5102_pam8403/reports/cls_research_20261026/ASSESSMENT.md) · [曲谱弯音](../pcm5102_pam8403/reports/score_bend_integration_20261026/README.md)；每轮目录只入库报告正文、脚本与 JSON 证据，重建出的位流、回退 APK 与原始采样向量按 `.gitignore` 留在本机 |
| [LED 视觉与 App 联动](../pcm5102_pam8403/LED_VISUAL_APP_PLAN.md) | 功能总表、现有联动、手机 LED 控件建议、带宽与资源边界 |
| [手机 LED 轨迹控制](../pcm5102_pam8403/android_app/LED_CONTROL.md) | App v1.9 安装、六个 XY 预设、频率比/相位与设备确认 |
| [手机切页与实时预览](../pcm5102_pam8403/LED_REMOTE.md) | App v1.10 与配套位流、四页切换、实际状态、频谱与幅度回传 |
| [统一版历史验证](../pcm5102_pam8403/RAM_GEOMETRY_VERIFICATION.md) | 2026-10-20 含 PCM 录制版本的 RAM 优化、逐时钟等价与吞吐结果，含构建复查脚本 |
| [验证记录](../pcm5102_pam8403/VERIFICATION.md) | 顶部为 2026-10-27 曲谱弯音默认构建与 2026-10-26 三轮 CLS 尝试的资源、SHA256 与仿真范围，其后按时间倒序记录固定十六键（Code26）、三效果（Code27）、演奏体验（Code35）、App v1.24-hue / Code25、33 档色环位流（UserCode `0x00002176`）、弱信号修正版、四档回声、半音阶、踏板版及更早构建和未完成的实板验证 |
| [33 档色环位流交付包](../pcm5102_pam8403/deliveries/LED_HUE33_20261023/README.md) / [App 色环交付包](../pcm5102_pam8403/deliveries/APP_HUE33_20261023/README.md) | 色环改动的完整 diff 与行号、五项 testbench 的 PASS 原文、前后综合 / PnR 对照与 Code25 构建日志 |
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
