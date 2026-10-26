# 固定十六键生产交付（2026-10-26）

已将去掉 TTP229 八键模式的方案接入生产 RTL，完成对应默认码流和 App v1.25-touch16 / Code26。保留旧默认构建与原滚动 Code25 APK，未烧录 FPGA、未安装手机、未做模拟音频对录。三效果原型未接入，既有回声/合唱仍按原实现工作。

## 行为与实施

- 上电固定十六键串行，删除两组旧 GPIO 读取/同步/去抖模块；十六个声部和后续混音保留。CTRL/CTRL2 模式字段恒为 1，TOUCH8 返回 ERR,RANGE；TOUCH16 保留就绪与空闲检查。K8 作为音符，压力用途由手机选择。
- 删除 SDC 中只指向旧 GPIO 同步器的两条 false_path，其余时钟及异步输入约束保留。
- 补上固定十六键后的极性恢复路径：原 SERIAL 写入也依赖键盘 ready，错误极性可导致无法更改；现在只对此命令取消 ready 要求，仍检查音符、曲谱、下载、录制和延音忙状态。其他编辑命令仍使用原 ready 门槛。
- App 删除模式选择、相关草稿绑定和生成 TOUCH8 的路径；删除旧 REC 日志的一键八键配置，保留历史日志查看/导出及手机 MIDI、板上 TAKE。仍回读真实设备状态，连接旧八键固件时明确提示更新。
- 最初尚未修正 SERIAL 恢复条件的中间构建/仿真被主动停止；日志及当时 PCM/VVP 保存在 intermediate_before_polarity_recovery，不计作通过。正式构建和以下测试全部基于修正后的源码。

## 完整生产资源与时序

| 资源 | 原生产 | 当前生产 | 净回收 | 剩余 |
|---|---:|---:|---:|---:|
| Logic | 21649 | 21514 | 135 | 1526 |
| CLS | 11183 | 11199 | -16 | 321 |
| Register | 10579 | 10416 | 163 | 12864 |
| BSRAM | 47 | 47 | 0 | 9 |
| DSP | 26.5 | 26.5 | 0 | 1.5 |

相同 Gowin 二进制、50MHz、resource_sharing=1、retiming=1、place2/route0/maxfan23。未布通 0；setup/hold 违例端点 0/0，原始路径 WNS +0.146/+0.194 ns。
最终净省 135 Logic、163 Register，CLS 比原生产增加 16，BSRAM/DSP 不变。本次接口变更已经完成，但没有获得 CLS 净回收，不能把它当作释放了 14 CLS 的方案。
当前结果包含 SERIAL 未就绪恢复修正，不能直接套用前轮仅删除八键的 197 Logic/14 CLS，或把不同组合的节省相加。尚未完成的 D/B2/E100 与安全垫仍按 1650 Logic/365 CLS/4 BSRAM 规划；本次只交付删除八键及必要恢复路径，不宣称完整三效果或后续预留已经满足。

101 项生产源码/ROM/约束/工程/构建脚本在正式构建前后哈希一致；相对原生产只有 hc05_keymap.v、top.v、PCM5102_UNIFIED.sdc 三项变化。实际综合网表工程、cmd.do、device.cfg、资源报告、时序 HTML 和 timing_paths 指纹见 production_audit.json。

## 验证

- tb_top_touch16：真实 UART/TTP229 引脚、默认十六键、GPIO 隔离、按住和空闲时 TOUCH8 拒绝；全部十六个音高的 8192 样本 I2S 频谱，HOLD/PANIC、K16、远程压力用途、传感器重置后高有效配置、校准 BUSY 和就绪后重试。整条用例最终 PASS。频谱幅值记录在 functional_results.json，原始解码 PCM 独立保留。
- tb_top_touch16_recovery：传感器从上电即为高有效、FPGA 默认低有效，未就绪时通过真实 UART 接受 SERIAL1，恢复全部十六键，同时验证演奏忙时拒绝改变极性和 TOUCH8 拒绝。
- tb_hc05_extensions：47 个逐字节 UART 回复，覆盖未就绪恢复、音符/曲谱/录制忙保护、只读十六键状态、非法命令原子拒绝、旧音效/音量/模拟控制及 PANIC。
- tb_top_idle、tb_top_dual_analog：生产参数启动静默；压力与 ADS1115 滑杆同时作用及故障回退。全频谱用例 FSR 关闭、使用 500k UART、100µs 启动及短 ADSR；双模拟通道单独验证，未冒充全部传感器/Flash/回放联合实物验收。
- Android 完整核心测试、APK 构建、Code26 Manifest、签名验证通过，签名证书与原滚动 APK 相同。核心脚本读取的旧 RTL 录音夹具属于既有夹具，不称为本轮重新采集。手机 UI/蓝牙/模拟声音待实机验收。

## 产物

- 默认码流：`impl/pnr/PCM5102_UNIFIED.fs`；独立副本：`reports/touch16_delivery_20261026/PCM5102_UNIFIED_touch16_20261026.fs`。SHA256 `0D205CFE2795BEDE06987C0828D3BD70BE75726428B744C45FDDCE78B86E106C`。
- App：`android_app/dist/FPGA-Music-Touch16-Code26.apk`，滚动入口 `FPGA-Music-Unified.apk` 已同步。SHA256 `CE178B7094C09AAC3F1E25AD7374022731A8F25CACC21FDB3561416997CF4C3B`。
- 旧构建及 APK：`previous_default/`。当前操作与协议见 [TOUCH16.md](../../TOUCH16.md)。

## 复现

在 pcm5102_pam8403 目录执行；新实验请使用新报告路径，保留本轮证据。

```powershell
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build_unified.tcl
./tools/run_sim.ps1 -Tests tb_top_touch16
./tools/run_sim.ps1 -Tests tb_top_touch16_recovery,tb_hc05_extensions,tb_top_idle,tb_top_dual_analog
./android_app/test-core.ps1
./android_app/build-apk.ps1 -OutputApk 'dist/FPGA-Music-Touch16-Code26.apk'
```

旧八键专用 GPIO/顶层回归和 sim/reference 冻结模型仍保留历史用途；本轮更新实际十六键入口及协议扩展回归，没有把旧参考同步改成新行为。
