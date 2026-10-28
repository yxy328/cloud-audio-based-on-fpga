# 单曲扩到256条：Code46

2026-10-28，App **1.45-score256 / Code46**。单首曲谱由128条扩到 **256条事件**，音游、下落指引、自动演奏和CSV/MIDI导入使用同一上限。曲谱条数表示音符/和弦/休止事件，实际秒数取决于节奏，并非固定播放时间。

- [Code46 APK](../../android_app/dist/FPGA-Music-Score256-Code46.apk)
- [Code46 配套位流](PCM5102_UNIFIED_SCORE256_CODE46.fs)
- [最终资源、时序与产物指纹](release.json)
- [曲库实际加长对照](library_delta.json)

**超过128条需要本版FPGA与App配套更新。** 旧位流仍只接受128条；128条以内格式保持兼容。本轮未安装手机或烧录开发板。

## 曲库实际变化

保留120首及原有曲目ID，三个等级各40首。新增来源中的19首现在保留原谱反复，13首超过旧128条容量；最长252条，时长从此前最长68.571秒提升至 **103.571秒**。这是增加实际旋律内容，并非仅放慢速度。原九首保持不变；音域仍为MIDI60～72，跨度过宽的曲子继续明确标注节选，不折叠八度。

## 实现与资源

曲谱RAM由两个128条暂存/活动区扩为两个256条区，47位事件格式不变。物理映射仍为 **2块BSRAM**，整机仍54/56块，DSP仍25。寻址扩大一位、事件数量用9位表示，最长时间轴扩大到24位。

下载开始时清空暂存区，时长0表示“未写入”，取代原128位写入标记及选择逻辑。清空与正常下载共用一个物理写端口，最多256个主时钟（50MHz下约5.12µs）；`SONG_BEGIN`完成清空后才回OK。乱序写入、重复覆盖、漏写检查、失败保留旧有效曲谱和双缓冲原子提交均保留。不是把写入标记扩大到256位；计入最终频谱时序修正后，综合寄存器仍由11624降为11512。

音游连击、最高连击和Miss均扩到256，满分384000。计分ROM保存“千位组”，末三位由奇偶直接组成000/500，避免把24位整分值ROM扩成1024条而额外占用BSRAM。统计ROM同样利用已有物理块的空余深度。

最终布局布线数字、50MHz setup/hold余量和SHA256以[release.json](release.json)为准。候选保存在 `sim/build/unified/score256_46e`，原始综合、路由和时序报告在该目录中；没有为通过检查降低时钟频率。

首轮a完整布通，但频谱显示原有的“频段解码→80位选择→比较→写使能”路径出现30个setup违例，最差-0.963ns，没有交付。最终e在已有MAG_SCALE阶段寄存所选柱形的5位前值，MAG_ACCUMULATE只比较寄存值，FFT总周期不变；[逐拍原实现对照](spectrum_equivalence.log)覆盖全部累加频段以及静音、单音、双音、抗混叠场景，数值、柱形与发布时间均一致。最终整机综合Logic22589、Register11512、BSRAM54，均在器件内。仅布局策略候选b/c已停止；候选d寄存频段编号后被工具展开成更多逻辑，综合23082超过23040，均未交付。独立模块面积对照见`spectrum_*_audit.log`。

## 验证

- [底层RTL](unit_rtl.log)：128条兼容、256×60000ms最长时间轴、显示回压后无回绕、弯音存储、四类判定、256连击/256 Miss和384000分。
- [综合集成回归](integration_rtl.log)：乱序写入、128/255边界、漏写与旧谱保留、全部256条按时播放、清空中取消、协议/触摸/四类音符、自动演奏、I²S与曲谱配置。
- [串口256条端到端](uart256.log)：265条回复；三位数数量/索引、逆序上传、256条类型/弯音RAM字段逐项核对、257条拒绝、自动演奏/STOP和失败原子性。
- [App核心回归](core_tests.log)：全部通过，曲库85496项断言、CSV/MIDI与弯音/类型元数据256条上限，257条明确拒绝。
- [曲库重生成](library_reproducibility.log)：从保留的111个ABC重新生成，Java及目录SHA256完全一致。
- [APK构建](apk_build.log)：Java/D8/aapt2、Code46版本与签名验证；[附加校验](apk_checks.log)核对对齐及覆盖安装证书。
- [路由网表扫描](routed_scan.log)：最终路由网表40组外部RGB行扫描，检查64列、133时钟行周期、像素已知和消隐/LAT顺序。它是启动扫描检查，未把整局256条游戏当作门级仿真通过。

`rollback_Code45/`保留本轮修改前的源码、曲库、APK和默认位流；旧APK与位流都可回退。未进行Git提交。源码中已有的用户改动保留。

复现：

```powershell
./tools/run_sim.ps1 -Quick -Tests @('tb_score256','tb_hc05_score256','tb_song_time_bound','tb_rhythm_game')
./android_app/test-core.ps1
./android_app/build-apk.ps1 -OutputApk dist/FPGA-Music-Score256-Code46.apk
./tools/check_unified_build.ps1 -Label <新标签> -SynthesisOnly
./tools/resume_unified_pnr.ps1 -Label <新标签>
```
