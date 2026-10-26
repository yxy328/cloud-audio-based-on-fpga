# B1：12键半音阶与四个临时高音踏板条

> 2026-10-26 后续评估：[D/E/B2逐项结果](reports/performance_experience_20261026/REPORT.md)。完整曲谱弯音候选未满足35 CLS安全余量，未接入；完整B2依赖未满足，仍保留七键MAP/曲谱指引和K13～K16高音键。没有完整B2构建，不能据此断言所有B2方案放不下。

> 2026-10-26 固定十六键：当前统一工程上电即串行十六键，删除八键输入和 App 切换入口。`TOUCH,8` 返回 `ERR,RANGE`；键盘未就绪时可在空闲状态用 `SERIAL,0/1` 修正极性。以 [当前操作与协议](TOUCH16.md) 为准；下文八键及旧版构建说明保留历史用途。


2026-10-21。器件 GW5A-LV25MG121NC1/I0，工程 `PCM5102_UNIFIED.gprj` / `top_unified`。
本阶段保留 MAP 键号1～7、七通道曲谱 / 指引、现有弯音与协议；不改显示或 RAM 几何。

## 唯一扫描与物理键位表

用户在本次会话明确确认“K1=白1、K2=黑1、…、K13=踏板1”，即K1～K12依次为半音阶、K13～K16依次为四个踏板条。
此表以该接线确认为依据，不是由FPGA的SCL / SDO引脚推导。白键、黑键分别从左到右编号。

| TTP229扫描序号 | 物理焊盘 | 默认音名 | MIDI | 理论Hz | DDS步进 | 实机测频 |
| --- | --- | --- | --- | --- | --- | --- |
| K1 | 白1 | C4 | 60 | 261.625565 | 23012828 | 待上板 |
| K2 | 黑1 | C#4 | 61 | 277.182631 | 24381242 | 待上板 |
| K3 | 白2 | D4 | 62 | 293.664768 | 25831026 | 待上板 |
| K4 | 黑2 | D#4 | 63 | 311.126984 | 27367019 | 待上板 |
| K5 | 白3 | E4 | 64 | 329.627557 | 28994347 | 待上板 |
| K6 | 白4 | F4 | 65 | 349.228231 | 30718440 | 待上板 |
| K7 | 黑3 | F#4 | 66 | 369.994423 | 32545054 | 待上板 |
| K8 | 白5 | G4 | 67 | 391.995436 | 34480283 | 待上板 |
| K9 | 黑4 | G#4 | 68 | 415.304698 | 36530588 | 待上板 |
| K10 | 白6 | A4 | 69 | 440.000000 | 38702809 | 待上板 |
| K11 | 黑5 | A#4 | 70 | 466.163762 | 41004198 | 待上板 |
| K12 | 白7 | B4 | 71 | 493.883301 | 43442435 | 待上板 |
| K13 | 踏板1 | C5 | 72 | 523.251131 | 46025656 | 待上板 |
| K14 | 踏板2 | D5 | 74 | 587.329536 | 51662052 | 待上板 |
| K15 | 踏板3 | E5 | 76 | 659.255114 | 57988693 | 待上板 |
| K16 | 踏板4 | F5 | 77 | 698.456463 | 61436880 | 待上板 |

计算式：`round(440 × 2^((MIDI−69)/12) × 2^32 / 48828.125)`，Fs为50MHz / 1024。
“误差为零”指仿真的实际相位步进与上述取整结果一致，不表示实物晶振、DAC或测频没有误差。
16个音不是16个连续半音：前12个是C4～B4，另外4个明确为C5 / D5 / E5 / F5。

## 固件与协议边界

- `hc05_keymap.v` 的 DEFAULT_MAP 改为扫描K1～K7对应的 `60,61,62,63,64,65,66`。
- K1～K7继续经过既有MIDI LUT、FSR比率与逐声部弯音通路；K8～K16的两处发声路径共用 `touch_tdm_synth.note_step()` 的新常量。
- `midi_note_lut` 的BLOCK_ROM模式、60～72输入范围、字宽、存储端口与时序不变。K14～K16的临时高音在既有高键常量函数内，不扩大MAP范围。
- `MAP?` 上电及 `MAP_RESET` 后读回 `MAP,60,61,62,63,64,65,66`。`MAP_RESET` 的回复仍为 `OK,MAP_RESET`；没有新增命令或回复模板。
- 8键直连模式共用前七键默认表，因此也改为C4～F#4；K8仍切压力用途。完整12键钢琴演奏使用16键串行模式。
- 只有前七个**扫描键**可重映射和逐声部弯音，其中包含三个黑键；不等于七个白键。
- 曲谱、AUDITION与HUB75指引仍只有七个映射通道。C大调曲库需要使用现有“匹配七键并下载”；它可能改动前七键的默认半音阶，恢复钢琴默认演奏前应执行MAP_RESET。

四个踏板条当前都是普通高音键。B2才评估踏板功能、12键可映射、更多指引通道等；B2仍依赖C / D及资源决策，不能把本轮普通高音条理解为已经实现延音 / PANIC / 八度移。

## App与手机录制

版本为 **Code17 / 1.16-chromatic**，Gradle和Manifest同步递增。

- 手机琴键使用七个全高白键与五个较窄、半高黑键；黑键分别跨在白1/2、2/3、4/5、5/6、6/7之间，四个高音条在右侧独立一列。
- 每个按钮标注扫描K号；触摸回调仍使用扫描索引，不按绘制顺序重排事件。真实Button保留多指分发与无障碍点击入口。
- 七键映射编辑先选K1～K7，再点图形琴键填入MIDI；原文本输入保留为高级入口。可选范围仍是60～72，后三个高音条在该编辑器里禁用。
- 手机本地发声与MIDI导出使用同一张16键音高表。手机录制仍是音符事件，不是音频。
- 旧手机文件PTK1只存扫描索引，固定含义是原自然音阶；新文件PTK2在文件头保存16项MIDI音高快照。载入旧文件时按其原版本音阶解码，改名保存后写入带快照的新格式，回放与MIDI不会被全局默认表改变。CRC和原子保存继续生效，读失败不删除原文件。

## 资源与布局布线

改动前93份RTL / 约束 / 工程输入的SHA256全部匹配 `pedal_final_constraints_20261021` 冻结快照，以下为同工具、同器件、50MHz、布局2 / 布线0 / 最大扇出23的PnR报告口径。

| 资源 | B1前 | B1后 | 增量 |
| --- | --- | --- | --- |
| Logic / 23040 | 20939 | 20967 | +28 |
| LUT | 17223 | 17256 | +33 |
| CLS / 11520 | 11055 | 11053 | −2 |
| Register / 23280 | 10039 | 10039 | 0 |
| BSRAM / 56 | 44 | 44 | 0 |
| DSP / 28 | 26.5 | 26.5 | 0 |

Logic增量28≤60、CLS增量−2≤10，符合B1预算。余Logic2073、CLS467、BSRAM12、DSP1.5；后续B2与E的整体预留仍未闭合，见[方案审查](SIDEBAR_REVIEW.md)，本轮不据此批准后续全部功能。

Fmax由51.236MHz变为 **52.026MHz**；主时钟及ADC时钟的Setup / Hold违例端点均为0。
工具完成全量布局、布线、位流生成，日志没有未布通或ERROR；输出可用 `.fs`。ADC时钟无可计算Fmax的路径，不另报其Fmax。
本次没有烧录。

冻结快照：`sim/build/unified/chromatic_b1_20261021/`；最终RTL与该快照的输入哈希一致。
位流UserCode：`0x000015CD`，SHA256：`E40B7502ADC87A6A9F1B0435002E0419D07FD6D618E7ABB58789B40F10E74DFC`。
APK SHA256：`1675EF87CCC5FEFB9C1DD0658B2B745758438B72C611628ABA8F8FA92635A888`。

## 验证与复现

已完成：

- `tb_touch_tdm_synth`：16个声部连续32帧的实际DDS相位差与A440公式取整结果逐项相等；4096采样的G4～F5扩展声部频谱、独立包络快照 / 释音、共享变调及帧期限通过。
- `tb_hc05_keymap / bend / adsr / control_races`：新默认MAP读回、MAP_RESET、所有键号及13个合法音高、原有控制边界与竞态通过。
- `tb_hc05_decoder_equivalence`：512次UART差分通过；冻结参考源码不改，新旧默认映射单独断言，其余控制、回复和脉冲继续比对。曲谱夹具使用两套默认映射都覆盖的音集。
- `tb_hc05_download`：显式设置原C大调映射后核对既有曲谱下载、原子提交、缺音拒绝、录制日志与锁定，避免把旧默认表混入新功能断言。
- `verify_ram_geometry.ps1`：正弦ROM、上下文、弯音RAM、FIFO、ADSR、八音色与生产者队列全部通过；RAM几何和BSRAM占用不变。
- Android核心回归和APK编译 / 签名 / 版本验证通过；77项ChromaticKeys断言覆盖扫描音高、黑白键位置与16个MIDI输出；PhoneTake包含旧PTK1回放 / 改名后的原音保持、新黑键MIDI、PTK2音高快照与非法音高拒绝；全部曲库均从新默认七键完成匹配校验。

顶层回归已完成：

- `tb_top_touch16 -Quick`：8192个外部I²S采样检出全部16个新音高；直连隔离、忙保护、锁存 / PANIC、K16、压力控制、高有效串行极性与返回GPIO通过。
- `tb_top_pedal -Quick`：80ms加速尾音、相位连续、抬踏板隔离、再踩、最旧尾音抢占、物理键优先、16音无削顶 / 超时、清态通过；最坏帧1011/1024时钟。没有把本次80ms顶层测试表述成1200ms实物验收。
- `tb_top_audition -Quick`：显式七键映射后的UART启动、静默预备、三 / 七声部外部I²S、重复音 / 休止 / 结束、STOP保留实按音与缺音拒绝通过。

本轮按B1范围运行上述相关回归，没有重复完整的旧GPIO演示混音频谱测试；其默认频率断言已同步，GPIO切换与恢复由16键顶层回归覆盖。
顶层串行队列在16键和踏板两项通过后停止剩余队列；自动演奏已在独立进程通过。组合进程的停止返回码不作为整组通过证据，最终核对逐项完成日志。
组合控制日志保留首次默认音集夹具不匹配的失败记录；修正夹具后，512次差分和下载已在 `b1_control_completion.log` 重新通过，最终逐项结果以对应 `tb_*` 日志和 `b1_final_validation.json` 为准。

最终产物：

- [B1位流](impl/pnr/PCM5102_CHROMATIC_B1.fs)，同时同步到标准 `impl/pnr/PCM5102_UNIFIED.fs`。
- [Code17 APK](android_app/dist/FPGA-Music-Chromatic.apk)，与标准 `android_app/dist/FPGA-Music-Unified.apk` 相同。
- 资源 / 时序报告已同步到 `impl/pnr/`，包括主HTML及其 `_tr_content.html` / `_tr_cata.html` 支持文件；综合报告和网表同步到 `impl/gwsynthesis/`。

复现命令（项目目录）：

```powershell
& ./tools/run_sim.ps1 -Quick -Tests @('tb_touch_tdm_synth','tb_hc05_keymap','tb_hc05_bend','tb_hc05_adsr','tb_hc05_control_races','tb_hc05_decoder_equivalence','tb_hc05_download')
& ./tools/run_sim.ps1 -Quick -Tests @('tb_top_touch16','tb_top_pedal','tb_top_audition')
& ./tools/verify_ram_geometry.ps1
& ./android_app/test-core.ps1
& ./android_app/build-apk.ps1
python ./tools/generate_hc05_decoder.py --check
python ./tools/generate_hc05_replies.py --check
& ./tools/check_unified_build.ps1 -Label chromatic_b1_rebuild -SynthesisOnly
& ./tools/resume_unified_pnr.ps1 -Label chromatic_b1_rebuild
```

本机脚本策略受限时，在新PowerShell进程加 `-NoProfile -ExecutionPolicy Bypass`，不更改系统策略。
构建日志：`sim/build/b1_synthesis.log`、`b1_pnr.log`；RTL日志：`b1_control_regression.log`、`b1_control_completion.log`、`b1_ram_verification.log`、`b1_top_regression.log`、`b1_audition_regression.log`；App日志：`android_app/build/chromatic-core-test.log`、`chromatic-apk-build.log`。

## 实机验收待办

- [ ] 烧录配套B1位流并安装Code17，16键串行模式逐键确认扫描号与本表一致。
- [ ] 按白1、黑1、白2、黑2、白3、白4、黑3、白5、黑4、白6、黑5、白7顺按，听取连续C4～B4。
- [ ] 四个独立条分别得到C5 / D5 / E5 / F5，不是本轮踏板功能。
- [ ] PCM5102耳机口对录，用Audacity逐键测谱峰，将实测Hz和偏差补入上表；不以仿真替代对录。
- [ ] 新MAP? / MAP_RESET、七键图形编辑、曲库匹配下载、恢复默认半音阶、原有弯音和FSR音高叠加。
- [ ] 手机黑白键多指、按键释放 / 取消、旧录音原音回放、新录音保存与MIDI、无障碍点击、灰度与屏幕边距。
