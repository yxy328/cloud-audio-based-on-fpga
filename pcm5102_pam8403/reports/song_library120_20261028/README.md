# 120首离线曲库：App Code45

2026-10-28，App **1.44-library120 / Code45**。音游、下落指引和自动演奏本来就使用同一份 `downloadable_song` RAM 中的已提交曲谱。本轮将手机曲库从9首扩充到 **120首，三个等级各40首**，同时在曲谱页说明共用关系。

- [安装包](../../android_app/dist/FPGA-Music-Library120-Code45.apk)；[默认入口](../../android_app/dist/FPGA-Music-Unified.apk)与它逐字节一致。
- [使用与容量说明](../../android_app/SONG_LIBRARY.md)
- [逐曲目录、来源与数据指纹](../../android_app/third_party/oneill/catalogue.json)
- [来源与改编方式](../../android_app/third_party/oneill/README.md)
- [本轮机器可读结果](release.json)

## 曲目与玩法

原九首和默认白银《伦敦桥》保留，新增111首有原谱来源的 O’Neill 1903 传统旋律。总计 **原9首、58首新增单遍版、53首明确标注的旋律节选**；新曲保留英文原名。不是120首完整版，也不把同一曲的变速、移调或多个片段重复计数。

单遍练习版各段演奏一次，反复段使用首遍结尾，合并连音并略去装饰音。整曲超出范围时，选择连续4/8/12/16个完整记谱小节，不切断连音；标题带“（节选）”，元数据给出范围。小节序号按单遍练习版计数，包含弱起、去掉非首遍结尾后计数。只做整体移调，保持音程和相对节奏，不折叠八度。

全部曲谱在 MIDI60～72 范围内、最多十二种音高，新增曲最大121条事件；上限仍为128条。默认十二键映射可自动匹配，原九首仍兼容七键。旧七键映射遇到超过七种音高的曲子会明确拒绝。下载成功再 PLAY 即可跟谱计分；自动演奏试听不计分。普通曲库按时长自动生成 TAP/HOLD；原有四类练习谱和类型CSV仍支持DRAG/FLICK。

## FPGA资源

**增量：0 Logic / 0 CLS / 0 Register / 0 BSRAM / 0 DSP。** 整个曲库保存在APK，FPGA只接收当前一首，继续使用原128条事件的双缓冲原子提交RAM。无需扩充板上ROM，不改协议，不改综合或布局布线输入，也无需为曲库重新烧录。

[audit.ps1](audit.ps1)逐项确认开始本轮时记录的 **86个FPGA源文件** 哈希未变，并检查111个原始ABC的SHA256、容量以及两个APK字节一致。本轮未综合布局布线、未修改或烧录位流；当前磁盘默认位流指纹保存在 `release.json`，不以历史报告中的指纹代替实测。

## 验证与产物

- [曲库与App核心回归](core_tests.log)：全部通过，曲库 **80015项断言**，覆盖原九首时长、120首容量/唯一性、七/十二键随机与重复映射、下载命令、音游/试听相同事件、CSV无损回读；同时通过既有弯音、四类音符、SPP、音游状态等回归。日志中与RTL夹具比较的条目使用已有数字仿真输出，本轮未重新运行RTL仿真。
- [数据重生成](reproducibility.log)：从111个保留的原始ABC重新生成Java和目录，SHA256完全一致；music21只在开发机生成数据，不进入APK或FPGA。
- [APK构建](apk_build.log)：Java/D8/aapt2编译、Code45版本及v3签名验证通过；[附加核对](apk_checks.log)通过4字节对齐，签名证书与Code44相同，可覆盖安装。
- [源文件/产物审计](audit.log)：源文件未变、111份来源指纹、128条上限、默认/命名APK一致。

APK SHA256：`E918156D1765F8BF9C063D37DA8193F6E156F384B311226D4F12CE285DED3897`。

未安装到手机、未连接真实HC-05进行整库下载与试玩。旧的 [Code44 APK本机回退副本](rollback_Code44.apk) SHA256：`319C838FFC708DDEF4725364E6D48E6134FAED09930D7BC5EABE456BF92302EB`。已有用户改动保留，未进行Git提交。

复现：

```powershell
# 在 android_app 目录
./test-core.ps1
./build-apk.ps1 -OutputApk dist/FPGA-Music-Library120-Code45.apk
# 可选：从保留的来源重新生成曲库，需要开发机安装 music21==10.5.1
python tools/generate_traditional_songs.py
```
