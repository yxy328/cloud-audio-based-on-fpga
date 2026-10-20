# 2026-10-19：HC-05 通信配置资源优化

默认工程仅通过 HC-05 与手机通信。保持现有手机命令、实时合成和 HUB75E 功能，本轮将同条件综合 Logic 从 **21058 降到 19393，减少 1665（7.91%）**；布局布线 Logic 从 **21163 降到 19506，减少 1657（7.83%）**。50MHz Setup/Hold 违反端点均为 0，已生成独立位流，尚未烧录。

## 实际修改

1. **共享命令译码电路。** `hc05_command_decode.v` 用一份同步 ROM 和一个逐字节比较器识别原有 53 个命令模板，代替大段并行字符串比较。复用已有命令 RAM，`hc05_keymap.v` 的末尾参数缓存从 96 位缩到 32 位，删除另一份 96 位前缀缓存。原有参数检查、错误回复、提交时机、日志仲裁和命令名称保留。字典占用一个 BSRAM；由 `tools/generate_hc05_decoder.py` 同时生成字典与命令编号，`--check` 检查两者一致。
2. **默认裁掉 USB 高速录音硬件。** `top` 新增 `ENABLE_USB_AUDIO_RECORD=0`，综合时移除独立录音 FIFO、CRC 和 2Mbps UART，释放一个 BSRAM；因此字典加入后总 BSRAM 仍为 53。预留引脚和备用源码保留，`audio_rec_tx` 固定空闲高电平，CTS 不参与当前逻辑。`AREC?` 返回 `AREC,0,0,0`，开始录音返回 `ERR,STATE`。HC-05 曲谱、控制、显示预览及原事件日志保持原链路，不将完整 PCM 改走 9600bps。
3. **按生产上界缩减曲谱计时器。** 曲谱最多 128 个事件、每个不超过 60000ms；含 1500ms 预备及前瞻，计时与比较采用计算出的 23 位宽度。声音游标结束后冻结时间，允许显示端长时间背压后排空，避免缩位后绕回。日志原有 32 位时间戳保持。前瞻加法显式保留进位，再按已验证上界取位，消除旧截位告警。
4. **约束与构建配套。** 默认 USB 录音同步器已不存在，因此移除只针对该同步器的 CTS 假路径，保留主时钟、ADC 和其他第一级同步器约束。新建 `tools/build_hc05_only.tcl`，输出独立文件；资源检查脚本支持从已保存快照覆盖指定旧文件，便于同条件对比。

## 同条件结果

Gowin **V1.9.11.03 Education**，器件 **GW5A-LV25MG121NC1/I0**，顶层 `top`，资源共享和 retiming 开启，主时钟 50MHz。默认 `ENABLE_EVENT_TAKE=0`、`ENABLE_USB_AUDIO_RECORD=0`。

| 指标 | 同条件优化前 hc05_matched_before | 优化后 hc05_final |
| --- | ---: | ---: |
| 综合 Logic | 21058 | 19393 |
| 布局布线 Logic | 21163/23040 | 19506/23040 |
| Register | 9340/23280 | 8856/23280 |
| CLS | 11224/11520 | 10713/11520 |
| 空闲 CLS | 296 | 807 |
| BSRAM | 53/56 | 53/56 |
| DSP | 20.5/28 | 20.5/28 |
| Fmax | 50.973MHz | 51.116MHz |
| 最差 Setup Slack | +0.382ns | +0.437ns |
| Setup/Hold 违反端点 | 0/0 | 0/0 |

`hc05_matched_before` 以最终快照为基础，仅恢复 `hc05_before` 中的 `top.v`、`hc05_keymap.v`、`downloadable_song.v` 和主工程 SDC，其他源码、TDM 改动与工具设置相同。新增译码器在旧顶层未实例化，会被裁掉。最早 `hc05_before` 的综合数为 20980，但共享工作区同期还有 TDM 修改，故不使用它计算本轮净收益。综合与布局布线数量属于不同阶段，分别比较。

最终构建于 **2026-10-19 15:27:18（上海时间）** 完成。0 ERROR，2 条 `CV0016` 告警分别为默认未使用的 `audio_rec_cts_n`、`flash_miso`。Logic 尚余 3534，CLS 尚余 807，BSRAM 尚余 3；后续功能仍需结合三者检查。当前主要容量边界仍是 BSRAM 和 CLS，不能只看 Logic 百分比。

## 验证范围

本轮 **19 组不同 RTL 测试通过**；未运行全部历史回归、新位流门级仿真或实板测试。

- `tb_hc05_decoder_equivalence`：与保留的旧并行译码器进行 **512 次真实位级 UART 事务对照**，检查回复字节、已提交控制值和动作脉冲计数；覆盖合法命令、格式错误、逐字符变异、随机行和过长行。串行化后执行延迟有变化，测试比较协议及最终控制行为。
- `tb_song_time_bound`：覆盖 **128×60000ms** 最大曲谱、23 位时间范围、1ms 断音边界及声音结束后显示端阻塞 2000 周期再排空；通过在事件边界间推进内部时间缩短仿真，RAM 和游标握手正常运行。
- `tb_hc05_keymap`、`tb_hc05_extensions`、`tb_hc05_download`、`tb_hc05_control_races`、`tb_hc05_visual`：命令、严格语法、下载原子提交、控制竞争与原子预览快照。
- `tb_downloadable_song`、`tb_hc05_adsr`、`tb_hc05_bend`、`tb_hc05_xy`、`tb_hc05_audio_record`、`tb_hc05_take`：曲谱背压、运行时参数、备用/可选协议兼容。
- `tb_top_hc05_only`：默认配置的真实 UART、CTS 隔离、录音状态/拒绝、触摸发声与释放、I²S、TDM 期限和 HUB75 扫描。
- `tb_top_audio_record`：显式启用备用 USB 录音配置，712 个采样与外部 I²S 逐字一致；此测试不代表该可选配置完成本轮布局布线。
- `tb_top_live`、`tb_top_idle`、`tb_top_score_config`、`tb_top_audio_visual`：3821 对现场多声部采样、136 对生产空闲采样、曲谱/试听配置、连续音频相位、ADC/控制总览、S2/手机四页、整帧显示切换和 32 字节实时预览。

日志为 `sim/build/hc05_decoder_first.log`、`hc05_decoder_more.log`、`hc05_differential.log` 和 `hc05_top_regressions.log`。字典生成检查通过。布局布线及位流对应固定 `hc05_final` 快照；之后工作区可选 TAKE 分支新增 `frame_ce` 接线，不参与该默认配置。可选 Flash 事件录制的独立工程不属于本报告验收范围。

## 已查看的 Gitee 参考

已通过 Git 读取用户提供的 [fpga-musical-magic-box](https://gitee.com/xu-qianru/fpga-musical-magic-box)，固定提交为 **03dae97ae942c0efefae4127dcede312f09058a6**，README 标注 **fix41 + Android App 1.0.1**。本次重点查看 README、`tdm_synth.v`、`bluetooth_octave.v`、`audio_effects.v`、fix41 说明及资源报告，没有运行其脚本。工作区原有副本是 fix28，其中“尚未实现蓝牙”的说明不适用于线上 fix41；线上版本已实现 HC-05 9600/8N1 手机联动。

可借鉴的方向是低速控制状态机复用运算，以及声部上下文按 RAM 宽度组织。其 32 声部共享 33×18 乘法器、437 位上下文分成两份 219 位存储；本工程也已使用 TDM。其包络配置较紧凑，本工程还保存精确运行时 ADSR 步长与独立声部参数，直接替换会改变现有语义，故本轮保留。后续可评估包络参数池及上下文重新打包，须先验证活动声部配置快照和满复音期限。

参考项目采用 ST7796/FT6336 和 74HC595，与本工程 HUB75E、压力输入和命令集合不同。没有照搬其引脚、精简协议或位流；两个项目资源报告不能作为同功能 A/B 对照。本轮节省量以上表本工程同条件快照为依据。

参考文件的本机读取副本和指纹位于 `sim/build/gitee_reference_03dae97/`，不随源码仓库上传。

## 产物与复现

- 独立位流：[PCM5102_HC05_ONLY.fs](impl/pnr/PCM5102_HC05_ONLY.fs)
- 资源报告：[PCM5102_HC05_ONLY.rpt.txt](impl/pnr/PCM5102_HC05_ONLY.rpt.txt)
- 时序报告：[PCM5102_HC05_ONLY_tr_content.html](impl/pnr/PCM5102_HC05_ONLY_tr_content.html)
- 指纹和配置：[PCM5102_HC05_ONLY_manifest.json](impl/pnr/PCM5102_HC05_ONLY_manifest.json)
- 构建输入与日志：[HC05_ONLY_sources.zip](sim/build/HC05_ONLY_sources.zip)

位流 SHA256：`99249FC9FA132F48BE4FC3E1C9847B946BE86062DF3261760B7F478DBCECB326`。交付副本来自 `sim/build/resource_optimization/hc05_final/pcm5102_pam8403/impl/pnr/PCM5102_RESOURCE.fs`，只改文件名，字节相同。快照目录保留输入 `sources.json`、工具日志、网表及完整时序报告；生成产物被 Git 忽略，克隆后需重建。

源码压缩包的 87 个输入逐项符合 `sources.json`。Gowin 在构建目录改写过程配置的输出文件名；压缩包保存原始输入配置，脚本会将输出名设为 `PCM5102_RESOURCE`，差异另记于包内 `archive_notes.json`。

在 `pcm5102_pam8403` 目录构建当前默认配置（Gowin 路径按本机调整）：

```powershell
python ./tools/generate_hc05_decoder.py --check
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' ./tools/build_hc05_only.tcl
./tools/run_sim.ps1 -Tests tb_hc05_decoder_equivalence,tb_song_time_bound,tb_top_hc05_only
```

同条件快照复核（使用尚未存在的新标签；旧快照仅保留在本机）：

```powershell
./tools/check_resources.ps1 -Label hc05_after_recheck -ReferenceLabel hc05_final
./tools/check_resources.ps1 -Label hc05_before_recheck -ReferenceLabel hc05_final -OverlayLabel hc05_before -OverlaySource top.v,hc05_keymap.v,downloadable_song.v,PCM5102_PAM8403.sdc
```

以上脚本均不烧录。重新启用备用 USB 硬件还需恢复仅指向 `legacy_pcm.u_audio_record/cts_meta*/D` 的 CTS 第一级同步器约束，重新综合、布局布线和验收，不能复用本配置的时序结论。
