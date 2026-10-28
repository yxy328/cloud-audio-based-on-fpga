# 十二键音游交付：Code41

用户确认玩法种类和外观两种都需要。本轮已接入默认工程及 App **1.40-rhythm / Code41**：十二列跟随自定义映射，单点/和弦/重复音/长按计分，得分、连击、最高连击、Miss，薄音符、三主题及击打反馈。没有安装 App、烧录 FPGA 或写板上 Flash。

## 产物与使用

- [音游操作说明](../../RHYTHM_GAME.md)
- [Code41 APK](../../android_app/dist/FPGA-Music-Rhythm-Code41.apk)，与默认 Unified.apk 字节一致。
- [配套码流](PCM5102_UNIFIED_RHYTHM_CODE41.fs)，与默认 impl/pnr/PCM5102_UNIFIED.fs 字节一致。
- [设计/协议/边界](DESIGN.md)、[构建与测试审计](build_audit.json)、[发布和回退指纹](release.json)。

APK SHA256：`32B3D7C577C9AB1DBC10D7EDCDDF21D9A375148DFBABD322A214178660F8E98E`。

位流 SHA256：`F7B89654B8F653A639130F6B8C46BD4E9F9F150E460DE30EAECF7C7BB13C4D67`。

## 实际资源与时序

最终标签 `rhythm_game_release41`，GW5A-LV25MG121NC1/I0、Gowin 1.9.11.03、50 MHz、sharing/retiming 开启、place2/route0/fan23。原约束和引脚保持；存储配置保留 native 32/36 位块，不再强制拆成 16/18 位。

| 资源 | Code40 | Code41 | 剩余 |
|---|---:|---:|---:|
| Logic / 23040 | 22732 | 22542 | 498 |
| CLS / 11520 | 11482 | 11426 | **94** |
| Register / 23280 | 11225 | 11525 | 11755 |
| BSRAM / 56 | 56 | 54 | 2 |
| DSP / 28 | 25 | 25 | 3 |

净回收 **56 CLS**；保留此前要求的35 CLS后，仍可用59。完整布通、未布通0；主时钟和 ADC 时钟 setup/hold 违例端点均为0。原始最差 setup/hold slack **+0.246/+0.149 ns**。工具完成位流生成；以上为同一最终候选的实际结果，不把其他失败候选的收益叠加。

## 验证

十一组最终 RTL 检查、App 全部核心回归、新 APK 编译/签名/版本核对通过，界面素材与 Code40 相同。最终路由网表另验证40组外部扫描行：64列、133主时钟行周期、已知RGB和消隐/LAT顺序。它是启动/扫描检查，不是全游戏门级仿真。

重点证据：

- 四档正负窗口边界及超界、过期时间戳、重复键不刷分、和弦、长按/断按、STOP、清零、128条满分 **192000** 和128连击。
- 外部 RGB5/PWM 的薄头、长按色、保持标记、180 ms 闪光与数字；独立64行模型覆盖6500 ms回绕、994个密集头部、8次清行反压、停止/重新清图。
- UART下载及设置、真实TTP229串行模型按K1/K12、点按+休止+长按得到2500分，AUDITION排除、外部I2S和音频期限检查。
- 传感器暂存逐周期对照150000拍、1778个原子事件、1710次同址转发、1029个满队列周期，队列/溢出/PCM完全一致；按键上报逐周期对照100000拍，覆盖1124条消息和38978次背压。
- 十二路密集128×1ms曲谱；43/33字段 TAKE 兼容与原子恢复；528位三效果原子快照。
- 额外通过旧 HUB75 RGB5/下落和波形/XY/FFT切页回归、UART 256字节及波特率容差、八音色、共享算术1668帧以上对照。日志保存在候选 sim/build；最终11项索引和哈希见审计。

曾启动的早期完整9600-baud门级查询测试因期望夹具误写成33字节而中止，已修正测试源，但不计为完整UART门级PASS。最终扫描网表检查和真实UART的RTL整机检查分别列报，不相互替代。实物触摸延迟、LED观感、手机界面/蓝牙及DAC听音仍待用户实机验收。

## 复现与回退

在 pcm5102_pam8403 中运行：

```powershell
& ./tools/test_rhythm.ps1 -RoutedScan
& ./android_app/build-apk.ps1 -OutputApk dist/FPGA-Music-Rhythm-Code41.apk
& ./tools/check_unified_build.ps1 -Label <新标签> -SynthesisOnly
& ./tools/resume_unified_pnr.ps1 -Label <新标签>
```

构建脚本会冻结当前工程 process_config；请保留 `Convert_SDP32_36_to_SDP16_18=false`。源码中的四张音游 ROM 由 `tools/generate_rhythm_tables.py` 生成，可加 `--check` 核对。

[rollback_Code40](rollback_Code40/) 保存本轮覆盖的原源码、配置、文档、默认APK/码流和生成报告；发布指纹记录所有备份及新入口的SHA256。回退时先停止使用新App，按记录恢复被覆盖文件，移除本轮新增入口，再配套使用原Code40 APK/码流。原Code40命名交付也仍保留。本轮没有Git提交。

中间实验在 candidate 下按标签保留。首版83等效逻辑未放置；共用shader/较早RAM候选超综合上限；字体候选在默认拆分配置下需57块RAM；native-wide首个候选只余5 CLS；后续20/13 CLS候选未达安全余量；传感器RAM/有效数据版本曾有235/236条未布通，一组place1仍有224条未布通。清图握手的未完成中间快照和合成编码试验均未发布。最终采用独立初始化/清行、同步计分ROM、native-wide存储与明确同址转发。
