# 四档回声优先版：仿真与构建交付

> **APK已停用：本冻结包内为有回复识别缺陷的Code22，请勿安装。** 当前请使用 [Code24独立APK](../../android_app/dist/FPGA-Music-LinkDiag-Code24.apk)，安装后设备页应显示Code24。位流、资源和时序的历史记录保持；连接修复与实机边界见 [HC05_CONNECTION.md](../../HC05_CONNECTION.md)。

2026-10-22。用户确认实物尚未接好，本轮先交付仿真与构建结果。没有烧录、安装手机或耳机口对录；不将仿真结果记为实物验收。

保留84 /168 /336 /504 ms四档回声，长三档仅湿声降采样，干声与原84 ms档保持原样。C7移调 /A4缩为红外与手势共享，16触摸键与吉他保持原音高。弯音范围、滑音时间、共享颤音及整体起振等待保留；合唱速率固定，震音与律制未启用。范围与协议以仓库根目录 [PERFORMANCE_PARAMS.md](../../PERFORMANCE_PARAMS.md) 为准。

## 文件

- [PCM5102_UNIFIED.fs](PCM5102_UNIFIED.fs)：GW5A-LV25MG121NC1/I0，UserCode **0x0000589C**，已同步仓库 `impl/pnr/PCM5102_UNIFIED.fs`。
- [FPGA-Music-Unified.apk](FPGA-Music-Unified.apk)：Code22 /1.21-echo，已核对签名与Manifest版本。
- [PnR五项资源](PCM5102_UNIFIED.rpt.txt)、[时序报告](PCM5102_UNIFIED_tr_content.html)、[构建日志](BUILD.log)。
- [RELEASE.json](RELEASE.json)：资源、预算增量、Fmax、位流与APK指纹、验证状态。
- [RTL_SOURCES.json](RTL_SOURCES.json)：94份最终构建输入的SHA256；App与协议审计清单见本目录JSON文件。
- [verification](verification/)：相关仿真日志、额外全量回归的时点快照；[SHA256.json](SHA256.json) 校验本包文件。

## 资源与范围

| Logic | CLS | BSRAM | DSP | Register | Fmax |
| --- | --- | --- | --- | --- | --- |
| 21088 | 11060 | 44 | 26.5 | 10239 | 50.096 MHz |

相对B1，阶段C新增 **121 Logic /7 CLS /0 BSRAM /0 DSP /200 Register**，低于400 Logic /100 CLS预算。setup /hold违例端点均0，无未布通报错。剩余1952 Logic /460 CLS /12 BSRAM；后续D、B2、E100和安全垫共需1650 /365 /4，仍保留302 /95 /8余量。

新参数六个相关仿真、默认逐时钟对照、RAM几何检查及App核心测试通过，PerformanceParams含8690项检查。四档脉冲延时、长档有符号低通、70000默认帧及相位回绕、81次实际UART回复、32传感器调律与16触摸键原音均有仿真记录。

额外107项RTL全量回归继续在独立目录运行，尚未全部通过；交付包保留打包时点快照，不随后台结果变化。实时状态见仓库 `sim/build/regression_20261022/results.json`，每项日志保存在对应worker目录。外部GPIO读取器用例另已通过。实物对录、手机布局和蓝牙实机联动仍待接线后验收。

长档前端一阶低通会进一步衰减高频，最长档湿声采样上限约4.07 kHz，存在残余混叠与保持波形。切档清旧尾音。TAKE不保存新增参数，录制和回放前需使用同一套移调、颤音和回声设置。

## 指纹

- 位流：`E236EB634F02FB24B93E004C9AA5B68229D1E693EE5D678AAD173DE232F97EDE`
- APK：`BEF1A3F01945BF32D283B1EF4988A58D2D27793B797A19D4B6AFA46EB5E4226A`

旧B1与C7候选的独立文件和冻结构建保留，不含本版四档回声；默认烧录脚本当前使用本版标准输出。
