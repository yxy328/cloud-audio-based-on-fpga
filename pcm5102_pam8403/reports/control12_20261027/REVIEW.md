# 十二路控制优化前的评审记录

> 已按用户要求保留35 CLS并完成优化，当前Code40默认交付余38 CLS、预留后可用3。正式APK、码流和完整验证见[交付报告](README.md)。以下保留优化前的实验记录。

当时已实现完整十二路控制并完成全量布线及50 MHz时序验证，通过候选为 `control12_shared_reply`。

| 项目 | Code39基线 | 十二路实验版 | 变化/余额 |
|---|---:|---:|---:|
| Logic | 22453 | 22826 | +373，剩214 |
| CLS | 11439 | 11505 | +66，剩15 |
| Register | 10783 | 11291 | +508 |
| BSRAM | 55 | 56 | +1，剩0 |
| DSP | 26.5 | 26 | -0.5，剩2 |

未布通0，setup/hold违例0/0，原始 WNS +0.035/+0.159ns。原先预留35 CLS后可用46；本候选净增66，距该预留要求差20 CLS。当前默认仍为 Code39，实验版尚未被设为默认。

- [实验APK：Code40](FPGA-Music-Control12-Experimental-Code40.apk)
- [实验配套码流](PCM5102_UNIFIED_CONTROL12_EXPERIMENTAL_20261027.fs)
- [设计、协议和旧TAKE兼容](DESIGN.md)
- [全部构建结果](build_results.json) · [功能验证索引](verification.json)

K1～K12 支持映射、独立弯音、曲谱弯音、自动演奏及十二列指引。K13～K16保留高音键、触摸引擎保留16音。曲谱128条/单条60000ms、TAKE1024个差分事件保持；新字段会增加实际事件消耗。

通过项目包括十二键逐项13个音高、两位键号、全部BEND地址、1024步滑音/压力叠加、128条密集曲谱、84项整机音高与24条UART交互、屏幕/I2S输出、旧33字段/新43字段TAKE、UART录制后K8/K12弯音和K16高音恢复，以及对实际Code39七路配置的512事务差分。APK完整核心回归、编译验签与版本通过，十项素材及签名证书保持。

本实验码流的确切源码位于 `candidate/pcm5102_pam8403/sim/build/unified/control12_shared_reply/pcm5102_pam8403/src/`。candidate/src 中另有尚在综合/布线的后续微调，请按每个冻结构建的 sources.json 区分。

没有安装App、烧录FPGA或写实物Flash；数字仿真不替代手机/蓝牙/模拟音频验收。请配套使用APK和码流；新版可以读取旧TAKE，十二路新TAKE由新版固件回放。

## 同源物理策略复核

| 策略 | 剩余CLS | 布线/时序结果 |
|---|---:|---|
| place2 / fan23 | 15 | 全布通，50MHz setup/hold均通过 |
| place1 / fan23 | 27 | 214条未布通，淘汰 |
| place3 / fan23 | 23 | 9个setup违例，原始WNS -1.931ns，淘汰 |
| place2 / fan32 | 15 | 全布通及时序通过，资源收益0 |

仅裁去未用兼容回复分支的后续候选实际余17 CLS且时序失败，未采用。最终采用的 `control12_width_final` 余38 CLS、完整布线且50 MHz时序通过；资源优化和音频逐位对照详见[设计说明](DESIGN.md)。
