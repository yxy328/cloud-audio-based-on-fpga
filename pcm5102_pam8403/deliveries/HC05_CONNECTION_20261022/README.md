# HC-05连接定位版

2026-10-22，**Code24 /1.23-linkdiag**。安装 [FPGA-Music-LinkDiag-Code24.apk](FPGA-Music-LinkDiag-Code24.apk)，与仓库滚动安装包字节一致、与原Code22签名证书相同，可覆盖安装。

1. 安装后打开“设备”页，确认显示 **当前安装：v1.23-linkdiag / Code24**。
2. 选择HC-05并点击连接。
3. 如果失败，保留完整提示。新版会显示具体命令、期望回复、字节数，以及最近完整行或缺少LF的情况。

原四档回声冻结包中的同名APK仍为有缺陷的Code22，已加停用提示，不应继续安装该副本。用户反馈的截图没有版本与失败命令，本次尚不能确定现场卡在哪一步，也未宣称手机连接已恢复。

本版将回复匹配收敛到一处，设备事件与异步录制溢出不确认命令；发送1～64个可打印ASCII字符并只追加LF。补测完整初始化十步、真实参数回包解析、逐字节分片、交错回复，以及无字节 /缺LF /回复类型不符的超时。全套核心测试通过，SppLink **255项**；APK构建、v3签名与Manifest核对通过，记录见 [APK_VERIFY.log](APK_VERIFY.log) 和 [RELEASE.json](RELEASE.json)。

本次未改RTL、命令字典、回复模板或位流。原四档回声与资源记录继续适用。详细说明见仓库 [HC05_CONNECTION.md](../../HC05_CONNECTION.md)；本包校验见 [SHA256.json](SHA256.json)。

APK SHA256：`8E2C3AF491B68E6D1755BCFFBF31D470DFD4243F777ABE48D866208608B9A7DD`。
