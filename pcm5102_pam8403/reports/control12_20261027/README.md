# 十二路控制交付（2026-10-27）

已接入默认工程与 App **1.39-control12 / Code40**。K1～K12 支持映射、独立弯音、曲谱弯音、自动演奏和十二列指引；K13～K16 保留高音，十六键发声保留。未安装 App、烧录 FPGA 或写板上 Flash。

| 资源 | 本轮用量 | 剩余 |
|---|---:|---:|
| Logic | 22732 / 23040 | 308 |
| CLS | 11482 / 11520 | 38 |
| Register | 11225 / 23280 | 12055 |
| BSRAM | 56 / 56 | 0 |
| DSP | 25 / 28 | 3 |

相对Code39净增 **43 CLS**，余量从81降至 **38**，保留35后仍可用 **3**。50 MHz，sharing=1、retiming=1、place2/route0/fan23；未布通0，setup/hold违例0/0，原始WNS **+0.478/+0.188 ns**。资源增量以 `build_results.json` 的 Code39基线到本轮最终物理结果计算，不叠加中间候选成本。

## 产物

- [Code40 APK](../../android_app/dist/FPGA-Music-Control12-Code40.apk)，SHA256 `4F5D1253B597F03780C11000913BEB037E4031CF98AE7D98F393EC812E71379C`。
- [配套码流](PCM5102_UNIFIED_CONTROL12_20261027.fs)，SHA256 `2B25F84FCACB428BBD26127BC4C4A1527CC3039E64DEFFBEA03D9B353E307BE2`。
- [用法](../../CONTROL12.md)、[设计与兼容边界](DESIGN.md)、[构建记录](build_results.json)、[最终回归与源指纹](final_verification.json)、[验证日志索引](verification.json)、[本轮交付指纹](release.json)。
- 标准 `android_app/dist/FPGA-Music-Unified.apk` 与 `impl/pnr/PCM5102_UNIFIED.fs` 已同步，并分别与命名文件逐字节核对。
- [Code39 回退目录](rollback_Code39/) 保存了本轮覆盖的原源码/配置、旧滚动 APK 和旧默认码流。原 Code39 命名交付仍保留。
- [交付核对](post_release_check.json)确认所有安装文件与测试候选一致、命名与默认产物同指纹，Code39备份与原始冻结指纹一致；默认路径的App核心回归也已通过。

## 验证与边界

十二键逐键十三个合法音高、两位键号、全部 BEND 地址、严格边界和旧七路协议通过。十二路扫描验证 1024 步滑音、单位/端点、独立声部、压力叠加与回正；曲谱验证 128×1 ms 密集十二键/休止/弯音和完整指引、128×60000 ms 上限、原子双 bank、STOP/重启及失败保留旧谱。

整机测试核对 84 个精确音高结果、24 条 UART 交互、十六键、十二列外部屏幕时序、外部 I2S 协议/余量/音频帧期限、曲谱目标与手动恢复。TAKE 验证旧33字段/新43字段兼容、原子捕获、缺字段拒绝，并经过真实 RTL 顶层 UART 录制/停止/回放和 K8/K12 实际 DDS 音高恢复。通用 TAKE 和原528位三效果原子快照回归通过。

Android 核心回归、新增十二键导入/匹配/拒绝/弯音 CSV 检查、APK 编译、版本和签名通过。与 Code39 的十项素材逐项一致，签名证书保持。数字仿真和时序报告不替代手机、蓝牙、板上烧录及 DAC 听音验收。

最终位宽优化对照旧引擎：音量移位0/4/18及快速读四组共768帧逐位一致，覆盖16路相位/包络/年龄/踏板/复音/旧格式回退，普通/快速读最忙1011/819拍（1024拍期限）。实时按键上行逐周期对照旧实现100000拍，覆盖满FIFO、回绕、停发、复位和UART背压。最终23组RTL检查及源指纹见 final_verification.json；资源或时序未达标的中间RAM原型均未采用。

复现：`tools/test_control12.ps1` 运行23组RTL与App核心检查；新建唯一标签后执行 `tools/check_unified_build.ps1 -Label <label> -SynthesisOnly` 和 `tools/resume_unified_pnr.ps1 -Label <label>`。原始冻结输入、全部候选与失败记录均保存在本目录。
