# 2026-10-19 FPGA 资源优化记录

后续 [HC-05 默认配置优化](HC05_RESOURCE_OPTIMIZATION.md)已完成：共享命令译码、默认移除 USB 录音硬件及曲谱计时缩位，最新独立位流为 `PCM5102_HC05_ONLY.fs`。下面保留本轮较早构建的数据，最新指标与验证范围见后续记录。

已将日志缓存定宽和曲谱显示行选择合并应用到主工程。以同一份源码快照、同一器件和工具设置比较，两个 RTL 修改使综合 Logic 从 **23155 降到 22012，减少 1143（4.94%）**，解决该快照超出 23040 上限的问题。包含工作区同期 UART 修改的最终整合构建也已完成，布局布线使用 **21745/23040 Logic**，50MHz Setup/Hold 违例均为 0。

参考用户提供的[资源优化文章](https://blog.csdn.net/Pieces_thinking/article/details/147780561)，按本工程 Gowin 的实际报告选择适用方向；文中的 Vivado 命令和属性不能直接作为本工程的配置。结果以本机综合、布局布线和仿真为准。

## 实际修改

- `src/performance_logger.v`：发送缓存从 64 字节缩到 33 字节，同时调整移位切片、左对齐和长度计数位宽。最长事件行为 `EVT,4294967295,7F,1,65535,65535\r\n`，共 33 字节；MAP 最长 26，溢出消息最长 29，REC_END 最长 20。64 条事件 FIFO、32 位时间戳和丢弃计数范围保留。
- `src/hub75e_rhythm_display.v`：先用固定连线合并三行高音符的相邻位图，再选择上下半屏各一行，代替六次独立动态行选择。保持同一时钟边沿捕获、55 行以后的音符头裁剪、七条键道、133 时钟扫描周期、RGB5 PWM 及显示切页行为。
- `src/PCM5102_PAM8403.sdc`：修正已有 CTS 假路径中的生成块层级名，从 `legacy_pcm/u_audio_record` 改成工具实际使用的 `legacy_pcm.u_audio_record`。异常仅指向异步 CTS 的第一级 `cts_meta`；第二级与主时钟仍正常检查。原错误在资源溢出修复后才进入 PNR 并暴露。
- `tools/check_resources.ps1` / `.tcl`：复制源码、共享触摸模块、工程和过程配置到独立快照，保存输入 SHA256，固定 50MHz、资源共享与重定时设置，输出独立的 `PCM5102_RESOURCE` 产物。可从基准快照只覆盖指定源码，便于区分本轮优化和同期修改的收益。

## 同条件对比与最终结果

Gowin **V1.9.11.03 Education**，器件 **GW5A-LV25MG121NC1/I0**，默认顶层 `top`。

| 指标 | 优化前快照 baseline | 仅本轮两处 RTL 优化 optimized | 最新整合快照 integrated |
| --- | ---: | ---: | ---: |
| 综合 Logic | 23155，超过上限 | 22012 | 21592 |
| 布局布线 Logic | 未进入 PNR | 22156/23040 | 21745/23040 |
| Register | — | 9653/23280 | 9616/23280 |
| CLS | — | 11374/11520 | 11363/11520 |
| BSRAM | — | 53/56 | 53/56 |
| DSP | — | 20.5/28 | 20.5/28 |
| Fmax | — | 50.082MHz | 50.806MHz |
| 最差 Setup Slack | — | +0.033ns | +0.317ns |
| Setup/Hold 违反端点 | — | 0/0 | 0/0 |

综合与 PNR 数量属于不同阶段，不能直接相减。`optimized` 的 RTL 只覆盖本轮两个模块；另修正了上述 SDC。`integrated` 还包含工作区同期的 HC-05 回复串行格式化修改，额外收益不能全部归因于本轮两个模块。最新构建仍有 1 条已有的 `CV0016`（默认配置不使用 `flash_miso`），无 ERROR。

整合构建于北京时间 **2026-10-19 12:01:39** 完成。剩余 Logic 1295、CLS 157、BSRAM 3；时序余量约 0.317ns，继续加功能仍需重新检查布局布线。

## 验证

本轮共通过 **12 组不同 RTL 测试**，部分显示用例在修正生成期边界写法后重跑：

- `tb_performance_logger`：原有事件、FIFO64、溢出与 STOP；新增 33 字节最大 EVT、4294967295 时间戳和丢弃数、计数饱和、最大行发送暂停。相同扩展测试也在优化前模块上通过。
- `tb_hub75e_rhythm_display`：外部扫描/RGB5 PWM、下降轨迹、128 个逐时钟事件、滚动/插入/STOP 冲突、3002 个算术边界场景；新增独立邻行参考模型，检查 **6173 对上下半屏行掩码**，包括行 55～63 非零头的裁剪。
- `tb_hub75e_status`、`tb_hub75e_audio_display`：外部像素重建、状态页、波形/XY/FFT、帧边界切页和扫描周期。
- `tb_hc05_download`、`tb_hc05_control_races`、`tb_hc05_keymap`、`tb_hc05_extensions`、`tb_hc05_audio_record`、`tb_hc05_xy`：曲谱/键位/日志、忙状态、回复、录音控制与 XY 兼容回归。
- `tb_top_idle`：生产参数，136 对立体声帧，实体曲谱键不触发无触摸音频。
- `tb_top_audio_record`：真实音频/I2S/2Mbps UART 时序，**712 个录音采样与外部 I2S 解码逐字一致**；触摸、IR、分类后手势、吉他、音效/音量、CTS 暂停、TDM 期限和 HUB75 扫描通过。

日志：`sim/build/resource_unit_tests.log`、`resource_regressions.log`、`resource_top_regressions.log`、`resource_logger_baseline.log`。之后工作区可选 TAKE 分支更新，默认 `ENABLE_EVENT_TAKE=0` 的两组整机测试再次通过，日志为 `resource_top_final.log`；本报告的 PNR/位流对应已保存的 12:01:39 整合快照，可选 TAKE 配置不属于该位流的验证范围。本轮未运行完整历史套件或新位流门级仿真；静态时序通过不等同于整机实板验收，尚未烧录本轮位流。

## 产物和复现

最终独立位流：

`sim/build/resource_optimization/integrated/pcm5102_pam8403/impl/pnr/PCM5102_RESOURCE.fs`

SHA256：`ED56EDC9CED46D107F4F02B95CCE26CAC49451763CF8556B0591E4A82575B6D0`

同目录包含 `.vo`、`.rpt.txt`、`.tr.html` 及其配套报告。输入快照在各标签目录，清单为 `sources.json`；本轮核心源码指纹另存于 `sim/build/resource_optimization/verified_sources.json`。快照和产物在忽略的 `sim/build/` 下，本机保留，不随 Git 上传。

在 `pcm5102_pam8403` 中复跑当前源码，使用尚未存在的新标签：

```powershell
./tools/check_resources.ps1 -Label resource_recheck
./tools/run_sim.ps1 -Tests tb_performance_logger,tb_hub75e_rhythm_display,tb_hub75e_status,tb_hub75e_audio_display,tb_hc05_download,tb_hc05_control_races,tb_hc05_keymap,tb_hc05_extensions,tb_hc05_audio_record,tb_hc05_xy,tb_top_idle,tb_top_audio_record
```

在本机保留的 `baseline` 上只覆盖本轮修改并复核：

```powershell
./tools/check_resources.ps1 -Label resource_isolated_recheck -ReferenceLabel baseline -OverlaySource performance_logger.v,hub75e_rhythm_display.v,PCM5102_PAM8403.sdc
```

`-SynthesisOnly` 可只检查综合。构建脚本本身不操作下载器。
