# 本地验证记录

## 当前入口：统一版

主目录唯一工程为 `PCM5102_UNIFIED.gprj` / `top_unified`，默认 `gw_sh tools/build.tcl` 输出 `PCM5102_UNIFIED.fs`。统一版验证结果见 [RAM_GEOMETRY_VERIFICATION.md](RAM_GEOMETRY_VERIFICATION.md)，录制操作见 [UNIFIED_RECORDING.md](android_app/UNIFIED_RECORDING.md)。下文是按日期保留的历史验证记录，其中旧工程和旧构建脚本现已[归档](archive/legacy_projects/README.md)。

## 2026-10-20：独立 HC-05 Flash PCM 音频目标

新增 [路线2说明](HC05_AUDIO_ROUTE2.md)：原音质最多30秒，9600bps停止后回传约54分钟以上。独立工程为 `PCM5102_AUDIO_TAKE.gprj`；最终资源/时序及验证日志以交付包固定快照为准，不沿用默认HC-05或EVENT_TAKE资源数字。RTL、JVM/App构建、布局布线与实板状态分别记录；未自动烧录，实际Flash、手机SPP和播放仍待上板验收。

## 2026-10-19：HC-05 默认配置，命令译码及资源优化

已完成 [HC-05 资源优化](HC05_RESOURCE_OPTIMIZATION.md)：53 个命令模板共享同步 ROM/比较器，默认裁掉备用 USB 录音硬件，曲谱计时按上界缩为 23 位。保留手机命令、实时合成及 HUB75E；默认 `ENABLE_USB_AUDIO_RECORD=0`、`ENABLE_EVENT_TAKE=0`。App v1.11 继续使用现有 HC-05 9600bps 链路。

同条件快照综合 Logic **21058→19393，减少 1665（7.91%）**；布局布线 Logic **21163→19506/23040**，Register **8856/23280**，CLS **10713/11520**，BSRAM **53/56**，DSP **20.5/28**。50MHz Setup/Hold 违反端点 **0/0**，Fmax **51.116MHz**，最差 Setup Slack **+0.437ns**。最终构建于上海时间 **15:27:18** 完成，0 ERROR、2 条默认未用输入 `CV0016` 告警。

**19 组 RTL 测试通过**，含新旧译码器 512 次位级 UART 对照、128×60000ms 曲谱边界、默认 HC-05 整机发声/显示，以及显式启用备用 USB 的 712 采样兼容测试。详细范围、日志及固定输入见上述记录。独立位流为 `impl/pnr/PCM5102_HC05_ONLY.fs`，SHA256 **99249FC9FA132F48BE4FC3E1C9847B946BE86062DF3261760B7F478DBCECB326**，配套清单为 `PCM5102_HC05_ONLY_manifest.json`。

已读取 Gitee 参考最新 fix41（提交 `03dae97`）；它已支持 HC-05，旧本地 fix28 的说明不代表线上现状。构建对应固定 `hc05_final` 快照，可选 TAKE 后续修改不属于本位流。**未烧录，未做本轮门级或实板验证**；本段是默认 HC-05 配置的最新资源记录，下面 USB 启用配置属于历史构建。

## 2026-10-19：App v1.11 / Code12，仅HC-05通信，USB音频保留备用

按用户当前硬件选择，手机与FPGA仅使用现有HC-05连接。App启动不创建USB音频接收器、不注册其设备权限/断开接收器、不启动其工作线程；USB录音入口继续隐藏。驱动、音频接收代码和FPGA预留引脚保留备用，无需USB模块、RTS或OTG，不将完整PCM/WAV改走现有9600bps链路。当前曲库、LED联动、演奏控制及板上录制相关界面保留，各自仍需支持相应命令的固件；板上事件录制回放的未完成项见[说明](RECORD_PLAYBACK.md)。

### 构建与检查

- 独立产物：`android_app/dist/FPGA-Score-hc05-only.apk`，v1.11 / versionCode12，包名`cn.fpga.score`，Android 10+、target/compile SDK35。Manifest与Gradle版本一致，USB Host仅保留为可选的备用能力。
- Java、D8、APK打包、zipalign、v3签名及Manifest检查通过。JDK对旧API/Java8目标及签名工具本地访问仍有提示，不声称构建零警告。
- `javap`检查编译后的`MainActivity.onCreate`：没有USB音频构造或调用；备用连接/开始录音方法也不会执行USB调用或发送AREC命令。对应反汇编为`android_app/build/hc05_only_MainActivity.javap.txt`，此项属于编译结果检查，未声称手机运行测试。
- `android_app/test-core.ps1`的9组核心测试通过，共**22575项检查**：LED180、TakeStatus17、SongLibrary4118、DeviceControls4605、VoiceBend7229、AdsrProfile5032、SongCodec30、SppLink161、AudioRecording1203。另读取已有LED跨端夹具203项（含重复180项基线）及已有两份WAV夹具各11项；没有为本次通信选择重新运行FPGA仿真。
- 161个相关本地文档链接检查通过。旧`FPGA-Score-debug.apk`及`FPGA-Score-led-remote.apk`保留，SHA256与本次开始前相同。

新APK SHA256：`C4BC847AA8914A426A90FFEF47D72FF67ECD64DBEF231EEF7B441B401BDBF543`。
日志：`android_app/build/hc05_only_apk.log`、`android_app/build/hc05_only_core.log`；源码与产物指纹：`android_app/build/hc05_only_hashes.json`。本次未修改FPGA RTL、引脚或位流，也未烧录实板；关闭USB初始化不需要为此重烧FPGA。尚未在手机/模拟器操作本次App或实测HC-05联动。

## 2026-10-19：App v1.10 / Code11，手机切页、状态读回与实时预览

已完成 [手机 LED 联动](LED_REMOTE.md)：`VIS,0..3` 直接切页，`VIS?` 区分请求/实际页面及请求/已发布 XY 参数，`VIZ?` 原子回传 16 段频谱、三组音源幅度和实际显示元数据。复用原扫描器、FFT 和缓存，不在音频链路插入处理级。

### 配套构建

- **2026-10-19 15:23:19（上海时间）**，Gowin V1.9.11.03 Education 完成冻结快照的 `top` 综合、布局布线和独立位流。脚本使用资源共享和 retiming，保留 50MHz 及原 ADC 时钟约束。
- Setup/Hold 违反端点均 **0**，Fmax **50.344MHz**，最差 Setup Slack **+0.137ns**，最差 Hold Slack **+0.149ns**。
- Logic **19920/23040**，Register **9200/23280**，CLS **10834/11520**，BSRAM **54/56**，DSP **20.5/28**，I/O **50/86**。
- 最终 **0 ERROR、2 WARN**：`CV0016 flash_miso unused` 因该目标不启用 Flash 事件录制；`EX3791` 为曲谱前瞻加法结果装入 23 位计时量，生产上界 `128*60000+1500+1500+2 < 2^23`，本轮下载与整机曲谱检查通过。保留告警记录，不声称零警告。
- 复用同期日志/显示资源优化；新增回复编码器分时使用已有 256 位回复寄存器。第一版并行编码超出容量，已替换，不交付失败构建。
- 交付来自 `sim/build/led_remote_delivery/pcm5102_pam8403/` 固定源码；其中构建日志为 `sim/build/delivery_build_final.log`。快照配置 `ENABLE_EVENT_TAKE=0`、`ENABLE_USB_AUDIO_RECORD=1`，CTS 例外仅限第一级同步器。共享工作区同期仍有修改，故提供 `sim/build/LED_REMOTE_v1.10_sources.zip` 与快照指纹；早期 14:47 构建属于中间产物，不作为最终交付。
- 资源/时序报告已复制到 `impl/pnr/PCM5102_LED_REMOTE.rpt.txt`、`impl/pnr/PCM5102_LED_REMOTE_tr_content.html`，最终 SHA256 以以下表格及冻结目录清单为准。

| 产物 | 标识 / SHA256 |
| --- | --- |
| `impl/pnr/PCM5102_LED_REMOTE.fs` | UserCode **0x00000147**；`28240EA2A11572DA3861BA0AF82167A47708AFBE30CF075144A8DBAD3D2043F6` |
| `android_app/dist/FPGA-Score-led-remote.apk` | **v1.10 / versionCode 11**；`B30E6145134BE4F8650EB91A62AAF58670805479931648F37333361B7B6B898C` |
| `sim/build/LED_REMOTE_v1.10_sources.zip` | **217 个输入文件及两份清单**；`4E171E90C62312C6F2CCF46C9B1B255BAEAF798B3576FD4C0BE5BD00E1CF6EA2` |

源码包中的 `source_manifest.json` 按相对路径记录所有输入的 SHA256，`delivery_manifest.json` 记录上述 APK/位流指纹和未烧录状态；解压后构建方法见 `DELIVERY.md`。不包含 SDK、签名私钥或构建缓存，重建产物的默认 UserCode/元数据可能变化，不保证重新构建的二进制逐字节相同。

App 从快照 Java 编译，经 D8、对齐、APK v3 签名与 Manifest 检查通过，包名 `cn.fpga.score`，min SDK 29 / target 35，使用原调试签名。旧 APK 与旧 `PCM5102_PAM8403.fs` 保留。快照日志为 `android_app/build/delivery_apk.log`；JDK/签名工具有旧 API 与本地访问提示，不声称 App 构建零警告。

### 数字验证

本轮 **10 组 RTL 测试通过**，不是全部历史回归：

- `tb_hc05_visual`：四页请求、请求/实际状态、单次脉冲、严格语法/边界、真实 32 字节 UART；发送中改变源快照，回复仍保持完整旧帧；XY/PING 共存。
- `tb_display_mode_control`：保留 S2 长短按、四页和六预设；手机与按键阈值/松开同周期优先级、按住期间动作抑制，不重启曲谱。
- `tb_audio_visualizer`、`tb_hub75e_audio_display`：65536 个采样坐标、幅度/衰减、波形/XY/FFT、外部 HUB 引脚、RGB5 整帧切换及隐藏曲谱推进。
- `tb_hc05_download`、`tb_performance_logger`、`tb_hc05_extensions`、`tb_hc05_xy`：原曲谱下载、日志及控制/XY 命令继续通过。
- `tb_top_audio_visual`：实际 I²S、相位、触摸/红外/吉他、S2 与手机四页并行；UART 快照与执行查询一拍的显示数据逐位一致，现场 C4 落入手机使用的频段；切页不重启曲谱或打断声音，继续从外部 HUB RGB/CLK/LAT 重建画面。
- `tb_top_audio_record`：712 个录音采样仍与外部 I²S 逐字一致，保留 CTS 暂停、真实输入、音效/音量、TDM 期限与 HUB 扫描检查。

最终快照 RTL 日志为其中的 `sim/build/delivery_regression.log`，显式启用交付 USB 配置的整机复查为 `sim/build/delivery_top_profile.log`。父目录早期日志仅作开发记录。

**9 组 JVM 核心测试通过**：LED 协议 180、SPP 161，及原 TakeStatus、曲库、设备控制、滑音、ADSR、曲谱、音频接收。将快照真实 UART 的 `led_visual_protocol.txt` 和整机现场 C4 的 `led_top_preview.txt` 输入同一 Java 解析器，核对状态、16 段顺序、三组幅度、版本和有效位，共 **203 项检查通过**（含重复执行的 180 项基线）；另验证本轮 712 采样录音文件。快照日志 `android_app/build/delivery_core.log`，最终 C4 复查为 `android_app/build/delivery_cross_final.log`。

App 最多约每秒查询 5 次，下载/录制或其他命令期间跳过查询，断线或切后台停止，1.5 秒无新数据清图。生命周期逻辑已编译并做代码检查，未在手机/模拟器操作新卡片。

**未烧录本轮位流，未做本轮门级仿真，实体手机、HC-05 和 LED 联合验收待完成。** 使用时按 [说明](LED_REMOTE.md) 更新配套 APK 与独立主工程位流。板上事件录制/Flash 回放属于另一个开发目标，不能由本次结果代替验收。

## 2026-10-19：日志与曲谱显示资源优化

详见 [资源优化记录](RESOURCE_OPTIMIZATION.md)。同条件快照中，两处 RTL 优化使综合 Logic 从 23155 降到 22012（减少 1143，4.94%）；修正 CTS 第一级同步器 SDC 层级名。包含同期 UART 修改的最终整合快照完成综合、布局布线与独立位流生成：Logic 21745/23040、Register 9616、CLS 11363/11520、BSRAM 53/56、DSP 20.5/28；50MHz Setup/Hold 违例均为 0，Fmax 50.806MHz，最差 Setup Slack +0.317ns。

12 组不同 RTL 回归通过，含日志最大 33 字节行/32 位计数边界、6173 对显示行参考检查及整机 712 个录音采样与外部 I2S 逐字一致。独立位流、SHA256、快照、日志和复现命令见上述记录；未烧录本轮位流，未完成新位流门级仿真或实板验收。

## 2026-10-19：App v1.9 / Code10，手机 LED 轨迹控制功能包

新增 [LED 控制卡片](android_app/LED_CONTROL.md)：六个参考/混音预设、频率比与相位选择，复用 `XY,r,p`。仍需板上 S2 进入 XY 页，不自动切页。参数等待设备 `OK` 后才显示“最近确认发送”；断线/重连清除确认，列表明确为待发送值，没有设备 XY 状态查询。正在下载或执行命令时禁用预设及参数选择。

### 构建与兼容范围

- 安装包 `android_app/dist/FPGA-Score-led.apk`，包名 `cn.fpga.score`，**v1.9 / versionCode 10**，Android 10+，target/compile SDK 35；Manifest 与 Gradle 版本一致。
- Java 编译、D8、zipalign、APK 签名验证与 Manifest 检查通过。与原 `FPGA-Score-debug.apk`、`FPGA-Score-library.apk` 的签名证书 SHA256 一致，可覆盖同签名旧版；这两份旧包没有被本次构建覆盖。
- APK SHA256：`CFC7F2328B6522E2F55096F1AE815978906F8B77BA72A5C43B120F0F71C0D623`。
- 构建命令：在 `android_app` 中运行 `./build-apk.ps1 -OutputApk 'dist\FPGA-Score-led.apk'`；日志 `android_app/build/led_xy_apk.log`。JDK 25 对旧 API、Java 8 目标及签名工具本地访问给出提示/警告，构建无失败，不声称零警告。
- 本次没有修改 FPGA RTL、重新综合或烧录位流；XY 功能依赖已有固件的命令支持。本包沿用当前工作区已有曲库、板上录制等界面，TAKE 按钮另需配套固件；本轮不将这些界面计为完成实板验收。

### 验证

- `android_app/test-core.ps1` 八组 JVM 核心测试通过，共 **22390 项检查**：TakeStatus 17、SongLibrary 4118、DeviceControls 4605、VoiceBend 7229、AdsrProfile 5032、SongCodec 30、SppLink 156、AudioRecording 1203。
- SppLink 新覆盖全部 16 组 XY 编码、CRLF、分片 OK、穿插事件/录制结束消息、OK 到达前保持等待，以及不支持命令的固件返回 `ERR,CMD` 后不产生成功确认。保留原手势命令等待、下载、控制、断开、取消及超时检查。
- 另用已有的 1501 样本模块串口文件与 712 样本顶层串口文件运行 Java/WAV 接收检查，各 11 项通过；**复用既有 RTL 数据，不是本轮重跑 RTL 仿真**。含这两组共 **22412 项检查**。日志 `android_app/build/led_xy_core.log`。
- 文档链接与相关修改的 `git diff --check` 通过。

尚未在实体 Android 手机或模拟器运行新卡片，未完成 HC-05、LED 面板与手机联合验收。远程切页、实时设备 XY 查询与手机实时频谱预览仍待开发。

## 2026-10-18：App v1.6 / Code7，完整数字演奏录音（稳定安装包）

新增[单向录音回传](AUDIO_RECORDING.md)：在I²S同一帧锁存最终16位混音副本，经独立1024样本FIFO、FAR1/CRC、2Mbps UART及USB串口送到手机，校验后保存/导出WAV。HC-05保留9600bps控制/事件日志；触摸16路、红外/手势32路原有TDM不变，没有新增预录PCM下载或播放通路。需增加3.3V且支持2Mbps与自动RTS/CTS的模块、两根J3信号、共地及手机OTG；原REC日志范围不变。

### 当前构建

- Gowin V1.9.11.03 Education，GW5A-LV25MG121NC1/I0，默认顶层`top`；上海时间 **2026-10-18 20:38:46** 完成综合、布局布线、静态时序、位流和仿真网表生成。此构建包含共享工作区已完成的告警修正；`WARNINGS.md`中的独立构建是另一份产物。
- 最终Gowin完整日志 **0 WARN、0 ERROR**。50MHz：Setup/Hold违反端点均为 **0**；Fmax **50.722MHz**，最差Setup Slack **+0.285ns**。只对新增CTS第一级同步器设异步输入假路径，未放宽音频主时钟。
- 资源：Logic **22827/23040**，Register **9890/23280**，CLS **11492/11520**，BSRAM **53/56**，DSP **20.5/28**，I/O **44/86**。CLS只余28个，后续叠加功能需重新评估容量与时序。
- App **v1.6 / versionCode7**：保留已有主题资产与演奏控制；Java/D8/APK构建、对齐、v3签名、Manifest版本和可选USB Host特性检查通过。没有声称完成手机界面或USB硬件运行测试。

### 数字验证

本轮 **10组RTL测试通过**，包括新增3组及7组有针对性的兼容回归；没有重跑全部历史测试。

- `tb_audio_record_stream`：实际2Mbps位时序，1501个采样逐字一致，CTS中途暂停、部分尾包、CRC/序号/会话/采样索引；长暂停溢出时保留64采样连续前缀并标记失败，中止后99采样新会话正常。
- `tb_hc05_audio_record`：21条位级UART事务，AREC_START/STOP/ABORT/查询、会话边界与严格语法、未就绪/忙拒绝、单次脉冲；16键/锁存/模拟控制期间允许数字音频录制，旧REC事件日志守卫与PCM命令拒绝保持。
- `tb_top_audio_record`：50MHz、音频/I²S及2Mbps UART保留真实时序；**712个回传采样与外部I²S引脚解码逐字一致**。覆盖真实触摸/IR引脚、分类后的手势注入、吉他、录制中EFFECT/VOLUME控制、CTS暂停、TDM期限与HUB75扫描。APDS光学分类不属于这项测试。
- 回归：`tb_hc05_extensions`、`tb_hc05_download`、`tb_performance_logger`、`tb_touch_tdm_synth`、`tb_audio_effects`、`tb_audio_master_volume`、生产参数`tb_top_idle`通过。包含旧事件日志的溢出/结束及拒绝采样播放命令、16声部包络/频谱、59005采样音效参考模型等检查。
- JVM共 **18224项检查**：DeviceControls4605、VoiceBend7229、AdsrProfile5032、SongCodec30、SppLink103、AudioRecording1203，另有两份真实RTL串口数据各11项。包含分片、粘包、随机有符号数据、CRC损坏、丢包、溢出、缺结束包、16位序号回绕、WAV头和全部采样字节。
- 将模块1501采样和整机712采样串口文件送入手机同一Java接收器，输出WAV均逐字一致；再用Python标准库`wave`及独立`binascii.crc_hqx`复核包CRC、长度、序号、采样及WAV载荷通过。WAV整数率48828Hz，`srAT`块保存精确50000000/1024，不重采样。
- 另尝试了PNR网表的`tb_top_idle`冒烟运行，编译完成但运行超过12分钟仍未观察到PASS，主动停止并记为**未完成**，不计入上述10组RTL通过数。日志为`sim/build/audio_record_netlist.log`；不据此声称门级功能仿真通过。

### 当前产物与日志

| 产物 | 标识 / SHA256 |
| --- | --- |
| `android_app/dist/FPGA-Score-debug.apk` | v1.6 / Code7；`C6B529F67CA9FA9E94EF75B2F8024CD933714E3BB85EDC65F5C7394F7BDD73E5` |
| `impl/pnr/PCM5102_PAM8403.fs` | UserCode **0x000089A9**；`6A1279C604A10355EA6CBD7BA4EF6D6FD406C9D9CDAA2BDF3B9739B5191A2344` |

源文件和产物指纹：`sim/build/audio_record_artifact_hashes.json`。构建日志：`sim/build/audio_record_build_final.log`；测试：`sim/build/tb_audio_record_stream.log`、`sim/build/tb_hc05_audio_record.log`、`sim/build/audio_record_top.log`、`sim/build/audio_record_regressions.log`、`android_app/build/audio_record_core_final.log`、`android_app/build/audio_record_apk.log`。

尚未烧录实板，未实测USB转串口的持续吞吐/RTS、手机OTG/前台运行、模块供电、实际声音或长时间录音。完整录音指最终数字混音，不含DAC/功放/扬声器的模拟声音。丢包、溢出、断连或缺END的文件只能标为不完整；这不是整机实物验收通过的声明。

以下保留此前版本的构建与验证历史。

> 2026-10-18 仓库整理复核：统一App v1.4、8/16键接线、八音色、ADSR作用范围及快速上手，新增版本记录和首页状态页预览。检查22份文档中的169个链接（其中2个为明确保留的本地生成产物链接），主工程50项文件依赖均已纳入仓库。重跑App五组核心测试共16990项断言通过；`tb_hc05_extensions`、`tb_analog_expression`、`tb_touch_tdm_synth`、`tb_audio_effects`、`tb_audio_master_volume`通过。模拟输入测试在受限环境编译器异常退出，宿主环境复跑通过。核对APK与本地位流SHA256均与下表一致；本次整理没有重新综合或烧录实板。

## 2026-10-18：App v1.4，8/16 键和参考工程迁移

功能、串口协议、接线和限制见 [参考工程迁移说明](REFERENCE_MIGRATION.md)。
新增 App 8/16 键选择、串行极性读回、完整 16 键和弦、回声/合唱、延音/PANIC、总音量、
滑杆四种用途及端点标定；红外/手势音色增至八种。上电仍为原 8 键接口。
无需 OLED，64×64 HUB75E 空闲显示控制参数、16 键/红外状态、音量和 ADC 行程，播放时自动显示原曲谱；波形、XY、FFT 页保留。

触摸合成改为 16 个独立相位/ADSR 上下文共享运算，每声部保存包络快照；
前七键 MAP、独立滑音和曲谱保持兼容，K8～K16 固定 C5～D6。
TTP229 采用参考工程的双窗口投票与两帧确认，并适配高/低有效串行。
16 键时必须拆掉 OUT1～OUT8 直连，只接 SCL/SDO，避免 FPGA 原有下拉加载触摸电极。
滑杆复用原 ADC，替换 FSR；没有新增第二路同时采集。曲谱/日志的兼容范围见迁移说明。

### 构建

- Gowin V1.9.11.03 Education，GW5A-LV25MG121NC1/I0，顶层 `top`；上海时间 **2026-10-18 16:27:14** 完成最终综合、布局布线、位流及仿真网表生成。
- 50MHz：Setup/Hold 违例均 **0**，Fmax **50.072MHz**，最差 Setup Slack **+0.029ns**；时序余量较小，修改 RTL 后需重新布局布线确认。
- 资源：Logic **22131/23040**，Register **9544/23280**，CLS **11343/11520**，BSRAM **52/56**，DSP **20.5/28**，ADC **1/1**。
  相比此前 7 键版本的 56 块 BSRAM、23 DSP，保留了新增功能所需空间；逻辑和 CLS 仍接近容量，不承诺还能直接叠加大型外设。
- App **v1.4 / versionCode 5** 已完成 Java/D8/APK 构建、对齐、APK v3 签名和 Manifest 检查；复用原调试签名，可覆盖安装。
- JVM 核心测试 **16990 项断言**：DeviceControls 4605、VoiceBend 7229、AdsrProfile 5032、SongCodec 30、SppLink 94。

### 数字验证

本轮针对性 RTL 仿真已通过 **35 / 35** 组；没有声称运行所有历史测试。

- `tb_top_touch16`：真实 UART、TTP229 SCL/SDO 和外部 I2S 解码；全部 16 键音高存在，两种串行极性、GPIO 隔离、忙状态拒绝、锁存/PANIC、K16、压力用途及返回 GPIO 均通过。
  4096 点 Hann 投影复查得到前七键幅度约 1217～1316、后九键约 614～624 PCM 单位，16 个目标音高均存在。
- `tb_touch_tdm_synth`：16 键同时起音/衰减不超音频帧期限；高九键频谱、各自包络/释音、已按音参数快照、新音参数更新、变调相位连续。
- `tb_hc05_extensions`：40 条真实位级 UART 事务，控制/ADC/标定/极性查询，参数边界、非法格式、录制/演奏忙状态和拒绝时不提交。
- `tb_analog_expression`：全部湿度代码、校准两端/中点、音量上限、音高、完整颤音周期、ADC 超时/过期回退。
- `tb_sensor_eight_timbres`：8 种不同且非零的 PCM 波形、事件分配、期限和最终释音；参考抗干扰用例通过真实 1+7、16 键和弦、短干扰修正、长干扰拒绝及恢复。
- 音效独立环形缓冲参考模型检查 59005 样本；总音量的精确静音/原增益、符号、平滑及反向变化通过。
- 原七键独立滑音、运行时 ADSR、现场静音/多音演奏、按键响应和显示回归通过；16 份顶层测试平台全部编译通过。
  七键 OUT→首个 I2S PCM 最慢 **1.823ms**，OUT→包含释音尾音的静音最慢 **12.033ms**；不含触摸芯片电容扫描、DAC 和功放。
- `tb_top_audition` 与 `tb_top_integrated` 已通过：显式试听、七键和弦/连续音/休止、STOP 保留手按音，UART/曲谱/HUB 扫描，FSR 两用途、四方向/双银行手势、吉他及最终静音。
- `tb_hub75e_status`：从外部 HUB75E RGB/CK/LAT 引脚重建全部 32 个 PWM 平面；精确检查 8/16 键、锁存、红外、字体、半音量/满行程、ADC 红色故障提示、整帧更新和状态/曲谱自动切换；扫描仍为每行 133 个时钟。
- 为解决新增显示后的布线拥挤，XY 的 32 样本历史改为同步 BSRAM；ADC、TTP229、曲谱和日志的计数器按参数范围定宽。`tb_lissajous_delay`、`tb_audio_visualizer`、`tb_fsr_adc_capture`、`tb_gowin_fsr_adc`、`tb_downloadable_song`、`tb_performance_logger` 和三组 TTP229 抗干扰用例重新通过。
- `tb_top_audio_visual` 已通过：真实 I2S 采样和 DDS 相位不受切页影响，触摸/红外/吉他进入波形与 FFT，S2 四页和六种 XY 预设、UART XY、曲谱并行正常；真实 UART 的音量/音效/延音/音色/压力/模拟用途、ADC 转换及实体键/红外进入总览快照，并重建外部 RGB5 画面。最终 RTL 的 `tb_top_touch16` 和生产参数 `tb_top_idle` 再次通过。

### 产物

| 产物 | 标识 / SHA256 |
| --- | --- |
| `android_app/dist/FPGA-Score-debug.apk` | v1.4 / Code5；`659A2DF5E1B58686C8BA1F662C39D4B33EB837CCBF9B61C3DEFEF4F147DDE7F7` |
| `impl/pnr/PCM5102_PAM8403.fs` | UserCode **0x00002850**；`E48577E990BF0A4233401078A91555CE0F22EBF44A824BE0986BF400F4B16FCF` |

源文件与产物指纹保存在 `sim/build/migration_artifact_hashes.json`。
主要日志：`impl/build_migration_led_fit.log`、`sim/build/migration_final_touch.log`、
`sim/build/tb_hc05_extensions.log`、`sim/build/tb_analog_expression.log`、`sim/build/migration_units.log`、
`sim/build/migration_regressions.log`、`sim/build/migration_led_tests.log`、`sim/build/migration_fit_tests.log`、
`sim/build/migration_led_top.log`、`sim/build/migration_led_touch16.log`、`android_app/build/migration_apk_led.log`。
16 键采样与频谱结果：`sim/build/decoded_pcm_touch16.csv`、`sim/build/touch16_spectrum.json`。
状态页预览：`assets/status16.png`、`assets/status8.png`，由真实 HUB75E 输出引脚的数字仿真重建。

本轮**未烧录实板、未实测触摸焊盘/误触、未试听模拟输出或测整机延时，未在真实安卓手机/模拟器操作 UI**。
上述属于数字仿真、编译与静态时序证据；硬件改接后仍需按迁移说明现场验收。

复现：`android_app/test-core.ps1`、`android_app/build-apk.ps1`、`tools/run_sim.ps1 -Tests <上述测试名>`、Gowin `gw_sh tools/build.tcl`。

> 2026-10-17 仓库文档整理复核：补充首页、文档索引和快速上手，修正运行时 ADSR、App v1.3 与 S2 操作说明，标注历史资料。检查了10份入口/功能文档中的96处本地链接及主工程全部文件依赖；重新运行 `tb_hc05_control_races`、`tb_hc05_download` 均通过，App四组核心测试共12347项断言通过。当前APK SHA256与下节记录一致。本次整理未重新综合、生成位流或烧录实板；下节保留最近一次构建结果。

## 2026-10-17：App v1.3 显式自动演奏试听（历史版本）

App 曲谱卡新增“自动演奏 · 已下载曲谱”，发送 `AUDITION`，不修改普通 PLAY/S1/S2 的无声指引语义。
默认仍为 `ENABLE_DEMO_SCORE=0`；显式试听将当前曲谱和弦对应的七键门控并入已有触摸 DDS/ADSR，
沿用逐声部音高、ADSR、FSR 表情和混音/I2S。没有新增预录音乐采样或计分振荡器。
相同音符通过事件末尾的短门控间隔重新起音；休止保持曲谱时序。停止保留实际按住的触摸音。
自动结束解除模式；硬件曲谱控制还会取消正在校验的 UART 自动演奏请求，防止延迟确认重新启用声音。
录制期间拒绝开始试听，曲谱校验/暂存双银行/键位覆盖不变。App 对旧位流 ERR,CMD 和无有效谱 ERR,STATE 给出操作提示。

### 构建与验证

- App v1.3 / versionCode 4 已生成并通过 APK v3 签名和清单检查；四组 Java 核心测试通过，共 12347 项断言。
- `tb_hc05_download` 通过，新增无曲谱、映射不覆盖、录制中拒绝试听及普通 PLAY 清除试听模式检查。
- `tb_hc05_control_races` 通过，新增校验中硬件操作取消自动模式、实体重启/停止清除自动模式检查。
- `tb_top_audition` 通过，真实 50MHz/I2S 下仿真 155.922ms，外部 BCK/LRCK/DIN 解码验证显式启动、
  预备阶段静音、三音/七音独立 DDS/ADSR 输出、重复音、休止、自然结束、STOP 保留手按音与缺键拒绝。
  曲谱时长和预备时间使用加速测试参数，生产预备时间仍为1500ms。
- `tb_top_live` 通过，真实 50MHz/I2S 下解码3820个立体声帧，确认原 PLAY/S1/S2 指引静音，
  手动四音/七音并发、独立释音、STOP保留按住的现场音符及最终静音均保持。
- Gowin V1.9.11.03 Education 于上海时间 2026-10-17 14:39:05 完成综合、布局布线和位流/仿真网表生成。
- 50MHz 约束下 Setup/Hold 违例均为 0，Fmax=51.123MHz，最差 Setup Slack=+0.439ns。
- 资源：Logic 22025/23040，CLS 11375/11520，Register 10155/23280，BSRAM 56/56，DSP 23/28。
  BSRAM/DSP 与此前版本相同；CST/SDC 未修改。
- App：`android_app/dist/FPGA-Score-debug.apk`，SHA256=`35AAAA77D9CB27629AD452FD290C5B8A7D407733C7FD2C8207A3DDBA8F94ED51`。
- 位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x0000859F`，
  SHA256=`82EAF284DFEFA15C4A0B2ADAAEE5AE37F94C4E64C85182306B35312394840553`。
- 日志：`sim/build/audition_build.log`、`sim/build/audition_tests.log`、`android_app/build/audition_apk.log`。
  自动演奏外部 I2S 采样：`sim/build/decoded_pcm_audition.csv`；文件指纹：`sim/build/audition_artifact_hashes.json`。
  修改前位流保存在 `sim/build/audition_baseline/PCM5102_PAM8403.fs`。

复现：`android_app/test-core.ps1`、`android_app/build-apk.ps1`、
`tools/run_sim.ps1 -Tests tb_hc05_control_races,tb_hc05_download,tb_top_audition,tb_top_live`、
`gw_sh tools/build.tcl`（分别在对应目录执行）。

本轮未烧录实物板或进行模拟输出试听/延迟测量，未运行本版 PNR 网表功能仿真。
自动曲谱试听不代替赛题传感器实时交互、≥4/32可闻独立声部和≤10/5ms延迟的现场验证。
需安装新 App、烧录配套位流并重新下载曲谱后使用，具体步骤见 `android_app/README.md`。

## 2026-10-17：综合位宽与ROM初始化警告清理（上一版）

修正 `downloadable_song.v`、`tdm_synth.v`、`hub75e_rhythm_display.v`、
`audio_visualizer.v` 的10处隐式截断，明确中间运算宽度、字段切片与有符号增益相加。
`midi_note_lut.v` 改用生成期常量初始化ROM，去掉综合器对初始循环变量 `n` 的警告。
既有的定点缩放、音符映射、流水线周期和端口保持一致。

- Gowin重新综合：`EX3791=0`、`EX3780=0`，没有其他新增综合警告；保留29条 `NL0002`。
- `NL0002` 原因：默认 `ENABLE_DEMO_SCORE=0` 裁掉演示曲谱音轨及其下载音高表；
  触摸只接七个音符键，第八声部恒静音。没有添加保留无用逻辑的属性，也没有屏蔽警告。
- 已通过11项模块RTL：MIDI ROM、下载曲谱、节奏显示、音频可视化、TDM ADSR、TDM队列、
  传感器事件队列、HC05下载、混音延时XY、参考XY、HUB音频显示。
  其中包含65536个有符号PCM输入的坐标核对、3002组延时/相位、每路256个MIDI输入、
  32声部独立包络与正负饱和；满队列处理最大871个主时钟，低于1024时钟帧预算。
- 完整 `tb_top_audio_visual` 通过：真实50MHz/I2S时序下174.47ms，核对触摸/红外/吉他、
  波形/FFT、六种XY预设、演奏中UART设置、连续音源相位、曲谱不误重启和八张外部HUB画面。
  本次合计12项RTL通过。
- 后续附加的 `tb_top_ir_tdm` 与PNR网表 `tb_top_idle` 手动结束，`tb_top_song` 未执行；
  不将这些附加仿真记作通过。验证范围见 `sim/build/warning_cleanup_validation_scope.txt`。

### 本次位流与时序

Gowin V1.9.11.03 Education于2026-10-17 13:20:26（上海）完成布局布线及位流/仿真网表生成。
50MHz约束下Setup/Hold违例均为0，Fmax=51.798MHz，最差Setup Slack=+0.694ns。
资源：Logic 21872/23040，CLS 11358/11520，Register 10124/23280，BSRAM 56/56，DSP 23/28。
CPU/SSPI GPIO仍开启、JTAG GPIO仍关闭；本次没有修改CST/SDC。

- 位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x00003EC1`。
- SHA256：`B4669E7ABD643631E52BA76B964A7504EFDDE729AFAEB9778313FB305B742581`。
- 日志：`sim/build/warning_cleanup_synth.log`、`warning_cleanup_pnr.log`、`warning_cleanup_tests.log`。
- 修改前五个RTL及旧位流备份：`sim/build/warning_cleanup_baseline/`。

本轮没有完成PNR网表功能仿真，没有下载FPGA或进行实板测量。下节保留上一版功能与验证记录。

## 2026-10-17：可调参考李萨如与实际混音XY（上一版）

补齐规整李萨如参考曲线及频率比/相位控制。原来的混音延时XY保留为AUD，不能用复杂混音点迹代替标准曲线验收。
参考曲线显示REF，不进入音频输出，不代表现场音源测量；波形、FFT与下方三组幅度条仍观察真实采样。

- S2长按仍轮换曲谱、波形、XY、FFT；XY页短按轮换八字、多瓣、圆、椭圆、直线、实际混音，其他页短按重启曲谱。
- 新命令`XY,r,p`分别设置来源/频率比和相位：r=0/1/2/3对应AUD/1:1/1:2/2:3，p=0/1/2/3对应0°/45°/90°/135°。
  命令回复OK，不自动切屏；正在演奏和曲谱播放时也可设置。参数随新捕获段锁存，标签与位图一起发布。
- 使用8位相干DDS、256相位像素正弦查表。每512点采集包含两个完整基础周期，双轴均14像素幅度，保证1:1、90°在方形LED上呈圆形。
  新参考逻辑复用原XY缓存，不增加BSRAM/DSP。现有安卓App无专用XY控件，使用S2或蓝牙串口终端，详见[AUDIO_VISUAL.md](AUDIO_VISUAL.md)。

### 最终构建（256相位查表）

| 项目 | 结果 |
| --- | --- |
| 工具 / 结束时间 | Gowin V1.9.11.03 Education / 2026-10-17 12:32:25（上海） |
| 工程 / 顶层 | PCM5102_PAM8403.gprj / top |
| 位流 | impl/pnr/PCM5102_PAM8403.fs |
| UserCode | **0x0000158C** |
| SHA256 | `D5F6EAFB45B0ED69698D9865AC6C139734AAEA43C459A8898BEB2A42F70F6429` |
| 约束 / Fmax | **50.000 / 52.733 MHz** |
| Setup / Hold违例 | **0 / 0** |
| 最差Setup Slack | **+1.037 ns** |
| Logic / CLS | **21776/23040 / 11307/11520** |
| Register | **10124/23280，锁存器0** |
| BSRAM / DSP | **56/56 / 23/28** |
| I/O | **41；CST/SDC与前版相同** |

资源接近上限；本次通过小型像素查表和共用位图实现参考曲线。首轮64相位版本存在可见点迹间断，
已提高至256相位并重新构建，首轮产物仅保留在`sim/build/lissajous_candidate1/`，不作为最终交付。
最终构建日志为`sim/build/lissajous_controls_build2.log`。46个输入及SHA256见`sim/build/lissajous_controls_source_manifest.json`。
前版0x0000017C源码、工程、文档与位流已备份在`sim/build/pre_lissajous_controls_20261017/`。

### 本轮验证

- `tb_lissajous_reference`：12种频率比/相位组合、3072个点与独立实数正弦比较，最大误差0.494860像素；闭合周期、圆形几何、八字交点、旧点清除、配置/标签整帧发布通过。
- `tb_hc05_xy`：16种设置、严格语法/范围、非法命令不修改状态、忙碌时设置及PING共存通过。
- `tb_display_mode_control`：六预设短按轮换、XY页不重启、远程独立参数、长按四屏轮换、复位通过。
- `tb_lissajous_delay`、`tb_audio_visualizer`、`tb_hub75e_audio_display`、`tb_hc05_bend`、`tb_hc05_adsr`、`tb_hub75e_rhythm_display`、`tb_audio_spectrum`通过。
- 完整顶层`tb_top_audio_visual`通过：按真实50MHz/I²S时序运行174.47ms，仅UART和长按阈值加速；真实触摸/红外/吉他、六预设物理S2切换、忙碌中UART设置、返回FFT/曲谱、I²S取样与连续音源相位、曲谱不误重启，以及八张完整PWM面板重建均通过。
- `tools/check_lissajous_panels.py`逐像素核对五种参考画面的外部HUB输出：八字149点、多瓣189点、圆96点、椭圆104点、直线29点，均与独立正弦量化坐标完全一致，无缺点/多点。日志`sim/build/lissajous_controls_geometry.log`。

FFT独立NumPy复核通过：全部128个旋转系数正确，4组输入全部256个复数频点最大分量误差分别为0、4.1111、5.1237、1.0493 LSB。
日志为`sim/build/lissajous_controls_numpy.log`。最终RTL汇总日志为`sim/build/lissajous_controls_final_tests.log`，以上11项RTL全部通过。

六种XY对比预览为`sim/build/lissajous_presets_preview.png`，由外部HUB引脚重建数据生成，已检查图形和REF/AUD标签；并非实物拍摄。
产物、测试、文档的SHA256见`sim/build/lissajous_controls_delivery_manifest.json`。

尚未烧录或进行本版实板测量。上板需确认按键操作、REF/AUD标识、图形比例、HUB色序及演奏到声音/屏幕的响应。
下面保留前版历史记录；当前交付以本节为准。

## 2026-10-17：波形、混音延时XY与实时FFT四画面（历史版本0x0000017C）

S2长按约1秒按“曲谱→波形→延时音频XY（李萨如）→实时FFT频谱→曲谱”循环；
短按松开仍重启下载曲谱。三个分析画面都保留触摸、红外/手势、吉他三组采样幅度条。
曲谱在后台继续推进，各音源、I²S和事件日志无需等待显示分析。操作与范围见
[AUDIO_VISUAL.md](AUDIO_VISUAL.md)。App沿用v1.2，无需新命令或重新安装。

### 最终构建

Gowin V1.9.11.03 Education完成综合、布局布线、时序和位流/仿真网表生成，
结束于2026-10-17 11:54:51（Asia/Shanghai）；日志`sim/build/xy_fft_build3.log`。

| 项目 | 当前结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | **0x0000017C** |
| SHA256 | `C461EAC66773D6A67CF6B5CA314FD956EE2B2B04AED5112F61ADB0506964BF31` |
| 约束 / Fmax | **50.000 / 55.172MHz** |
| Setup / Hold违例 | **0 / 0** |
| 最差Setup Slack | **+1.875ns** |
| Logic | **21515/23040** |
| CLS | **11214/11520** |
| Register | **10098/23280，锁存器0** |
| BSRAM | **56/56** |
| DSP | **23/28** |
| I/O | **41；CST/SDC与前版SHA256相同** |

首轮32位FFT工作区因器件的SDP32/36转换设置超出1块BSRAM；改为16位分时访问，
保留原转换设置。第二轮能放入，50MHz仅余0.018ns；最终将幅值求和、压缩柱高、
频段最大值写入拆成流水级，时序余量改善到1.875ns。中间产物不作为本次交付。
FFT仅增加一个复用乘法器；当前BSRAM已用满，不能直接继续叠加大型缓存。

### 分析链路与验证范围

- 波形：同一I²S帧锁存采样，64列×8采样的极值窗口，显示约10.486ms。
- XY：X为当前混音，Y为32个采样前的混音，固定延时655.36µs；64×32位图双缓冲。
  这是同信号延时XY，不是两个独立声道测相。位图与波形合用一块BSRAM。
- 频谱：CIC3低通/8倍降采样→Hann窗→256点定点FFT→16频段压缩柱高。
  分析采样率6103.515625Hz，频点间隔23.8418579Hz，约0～3.05kHz、约23次更新/秒。
  另一块1024×16 RAM同时保存工作区和旋转系数，实虚部分时访问；分析间隔不阻塞演奏。
- `fft256_init.hex`保存数学旋转系数和零初始化，不含歌曲或预录音频。
  FFT每级缩放1/2，幅度近似为`abs(real)+abs(imag)`，显示抑制≤8LSB底噪。
  CIC高频通带衰减未补偿、柱高未校准为声压级，不能用作精密全频段测量。

| 本轮RTL测试 | 结果与范围 |
| --- | --- |
| `tb_audio_spectrum` | 通过：静音、单音、双音、落在抽取镜像频率的高频抑制，导出4×256个复数FFT频点 |
| `tb_lissajous_delay` | 通过：非周期正负阶跃区分当前X/32采样前Y，轨迹位置、零点和下一帧旧点清除 |
| `tb_display_mode_control` | 通过：四画面循环、长按只执行一次、长按松开不重启、短按松开重启、复位 |
| `tb_audio_visualizer` | 通过：波形极值/双缓冲、分组峰值/衰减、XY点位、真实FFT柱高/间隔/底噪对应像素 |
| `tb_hub75e_audio_display` | 通过：外部HUB引脚的波形/XY像素、FFT首窗前空白、四模式整PWM切换、原133周期行扫描、隐藏曲谱继续下落 |
| `tb_hub75e_rhythm_display` | 通过：原显示扫描/RGB5 PWM、128事件提交和3002组位置运算回归 |
| `tb_top_audio_visual` | 通过：真实I²S采样取点与连续相位、触摸/红外/吉他幅度、实际C4的FFT频段、物理S2四模式循环、隐藏曲谱不中断，重建三张完整PWM画面 |
| `tb_top_voice_bend` | 通过：七键持续发声时分别变调、相位/ADSR保持、平滑回正与独立释音，外部I²S/HUB继续运行 |
| `tb_top_live` | 通过：默认曲谱静音、拒绝旧PCM命令、四/七键独立DDS/ADSR、独立释音、STOP不截断现场音符与最终归零；3820对立体声采样 |

以上9项RTL测试全部通过。独立NumPy FFT检查`tools/check_audio_spectrum.py`通过：全部128个复数旋转系数正确；
4种输入的全部256个复数频点，实部/虚部最大误差分别为0、4.1111、5.1237、1.0493 LSB，
均小于9 LSB门限。日志`sim/build/xy_fft_numpy_final.log`；FFT纯数值测试加速采样使能，
完整顶层仍按真实50MHz、I²S和HUB扫描运行，仅UART/S2长按测试阈值加速。

数值与独立延迟日志分别为`xy_fft_numeric_final.log`、`xy_fft_delay_final.log`，
其余最终回归日志为`sim/build/xy_fft_final_tests.log`。
本轮使用以上针对性测试；后续章节保留之前的完整综合演奏和32复音验收记录。

### 交付追溯与板上验收

45个构建输入（包含FFT初始化数据）的SHA256见`sim/build/xy_fft_source_manifest.json`；
产物与测试记录见`sim/build/xy_fft_delivery_manifest.json`。
前版波形位流0x00000B62及源码保留在`sim/build/pre_xy_fft_20261016/`。

三种画面的PPM来自顶层测试对外部HUB数据/时钟/LAT及完整32相位PWM的重建；
PNG和并排预览由`tools/render_audio_visual_preview.py`生成。
已目视检查最终波形、复合音XY轨迹、频谱柱及下半屏三组音源幅度条。
本轮未烧录实板，未测量实体面板、APDS光学识别、HC05无线或DAC模拟输出。
仍需现场核对S2四画面循环、颜色/行序、纯音XY椭圆、复合音轨迹和谱柱随演奏变化。
可视化未增加音频处理级，但本轮不能证明实物动作到声音≤5ms。
数字效果器、完整音频录音回传及逐动态声部独立显示仍未实现。

## 2026-10-16：最终混音波形与三组音源幅度反馈（历史构建）

在App v1.2独立变调版本上，增加64×64面板音频可视化。上半屏显示送往I²S的最终混音波形，
下半屏分别显示触摸、红外/手势合并组、吉他实际采样幅度。S2长按约1秒切换画面，
短按松开后重启曲谱。隐藏期间曲谱继续推进，切屏不复位音源或I²S。
操作、显示刻度与范围见[AUDIO_VISUAL.md](AUDIO_VISUAL.md)。手机APK沿用v1.2，无需更新。

### 构建与资源

Gowin V1.9.11.03 Education完成综合、布局布线、时序分析、位流及仿真网表生成，
结束时间2026-10-16 17:16:19（Asia/Shanghai），日志`sim/build/audio_visual_build2.log`。

| 项目 | 当前结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | **0x00000B62** |
| 位流SHA256 | `B8BAAE265DCDC3803BCCDC8B6FCB3263D317B88010243A42C3827D4B9F19B2E5` |
| 约束 / Fmax | **50.000 / 51.786MHz** |
| Setup / Hold违例 | **0 / 0** |
| 最差Setup Slack | **+0.690ns** |
| Logic | **20270/23040** |
| CLS | **10869/11520** |
| Register | **9051/23280，锁存器0** |
| BSRAM | **55/56，仅余1块** |
| DSP | **22/28** |
| I/O | **41；CST、SDC与修改前SHA256一致** |

相对独立变调版：Logic增加217、CLS增加79、Register增加90、BSRAM增加1，DSP不变。
128×10bit波形双缓冲使用一块同步RAM，扫描器提前请求下一列，保留133主时钟/行、
25MHz移位时钟及RGB5 PWM。模式和前后台缓冲均在完整32行×32相位边界切换。
音频合成、增益、混音和I²S发送模块源码未改动，显示只是并行读取实际采样。

### 验证证据

| 测试 | 结果与范围 |
| --- | --- |
| `tb_display_mode_control` | 通过：短按松开、长按阈值、按住不重复、长按松开不重启、再次切回和复位 |
| `tb_audio_visualizer` | 通过：64列独立极值窗口、首尾采样、正负满幅与17bit触摸求和、启动遮蔽、前台保持/整帧发布、像素颜色、幅度衰减归零 |
| `tb_hub75e_audio_display` | 通过：外部HUB引脚的交替波形列与同步RAM预取、三组音量条、原133周期扫描、整PWM帧切屏；隐藏曲谱经过750ms后从正确位置恢复 |
| `tb_hub75e_rhythm_display` | 通过：原显示扫描/RGB5 PWM、128事件连续提交、滚动/停止流水边界、3002组位置运算及触摸反馈 |
| `tb_top_audio_visual` | 通过：真实50MHz与I²S、物理S2消抖长短按、实际触摸/红外/吉他幅度；波形取样与I²S帧锁存一致、振荡器相位连续、运行中曲谱两次切屏不重启 |
| `tb_top_voice_bend` | 通过：七路持续发声时UART逐声部变调、相位/包络、平滑回正、释音，外部I²S/HUB连续 |
| `tb_top_live` | 通过：原生产默认静音指引、拒绝旧PCM命令、四/七路独立触摸、独立释音、STOP不截断现场音符 |
| `tb_top_integrated` | 通过：38条UART回复、压力ADC、五音色/四方向/双音组/颤音、吉他及七键+手势+吉他同奏、最终静音；11691对立体声采样、90012次面板行锁存 |

以上8项RTL测试全部通过。前5项日志为`sim/build/audio_visual_final_tests.log`，兼容性回归日志为
`sim/build/audio_visual_compatibility.log`。完整综合演奏输出`decoded_pcm_top_integrated.csv`与
修改前基线文件逐字节一致，包含相同时间戳和全部11691个单声道采样，外部I²S左右声道一致。
这个比较覆盖该固定测试输入序列，不代表实物模拟输出的验收。顶层可视化测试仍使用真实音频帧/面板周期，
仅UART加速至500k、S2长按阈值缩为64帧；默认约1秒的参数由48828帧×20.48µs确定。
红外由真实输入高低电平与1ms滤波触发；此用例没有模拟APDS光学识别。

`sim/build/audio_visual_panel.ppm`由顶层仿真的外部HUB引脚累计32个PWM相位重建，
`audio_visual_panel.png`为其最近邻放大预览，已目视检查波形和三组横条；均不是实物照片。

### 追溯与实物边界

43个构建输入的SHA256见`sim/build/audio_visual_source_manifest.json`，交付产物和测试清单见
`sim/build/audio_visual_delivery_manifest.json`。修改前源码、约束、位流及完整综合演奏基线
保留在`sim/build/pre_audio_visual_20261016/`；旧位流UserCode为0x0000F954。

本轮没有烧录开发板或进行实体屏幕、传感器、DAC模拟输出测试。还需板上核对长短按、
实际颜色/行序、触摸/红外/手势/吉他的声音与画面联动，不能据此宣称整条模拟链路满足5ms。
当前实现最终混音波形和三组采样幅度，尚无FFT频谱、李萨如、每个动态声部的独立可视化、
数字效果器或完整音频录音回传。

## 2026-10-16：App v1.2 七触摸声部独立变调（历史构建）

七个手机滑杆分别调整OUT1～OUT7正在发声及以后触发的音高，范围±1200音分，
支持和弦内只移动某个音，保持DDS相位与ADSR；保留FSR全局比例叠加。
App按最新位置合并拖动、逐条ACK、公平轮流发送；断线保留草稿，清除待发任务。
作用范围、命令、约100ms发送节拍和平滑时间见 [逐声部滑音](VOICE_PITCH.md)。
本节以及下面的ADSR、红外/TDM章节均为历史构建记录，最新产物以上方音频可视化章节为准。

### 最终构建与资源

Gowin V1.9.11.03 Education 完成综合、布局布线、时序分析和位流生成，
结束时间2026-10-16 15:23:41（Asia/Shanghai）。

| 项目 | 当前结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | **0x0000F954** |
| 位流SHA256 | `38D65661387E8F5008BE7C85B5AE11585CD259AFD2F81E896C16EB35CE0EFDFB` |
| 约束 / Fmax | **50.000 / 55.482MHz** |
| Setup / Hold违例 | **0 / 0** |
| 最差Setup Slack | +1.976ns |
| Logic | 20053/23040（约87.04%，工具向上取整88%） |
| CLS | **10790/11520** |
| Register | 8961/23280；锁存器0 |
| BSRAM | **54/56，仅余2个** |
| DSP | **22/28** |
| I/O | 41，CST与修改前逐字节一致，LED等原接线不变 |
| App | v1.2 / versionCode3；`android_app/dist/FPGA-Score-debug.apk` |
| APK SHA256 | `8B3C8207FEC3F5ACAAB9052D84CFDCA06DBD95E1009941AA01819C3A515B9CB8` |

与上版比较：CLS从11513降为10790，DSP从23降为22，BSRAM从38增为54。
节省逻辑以换用块存储器为代价，不能承诺直接叠加大型效果器。

### 架构与时序修正

- 基础MIDI仍限制60～72，相位步进小于2^26。一个26×16乘法器分时完成
  全局FSR和各声部Q2.14比例缩放，每帧最多43个时钟，1024时钟帧预算充足。
- 两个小块RAM保存目标/当前比例，比例每帧最多移动16/16384；
  半倍频到二倍频最大过渡30.72ms，回正到高八度约20.97ms。
  不改MAP、门控、包络、相位；回正同样平滑，松键保留该键偏移。
- 七键MIDI映射改用同步块ROM；触摸正弦查表和增益乘法之间增加每时钟流水寄存器，
  工具将七路正弦表映射为块ROM。相位在音频帧之间稳定，因此逐音频采样值与原实现一致，
  不增加音频帧延迟；该模式要求两个采样使能之间至少两个主时钟，生产间隔为1024。
- ADSR毫秒转换用5次串行乘5计算3125倍，再四舍五入，复用加法器。
  所有0～1000ms值和原实现一致，只增加控制换算时钟，不占音频帧预算。
- 第一轮新增功能超出逻辑上限（`voice_bend_build.log`）；第二轮放入但Fmax仅46.366MHz、
  Setup违例4（`voice_bend_build2.log`），**均不作为当前交付**。
  第三轮修正上述路径并通过50MHz检查，最终日志 `sim/build/voice_bend_build3.log`。

### 验证证据

本轮11种不同RTL测试通过（部分针对最终时序修正重新执行）：

| 测试 | 结果与证据 |
| --- | --- |
| `tb_voice_bend` | 全七键独立目标，半倍/二倍界限，1024个连续有界上升步，FSR叠加、非法值保护、平滑回正、帧间静止 |
| `tb_hc05_bend` | 位级UART，19条回复；键号/比例界限、缺失/多余字段/负号原子拒绝、发声与曲谱忙时仍可调节、回正、ADSR共存 |
| `tb_top_voice_bend`（最终源码重跑） | 真实50MHz与I2S、UART加速500k；七个触摸声部同时持续发声，分别指定两键约±100音分，其余五键准确不变；七路相位持续累加，ADSR不变，HUB锁存及I2S正常；回正与释音归零 |
| `tb_poly_pipeline` | 加流水寄存器后4825帧独立数学正弦/增益/混音检查、12315次未改声部对比，逐采样保持原行为 |
| `tb_midi_block_rom` | 每个键遍历全部256种MIDI地址，与原组合查表精确一致；非法音高输出0 |
| `tb_fsr_modes` | 原FSR两模式及全部32768种全局音高比例回归通过 |
| `tb_runtime_adsr`（修正后重跑） | 0～1000ms全部1001值、保持级、精确A/D/S/R、旧音快照/新音生效、提前释音 |
| `tb_hc05_adsr`（修正后重跑） | 20条UART回复，四参数换算、非法参数拒绝、两音源独立恢复、忙时运行 |
| `tb_hc05_keymap` | 原57条改键/查询/忙保护/异常行回复回归 |
| `tb_hc05_download` | 曲谱原子提交/重试/改键验证，事件日志帧、拒绝PCM命令 |
| `tb_tdm_adsr` | 32声部运行时包络/事件快照/测试模式，最重一帧871时钟，小于1024 |

日志：`sim/build/voice_bend_final_sim.log`、`voice_bend_regression.log`、
`voice_bend_compatibility.log`、`voice_bend_timing_regression.log`。
最终顶层外部I2S采样：`sim/build/decoded_pcm_voice_bend.csv`。
这里用相位步进精确证明目标音高，7.8ms的短I2S捕获不作为七个可分辨FFT峰的证据。
原TEST32频谱证据见历史章节，本轮没有重新执行整套模拟/频谱验收。

App纯JVM测试：VoiceBend **7229**、AdsrProfile **5032**、SongCodec **30**、SPP **56**项断言通过，
覆盖全部2401个音分值、比例误差<0.11音分、离线草稿、拖动合并、轮流发送、
发送中继续编辑、批量快照隔离、异步日志与命令确认。APK已完成编译、签名和Manifest检查。
日志 `sim/build/voice_bend_android_tests.log`、`sim/build/voice_bend_apk.log`。

### 来源、限制与现场验收

FPGA当前41个构建输入的SHA256在 `sim/build/voice_bend_source_manifest.json`；
App的9个构建输入在 `voice_bend_app_source_manifest.json`；交付产物/文档在
`voice_bend_delivery_manifest.json`。修改前源码、约束、App源码和位流保留在
`sim/build/pre_voice_bend_20261016/`。

本轮没有烧录开发板，也没有安装到实体手机或模拟器操作UI；未实测HC05无线传输、
DAC模拟输出、动作到声音延迟。蓝牙发送节拍/串行耗时与平滑时间不满足或证明≤5/10ms门槛，
该门槛仍须本地动作→FPGA→DAC的完整实物测量。

现场装入配套位流和App后，先全部回正，按住C/E/G，只拖对应E的声部：
观察/听取只有E移动，其余保持；再回正，叠加FSR全局滑音。
逐声部接口仅用于七触摸键，红外/手势32动态声部和吉他尚无同类寻址接口。
事件日志不保存BEND/ADSR等设置，不能完整重放含这些控制的演奏。

## 2026-10-16：手机运行时 ADSR 编辑（历史版本）

已为触摸与红外/手势加入两套独立运行时四参数包络。App 支持四滑块、可拖动曲线、
应用与恢复原包络；参数在新音符触发时锁存，正在响和已经排队的音符保持原设置。
用法、指令、保持段/提前释音语义见 [运行时ADSR](ADSR_RUNTIME.md)。原LED、传感器引脚未变。
下面的红外/TDM融合章节保留为历史记录，其资源和位流不代表当前版本。

### 最终构建

Gowin V1.9.11.03 Education 成功完成综合、布局布线、时序分析和位流生成。
结束时间：2026-10-16 13:59:25（Asia/Shanghai）。

| 项目 | 当前结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | `0x00002C7B` |
| 位流 SHA256 | `F5E86F8B20FBB08838D2278477CCBDDE618D79AEC5A007317FBC85958738847C` |
| 约束 / Fmax | **50.000 / 50.718MHz** |
| Setup / Hold 违例 | **0 / 0** |
| Logic | 22864/23040（约99.24%，工具取整显示100%） |
| Register | 9124/23280，无锁存器 |
| CLS | **11513/11520，仅余7个** |
| BSRAM | 38/56 |
| DSP | **23/28**，未因运行时包络增加 |
| APK SHA256 | `8D24181A30F91199603B4B81E4DA63924DB890DE0A85D89C0A1A0E939E0D6299` |

当前位流与源码以 `sim/build/runtime_adsr_source_manifest.json` 的41个工程、构建脚本、
启用RTL和约束文件为准，包含共用的TTP229输入源码。修改前产物在
`sim/build/pre_runtime_adsr_20261016/`。构建日志 `sim/build/runtime_adsr_build.log`。
App已构建并通过签名检查，文件为 `android_app/dist/FPGA-Score-debug.apk`。
逻辑和布线余量已经很小，不能据此承诺还可直接叠加其他大型模块。

### 实现与帧预算

触摸包络继续用线性余量累加，时长计数收窄到16位，每个声部在门控上升沿锁存配置。
红外/手势使用Q24相位、逐段计数与0～256增益，每个声部保存独立配置和ADSR状态；
排队事件同样保存配置快照。提前结束音符会从当前音量进入完整R段。
音色自身的主体/亮度衰减保留，因此包络预览不等于混音后实际声压曲线。

32路TDM新增的包络乘法放在查表时原来空闲的流水线时隙中，没有增加FSM状态。
音源仍共享一颗MULT27X36（两个DSP资源）；每帧现在有约161次乘法发起，
约786万次/秒。32事件压力测试最重帧仍为 **871/1024个50MHz时钟**。
蓝牙命令缓存改为同步BRAM，解析延迟远低于串口字节间隔；原协议和原子性测试继续通过。

### 完成的验证

| 测试 | 结果 |
| --- | --- |
| tb_runtime_adsr | PASS：全部1001个毫秒取值与S比例、恢复、触摸精确A/D/S/R、新旧音符独立、途中松手释音 |
| tb_tdm_adsr | PASS：A4/D4/S128/R8、排队快照、定时松音、TEST32独立包络、32个声部各用不同S值、同时释音；最重871时钟 |
| tb_hc05_adsr | PASS：20条真实UART回复，4字段、上下界/零、格式错误、非法更新不改变状态、忙时配置、分别恢复 |
| tb_top_runtime_adsr | PASS：24.48383ms，1195立体声帧；UART→触摸/IR包络、旧音S50与新音S25共存、复位恢复、外部I²S最终静音和LED扫描 |
| tb_adsr_env | PASS：原固定参数包络106459个精确线性采样及全部边界 |
| tb_hc05_download / tb_hc05_keymap | PASS：原曲谱原子提交、旧PCM命令拒绝、57条协议回复、改键/范围/格式/忙保护 |
| tb_hc05_control_races | PASS：下载/改键竞争与完成响应归属 |
| tb_tdm_queue / tb_sensor_poly_audio | PASS：FIFO64、替换/饱和/超时诊断、双输入事件及背压 |
| tb_top_ir_tdm（当前源码复验） | PASS：101.27518ms、4945个PCM采样；八IR与同拍手势、七键、UART TEST32及32路独立频率，原数字首音延迟1.833911ms未变 |
| Android AdsrProfile | PASS：5032项参数、预览几何、拖动控制点及边界断言 |
| Android SongCodec / SppLink | PASS：30 / 48项断言，包含ADSR和恢复指令的ACK传输 |

详细日志分别在 `sim/build/runtime_adsr_units.log`、`runtime_adsr_poly32.log`、
`runtime_adsr_protocol.log`、`runtime_adsr_initial.log`、`runtime_adsr_top.log`、
`runtime_adsr_android_tests.log`、`runtime_adsr_apk.log`。

最新TEST32外部I²S解码FFT仍得到32个独立对应主峰，单峰幅值510.013～513.972LSB，
最大绝对采样16289，无削顶。数据/图见 `sim/build/runtime_adsr_test32_spectrum.json` / `.csv` / `.png`，
检查日志 `sim/build/runtime_adsr_spectrum.log`。

测试与构建完成不代表板卡模拟链路验收。本次未烧录板卡，未测手机触屏实际手感、
HC-05实机连接、DAC模拟输出或总演奏延迟；基础≤10ms/拓展≤5ms仍需实测。

---


## 2026-10-16：八路红外与 32 复音 TDM

这是当前版本；后面的 2026-10-15 章节是历史记录。
完整引脚、基础/拓展要求状态、评分口径和现场标准见
[赛题验收表](PIN_FUNCTION_REQUIREMENTS.md)。原 33 个引脚分配全部保留，
新增 8 个红外输入，无重复球号，ADC J8/K8 保留。

### 构建产物与资源

Gowin V1.9.11.03 Education `run all` 成功完成综合、布局布线、时序分析和位流生成。
本次成功构建结束于 2026-10-16 12:12:54（Asia/Shanghai）。

| 项目 | 当前结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | `0x0000592C` |
| 位流 SHA256 | `40B0B67D9231B980108D69EAE6E492DECDE944B6FC370A6D2634FE4F6C07FCE9` |
| 约束 / Actual Fmax | 50.000 / **53.257MHz** |
| Setup / Hold 违例端点 | **0 / 0** |
| Logic | 21960/23040（96%） |
| Register | 7866/23280（34%），无锁存器 |
| CLS | 11262/11520（98%） |
| BSRAM | 25/56（45%） |
| DSP | **23/28（83%）**，上一版为28/28 |
| ADC | 1/1 |
| APK | `android_app/dist/FPGA-Score-debug.apk` |
| APK SHA256 | `EC807D78F24FCA36BB76247948620B532C1F08A02F8D4EC479C677CAE2D7728A` |

构建日志 `sim/build/ir_tdm_build.log`，PNR 报告 `impl/pnr/PCM5102_PAM8403.rpt.txt`，
时序报告正文 `impl/pnr/PCM5102_PAM8403_tr_content.html`，
43个工程/源码/约束文件的校验清单 `sim/build/ir_tdm_source_manifest.json`。
修改前位流及关键源码备份在 `sim/build/pre_ir_tdm_merge/`。
本次开发期间曾出现逻辑超限和专用 I²C 管脚冲突，均已修正；只有上述成功构建作为交付。

### DSP 为什么仍然不是整机两个

`u_gesture/u_audio/u_synth` 的 32 个声部共享唯一 `mul_a*mul_b` 运算路径，
综合层次报表显示一颗 `MULT27X36`，对应两个 DSP 资源。
这次采用的是红外/手势音源的 TDM 改造；保留的七路触摸 DDS/ADSR 仍为并行架构，
另有 FSR 映射/缩放、APDS 方向强度计算、命令解析及屏幕位置换算等乘法。
整机资源由全部模块和综合映射共同决定：不能把音源的理论乘法吞吐预算直接当作整机占用。
具体层次证据为 `impl/gwsynthesis/PCM5102_PAM8403_syn_rsc.xml`，
全局原语为 MULTALU27X18×13、MULT27X36×3、MULT12X12×4、MULTADDALU12X12×2，
最终物理资源按 PNR 报告的23/28计，不把不同粒度原语简单相加。
CLS 仅剩258个，当前限制仍是逻辑/布线余量，继续加效果器前需要继续优化。

这里实际主时钟是50MHz。当前引擎每声部逐帧发起音高、主体包络、亮度包络、
总增益四次乘法，另有一次全局LFO乘法：129×48828.125约为630万次/秒。
乘法发起量占50MHz周期约12.6%，但上下文访存、查表、流水线等待与事件分配也消耗时钟；
队列测试最重帧871周期，占1024周期预算的85.1%。不能只按乘法次数推断整个引擎只忙5%。

### 验证范围

- 红外：两级同步、双边1ms滤波、初次通光准备、保持遮挡不重发、同时8路和256种输入子集。
- TDM：FIFO64、每帧最多32次分配、最老声部替换、帧快照、正负饱和、溢出/超时诊断。
- 生产顶层：真实50MHz/1ms红外滤波、八路IR与同拍手势、触摸并发、UART TEST32、外部I²S解码和屏幕活动。
- 蓝牙/FSR：命令范围与格式、音符曲谱/静音指引、压力模式；安卓 SongCodec30和SppLink40项断言。

已完成的新回归：

| 测试 | 结果 |
| --- | --- |
| tb_ir_strings | PASS：全部256种同时触发子集、滤波/重新准备/复位 |
| tb_tdm_queue | PASS：64条队列、32声部、饱和和超时诊断，最坏871/1024时钟 |
| tb_sensor_poly_audio | PASS：APDS未就绪时红外独立发声、同拍事件、音色锁存、背压/缓存满/溢出/复位 |
| tb_top_ir_tdm | PASS：101.27518ms仿真、4945个PCM采样，八路IR+同拍手势、七键并发、真实UART TEST32与32个独立频率上下文 |
| tb_hc05_control_races | PASS：下载验证期间锁定映射和完成响应竞争 |
| tb_hc05_keymap | PASS：57条回复、全部键位/音高、错误格式/范围、忙保护 |
| tb_fsr_modes | PASS：1024个ADC码、32768种比例×七键、模式/平滑/复位 |
| tb_top_integrated | PASS：239.43324ms，38条UART回复、11691立体声帧、90012次面板行锁存；五音色/颤音、FSR、七键+手势+吉他并发无削顶、最终静音 |
| tb_top_live | PASS：78.24125ms，3820立体声帧；四/七键独立DDS/ADSR及释音、STOP保留按住的音符、曲谱指引无自动音频 |
| tb_top_idle，PNR网表 | PASS：生产参数2.8ms，136立体声帧；新IR输入明确拉高，S1/S2不触发自动音频；无SDF |
| Android core | PASS：SongCodec30项、SppLink40项；APK构建和签名检查成功 |

`tb_top_ir_tdm` 的数字边沿到首个外部I²S非零采样为 **1,833,911ns**，
场景为八路红外与同拍手势，未包含接收器本体/光学动作和DAC延迟。
从其I²S外部引脚解码结果末尾4096个稳定采样做FFT：**32个对应独立主峰**，
每峰幅值510.013～513.972LSB，混音最大绝对值16289，未削顶。
标称Fs=48828.125Hz，32路吞吐量1562500振荡器采样/秒。
PNR静音仿真使用厂商原语模型，模型有RAM位宽告警；外部I²S和静音断言通过。
早先一轮未显式连接IR的重复网表仿真已停止，不计通过；上表对应修正后完整完成的测试。

图为 [TEST32数字频谱](sim/build/test32_spectrum.png)，
原始采样 `sim/build/decoded_pcm_top_ir_tdm.csv`，逐频率表和数据为
`sim/build/test32_spectrum.csv` / `.json`，检查脚本 `tools/check_test32_spectrum.py`。
这份频谱是数字仿真结果，**不是板卡DAC模拟输出的32谱峰验收证据**。

本次没有烧录板卡、模拟音频采集、
手机蓝牙实机连接或环境光/手势实测。数字I²S首个非零采样延迟不含传感器和DAC，
亦不等于可闻响度阈值下的演奏延迟；基础≤10ms和拓展≤5ms均需现场验证。

---


最近更新：2026-10-15（Asia/Shanghai）。

## 2026-10-15 18:18：触摸、压力、手势、吉他、蓝牙与 64×64 屏幕融合

本节为2026-10-15历史融合版本。继续使用本目录 `PCM5102_PAM8403.gprj` 和 `top`，
保留七键独立 DDS/ADSR、FSR 音量/音高、HC-05 改键/曲谱/事件日志、安卓 App 和
64×64 HUB75E 七轨指引；增加 APDS-9960 四方向手势、五种手势音色、颤音、
高低两组手势音符及 Karplus–Strong 单弦吉他。独立红外对管按用户要求留待后续。

S1/S2 仍为曲谱开始/停止与重启。新增 `GUITAR`、`TONE,0..4`、
`VIBRATO,0/1`、`BANK,0/1` 由 HC-05 和安卓 App 控制；范围与单字符格式见
[融合说明](SENSOR_INTEGRATION.md)。生产默认 `ENABLE_DEMO_SCORE=0`，
曲谱只用于指引，触摸、手势和拨弦命令触发 FPGA 实时合成，不使用预录 PCM。

### 最终构建

Gowin V1.9.11.03 Education `run all` 完成综合、布局布线与位流生成，
稳定源码最终构建结束时间为 **2026-10-15 18:18:08**。

| 项目 | 当前融合结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | **0x0000A240** |
| 主时钟约束 / Actual Fmax | **50.000 / 51.018MHz** |
| Setup / Hold 违例端点 | **0 / 0** |
| Logic | 21776 / 23040（95%） |
| Register | 7014 / 23280（31%），无锁存器 |
| CLS | 11136 / 11520（97%） |
| BSRAM | 8 / 56（15%） |
| DSP | 28 / 28（100%） |

位流 SHA256：`296BDA6C8DAB31621A31CDD160F706C90E47239249A58961E6403361BB43EB39`。
构建日志：`sim/build/sensor_merge_final_build.log`。35 个工程/约束/源码文件的
SHA256 清单：`sim/build/sensor_merge_source_manifest.json`。

APDS 的 SCL/SDA 新增为 H4/G4（J3 第23/24脚），其余信号引脚保持原配置。
34 个启用工程文件均存在，33 个显式 IO_LOC 无重复，片内 ADC 的 J8/K8 未冲突。
I²C SDA 增加两级同步，只对第一同步级添加输入 false path；没有放宽 50MHz
内部时序或 ADC 时钟约束。原有未用演示声部被优化移除提示、五处曲谱/显示位宽提示
仍存在：预览延迟最多1500ms、运动相位小于1500、距离最多79499、目标行2～54，
在目标位宽范围内。新增音源没有引入其他综合警告。

资源余量为 CLS 384、Logic 1264、DSP 0，主时钟时序余量约2%。后续红外或其他
功能必须重新核对资源与时序，新增乘法音源需要先优化资源。
融合前的位流/功能网表/报告保存在 `sim/build/pre_sensor_merge_20261015/`。

### 本轮验证

- `tb_top_integrated` 完整联合仿真通过：38条位级UART回复、11447对外部I²S立体声、
  88133次完整64列屏幕行锁存，仿真234.43612ms。覆盖曲谱/屏幕/S1/S2、七键ADSR、
  实际ADC握手下的力度峰值1229/308与一八度变调、全部四方向/双音符组/五音色/颤音、
  吉他出声/衰减、七键+手势+吉他无削顶混音和最终严格静音。
  手势注入的是识别后的事件；测试缩短预滚到60ms、UART500kbaud、触摸1ms、
  ADSR4/4/32帧、FSR快速slew、手势400帧、吉他长度8/损耗移位2；
  50MHz时钟、I²S、ADC转换及屏幕扫描仍用真实时序。生产参数未改变。
  日志 `sim/build/tb_top_integrated.log`；独立PCM路径已加入脚本，
  本轮并行测试曾共用CSV路径，验收引用测试内存断言及PASS日志。
- 原有 `tb_top_live`、`tb_top_idle`、`tb_hc05_keymap`、`tb_hc05_download`、
  `tb_hc05_control_races`、`tb_hub75e_rhythm_display`、`tb_downloadable_song` 均通过；
  包括3820对现场演奏I²S、57条原改键协议回复、原子下载/中断保旧、日志分流、
  生产1500ms指引、128连续事件、3002组显示流水边界/算术检查。
  本组日志 `sim/build/merge_core_final_regression.log`。
- `tb_top_touch_response` 以生产2ms音符防抖、20ms模式防抖与98/3906/39321/488帧
  触摸ADSR通过七键、短噪声、独立释放/重触发及模式长按回归；7491对立体声，
  FPGA OUT 输入到首个PCM最大1.884151ms、松键到确认静音最大11.950392ms。
  这些仿真延迟不包含 TTP229 扫描和 DAC/功放模拟链路。仅上电等待缩短为3ms。
- `tb_fsr_modes` 通过1024码压力标定、模式切换/长按/复位、64-LSB平滑步进及七键
  全32768种音高比例检查；`tb_performance_logger` 通过事件、压力、FIFO64溢出与结束标记。
  日志 `sim/build/merge_unit_final_regression.log`。
- 新音源与控制单元：`tb_karplus`（40000个独立递推参考样本）、
  `tb_karplus_external`（单周期/跨帧/反馈周期触发）、`tb_gesture_audio`（原按键模式）、
  `tb_gesture_external_control`（默认PCM一致、双音符组、五音色、颤音、锁存与静音）、
  `tb_gesture_nco_pipeline`（1024帧数值一致）均通过。
- I²C 引脚级：`tb_i2c_master_bus` 在50MHz/100kHz下通过写ACK、重复起始、两字节读、
  主机ACK/NACK和缺设备NACK；`tb_apds_nack` 通过加速初始化下的三次NACK重试，
  未就绪时无假手势。两项测试不代表已经完成真实 APDS 的 FIFO/光学识别验收。
- 最终布局布线后的功能网表：`./tools/run_sim.ps1 -Netlist -Tests tb_top_idle`
  通过，生产参数下 S1/S2 不触发音频，外部 I²S 解码136对立体声，仿真至2.8ms。
  日志 `sim/build/tb_top_idle_netlist_quick.log`；本项没有加载SDF延迟，内部时序按上述STA验收。
- 安卓：JVM曲谱30项、串口40项断言通过，含新增控制确认与异步日志分流。
  原构建脚本完成 javac/D8/aapt2/zipalign/apksigner、Manifest 与签名验证；
  APK 内 DEX 与独立空目录重新编译的 DEX 一致。

APK：`android_app/dist/FPGA-Score-debug.apk`；SHA256：
`195768EB30518C0F75EE84FDBD61B95CC54541A8E836E18D5E60B3DEAD869122`。

本机受限沙盒内 Icarus 12/14、aapt2、zipalign 写文件曾返回访问冲突
`0xC0000005`。自动审批后在宿主环境执行相同标准脚本成功，没有忽略编译退出码，
也没有修改 SDK 或将崩溃生成的文件作为最终验收结果。

本轮完成通过18项RTL测试与1项PNR功能网表测试。原批次在前8项通过后进入
`tb_top_fsr_modes`（`ENABLE_DEMO_SCORE=1` 的开发自动演奏频谱长测试）；
该项在生产配置验证完成后被人工停止，**不计作通过**，本轮没有复验这一开发模式。
因此 `merge_core_final_regression.log` 末尾的该项非零退出来自人工停止；
生产压力路径由联合I²S/ADC测试、生产触摸回归与上述全比例压力单元测试覆盖。
原批次最后的事件日志测试已单独正常运行通过，没有留下运行中的仿真任务。

本轮未烧录实体 FPGA，未连接实物 APDS/FSR/面板/喇叭或真实安卓手机。
日志仍只记录触摸/压力，不包含手势和吉他；APDS 运行中掉电后需重新上电/复位系统，
没有自动恢复初始化或 I²C 卡总线恢复。完整操作与边界见融合说明。

以下为融合前的构建历史；其中旧位流、资源和“当前版本”措辞只适用于各节日期。

## 2026-10-15 17:13：安卓 HC-05 曲谱下载与 HUB75E 指引

本节为当前版本。已接通：安卓选择 CSV/MIDI 或内置示例 → HC-05 逐行确认 → FPGA 双 bank 曲谱 RAM → 1500ms 前瞻 → 64×64 HUB75E 七轨下落指引。声音仍由现场触摸驱动七路独立 DDS/ADSR 实时混音，生产 `ENABLE_DEMO_SCORE=0`。

新增 `SONG_CHORD,index,mask,duration`；13位十进制音高位图对应MIDI60～72，0表示休止。兼容原 `SONG_NOTE`。最多128条，每条1～60000ms；END和PLAY检查当前七键覆盖，失败或未提交时保留原谱。下载后断开蓝牙，S1开始/停止、S2重启指引；RAM掉电丢失。

### 当前位流

Gowin V1.9.11.03 Education `run all` 成功，2026-10-15 **17:13:34** 生成：

| 项目 | 当前结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | **0x0000D3D4** |
| 50MHz约束 / Actual Fmax | **50.000 / 53.046MHz** |
| Setup / Hold违例端点 | **0 / 0** |
| Logic | 15714 / 23040（69%） |
| Register | 5690 / 23280（25%） |
| CLS | 9234 / 11520（81%） |
| BSRAM | 7 / 56（13%） |
| DSP | 14 / 28（50%） |

位流SHA256：`748542A5C75209DD213D3C3B20472B629F57A4D1D632C5A7149D9AA50F817525`。
构建日志：`sim/build/score_screen_final_build.log`。本轮新增HUB75E引脚约束，已检查工程文件引用和物理引脚无重复；SDC仍为原50MHz约束，没有放宽内部时序。

初次显示集成的组合位置计算曾只有39.653MHz；已改为三级常量比较/减法流水，补偿在途滚动并通过回归。中间位流 `0x0000A4B4` 不用于烧录，已被上述通过时序的位流覆盖。更早 `0x00006013` 没有屏幕集成；`0x00009C48` 为已撤回的预录PCM版。

### 安卓安装包

`android_app/dist/FPGA-Score-debug.apk`，Android10+，本地调试签名，已执行javac、D8、aapt2、zipalign、apksigner及Manifest验证。
APK SHA256：`688CA47F3BE1A7ECDABBF5B693A6BFC80CF695629488045866DBB6670CDB3688`。
手机先在系统配对现有HC-05，App读取已配对设备并使用经典SPP。Android12+申请附近设备权限，不申请定位或整盘访问。
支持CSV/标准MIDI0/1、tempo、和弦/休止、七键覆盖检查、逐条ACK下载、改键、PLAY/STOP和事件日志导出；4秒超时或断线会终止会话，重连后从BEGIN完整重传。

### 实际验证

- `tb_top_live`：最终流水源码、真实50MHz/I²S、加速UART，检查UART下载到外部HUB引脚出现下落像素，4/7键独立合成、单路释放、STOP保留仍按住的现场音、最终静音；3820对立体声采样，78.24125ms场景。仅将指引预滚改为60ms加速集成仿真，生产保持1500ms。
- `tb_hub75e_rhythm_display`：生产1500ms参数，外部64列/32行、RGB建立/消隐/行地址/LAT顺序、5位PWM；750/1500ms位置，128个连续周期输入对应128次提交；每个流水阶段分别遇滚动/STOP，以及3002组相位/时长算术检查均通过。
- `tb_downloadable_song`：原子双bank、乱序/重发、缺失/范围、全部和弦音高覆盖、休止、1500ms预滚、连续1ms与128事件、背压修正和STOP/restart。
- `tb_hc05_control_races`：硬件S1验证期间锁定MAP；新UART请求首拍忽略旧完成脉冲。分别移除两项修复的临时副本均重现失败，正式代码通过。
- `tb_hc05_download` / `tb_hc05_keymap`：UART原子下载、中断保旧、和弦/休止、键位覆盖/范围、57条原协议回复、录制MAP/初始/最终EVT及结束标记、预录音频命令拒绝。
- 安卓纯JVM测试：30项曲谱断言、15项串口线程断言；含真实MIDI字节、tempo、前中尾休止、容量/音域拒绝、异步溢出通知与ACK分流、取消/EOF/超时及迟到回复隔离。
- `git diff --check` 通过；无锁存器。构建含关闭声部被优化移除提示，以及5处位宽截断提示：已核对预览延迟不超过1500ms、运动相位小于1500、距离最多79499、目标行2～54，均在目标位宽内；对应算术与时序边界已纳入上述测试。

日志：`sim/build/score_screen_final_regression.log`、`panel_pipeline_final.log`、`score_integration_regression.log`、`android_score_tests.log`。

### 当前边界

尚未在真实安卓手机连接HC-05，未烧录实体FPGA或验证面板/喇叭；本轮没有执行完整PNR网表或SDF延迟仿真。APK构建、RTL与STA不能代替板上联调。
当前从手机文件下载曲谱，没有互联网曲库服务。屏幕没有计分、命中判定和长音尾条；MIDI按音高集合分段，跨和弦边界持续的键可能重复显示头部，不能等同完整逐声部音游谱面。
事件日志可导出，但音频录音回传及手机声音重建尚未实现；FSR统一变调、ADSR编译期配置等边界延续原实现。

下文为更早构建的历史记录，位流与“尚未接入”等状态仅适用于其记录时点。

## 2026-10-15：撤回预录 PCM 路线，恢复现场实时合成

用户明确赛题要求：所有输出由 FPGA 根据实时演奏指令逐音、逐样本生成，基础复音数 ≥4，支持实时变调、ADSR 与混音，禁止预录 PCM 播放、预置推流及整段录音触发。
此前将用户音频转为 PCM 下载播放属于错误实现方向；**UserCode=0x00009C48 已撤回，不用于比赛或本轮验收**。
其历史 SHA256 为 `069C75FE4C39B51446883BE58BD5F3A5704E7A7BE81AD18A7A99A260AAD6C9D5`；旧 Fmax=55.433MHz 等结果只属于该已撤回构建，不能当作修正版结果。

修正版源码：删除预录 PCM 播放器、命令入口、上传/转换工具和试听产物；PCM5102 继续用于 FPGA 实时合成采样的 DAC 输出。
现场 K1～K7 各自保留独立 DDS/ADSR 并实时混音。生产默认 `ENABLE_DEMO_SCORE=0`，禁止下载谱及内置曲谱自动发声。
保留 `SONG_*` 音符/时长下载和 `REC_*` 演奏事件记录；自动曲谱只用于时序指导或主动开启的开发试听，不能替代现场演奏验收。

### 修正版构建与回归

Gowin V1.9.11.03 Education `run all` 成功，2026-10-15 13:41:51（Asia/Shanghai）重新生成同路径位流。

| 项目 | 修正版结果 |
| --- | --- |
| 位流 | `impl/pnr/PCM5102_PAM8403.fs` |
| UserCode | **0x00006013** |
| 50MHz 约束 / Actual Fmax | **50.000 / 57.332MHz** |
| Setup / Hold 违例端点 | **0 / 0** |
| Logic | 13469 / 23040（59%） |
| Register | 4872 / 23280（21%） |
| BSRAM | 7 / 56（13%） |
| DSP | 13.5 / 28（49%） |

SHA256：`61FCE559BFA84E00CE34324DD73E1BC4561FDFBC0F0B246EB01A78330BCB67B1`。
构建日志：`sim/build/live_synth_build.log`。引脚与 SDC 未改，未放宽内部时序。
生产源码和工程列表不再包含预录采样播放器；旧位流已由本次新构建覆盖。

本次实际执行通过：

- `tb_top_live`：生产默认自动曲谱静音，S1/S2 无触摸不出声；四个旧 PCM 命令均 `ERR,CMD`；下载谱仅推进 guide；4/7 键独立 DDS、ADSR sustain/单键 release、STOP 不切断触摸声、最终静音。17.25ms 场景检查 842 对外部 I²S 立体声采样及其时钟/格式。
- `tb_top_idle`：完整生产默认参数，S1/S2 长按不产生音频，136 对外部 I²S 立体声帧；该无参数测试同时用作生产网表的默认 smoke 入口，本轮仅执行了 RTL 版本。
- `tb_poly_synth`：4825 帧数学参考、12315 次未操作声部逐样本比较，四路并发、单路改音/释放/重触发不干扰其余声部，最后静音。
- `tb_dds_voice`：1024 个数学波形地址与 8203 次实时相位/采样使能检查，变调不清相位。
- `tb_adsr_env`：106459 个精确线性包络样本，中途释放/重触发/CE 停止与参数边界。
- `tb_audio_mixer`：1011 组实时求和、正负饱和、抵消、缩放与随机向量。
- `tb_hc05_download`：曲谱原子提交/中断保旧/键位覆盖/范围、预录采样命令拒绝、录制首 MAP/初始与最终 EVT/REC_END、录制映射锁。
- `tb_downloadable_song`：128 条边界、重复索引、缺失/越界、键位覆盖、计时与 STOP。
- `tb_performance_logger`：按压/长按/松键/多键、20ms 表达状态、FIFO64、溢出与满 FIFO 时的最终状态。
- `tb_hc05_keymap`：57 条原协议回复、七键/13 半音、忙保护、查询排队、长度/错帧恢复和默认映射复位。

本次未下载实体 FPGA，未新增喇叭听音或板上多键并发验收。源码、RTL 与内部 STA 结果不能代替完整赛题验收。

### 验收边界

- 单键按住时可实时变调；复音时 FSR 统一影响七键，尚无逐声部选择接口。
- 每声部 ADSR 实时运行，但 A/D/S/R 参数目前编译期配置，没有运行时设置命令。
- 曲谱模块可产生七位应按键信号，HUB75E 屏幕扫描与前瞻谱面调度尚未接入。
- MP3/FLAC 不能直接提供准确谱面；需人工制谱或离线转谱后校对音高、起音和时长。
- 移除违规播放路径不等于全部赛题功能已验收。真实触摸扫描、ADC 标定、DAC/功放声音及整机输入到出声延迟仍需板上验证。

下文为此前版本的历史记录，含自动曲谱/试听模式及旧位流；其中“当前”“最新”等字样仅指各记录当时，不代表本轮修正版。历史自动演奏结果不作为现场实时演奏验收。

## 2026-10-14：HC-05 手机修改七键映射

在原 `PCM5102_PAM8403.gprj` 集成第 1 阶段。新增 `uart_8n1.v`、`hc05_keymap.v`、`midi_note_lut.v`，
更新顶层、运行时压力缩放、F1/F2 约束和仿真入口；详细文件清单和手机操作见 [HC05_KEYMAP.md](HC05_KEYMAP.md)。
支持 `PING`、`MAP?`、`MAP,1,67`、`MAP_RESET`，每条命令追加 CR/LF/CRLF。
键号 1～7，MIDI 60～72；默认 60/62/64/65/67/69/71。歌曲、音符键、释放尾音或录制保护有效时拒绝写入。
录制功能尚不存在，其保护接口固定为 0；重新下载/断电恢复默认，不保存到 Flash。

### 布局布线与时序

Gowin V1.9.11.03 Education 综合、布局布线和位流生成成功。没有改动采样分频、DDS、ADSR、混音或 I²S 源码。
查表输出和共用压力乘法通路均有寄存器级，新增 UART 继续使用原 50MHz 时钟。
仅为 UART 第一级异步同步寄存器增加 SDC 例外，没有放宽内部路径。

| 项目 | 改动前 | HC-05 改键版 |
| --- | --- | --- |
| 时钟约束 | 50MHz / 20ns | 50MHz / 20ns |
| Actual Fmax | 56.344MHz | **57.409MHz** |
| Setup / Hold TNS | 0 / 0 | **0 / 0** |
| Setup / Hold 违规端点 | 0 / 0 | **0 / 0** |
| 最小 Setup / Hold 裕量 | — | **2.581ns / 0.236ns** |
| Logic | 11144/23040 | 12351/23040 |
| Register | 3185/23280 | 3921/23280 |
| DSP | 21/28 | **16.5/28** |
| BSRAM | 0/56 | 1/56 |

最差 Setup 路径仍在原歌曲 ADSR 到增益乘法器之间；新增串口和查表未成为最差路径。
引脚报告确认 `hc05_rx=F2`、`hc05_tx=F1`，BANK5 / LVCMOS33，其余音频、触摸和 ADC 约束保留。
综合只有关闭的第八触摸声部被优化移除的 NL0002 提示，未出现 EX3791 位宽警告。

位流：`impl/pnr/PCM5102_PAM8403.fs`；UserCode=`0x0000A575`，2026-10-14 20:06 生成。
SHA256：`F2CC529B032C229C2176F7F0C22F85CE924735791AFDE39A3203E2BAEEE8E958`。
构建日志：`sim/build/keymap_gowin_build.log`；改动前的位流/报告保存在 `sim/build/keymap_before/`。

### 仿真记录

- `tb_hc05_keymap -Quick`：57 条回复通过；四条命令、七个键、13 个半音、音符/键号范围、歌曲/按键/录制保护、
  查询连发、CR/LF/CRLF、空行、超长/二进制/未结束命令、坏停止位恢复及复位。
  13 个音符均按十二平均律公式核对 DDS 增量；压力半比例和默认恢复正确。
- `tb_uart_8n1 -Quick`：真实 50MHz/9600 分频通过 256 字节/连续帧、±2% 波特率偏差、假起始位、队列溢出清除及行边界恢复、错误停止位和后缀丢弃。
- `tb_fsr_modes -Quick`：32768 种比例 × 七个默认音符全部通过；中性模式、精确原始音高、低八度、平滑变化、K8 启动/短脉冲/长按/释放确认通过。
  额外验证帧边沿更新的压力比例在本轮立即使用，全部七音无额外帧延迟；无帧脉冲时输出保持。

- `tb_top_hc05_map -Quick`：3935 个完整立体声帧通过。真实 50MHz/I²S 周期，UART 联合测试加速到 500000；生产 UART 的 9600 分频由独立 UART 测试验证。
  第 1 键改为 G4、恢复 C4、映射上限 C5、C5 重压降至 C4 均通过频谱/相位增量检查，振幅分别为 1228.49、1225.94、1228.13、1225.83。
  持续检查 DDS 相位累加，未发生重置/跳帧；按住键、同步原始按键及歌曲播放时的修改保护，播放中 PING、K8 不发声均通过。

- `tb_top -Quick`：本次进程退出 0，3205 个完整立体声帧通过，S1 起音延迟 **1.105484ms**，与改动前记录相同；首段旋律、S1 长按/停止与释放、S2 启动/重播、I²S 格式通过。

- `tb_top_touch_response -Quick`：7491 个立体声帧，七个键和多键重触发全部通过，最大起音 **1.884151ms**、松键到严格静音 **11.950392ms**，与改动前记录相同；2ms 音符键、20ms 模式键、488 帧释放均使用生产默认值。
  此项和歌曲回归在最后的 UART 同步预取修正前完成；之后音频路径、按键逻辑、参数和采样分频没有改动。
  同步预取修正后重新通过 UART、57 条命令及联合音频测试。

### 同步 RAM 预取修正

额外检查实际 PNR SDPB 模型时，发现异步形式的 FIFO 读法在空队列首次入队时会提前给出旧数据。
修复前的原始模型记录首字节为 `0x00`，而发送的是 `0x50`（P）；RTL 测试没有暴露此问题。
已改成明确的同步读取与有效标志：入队后再预取，字节有效后才交给解析器，避免同地址写入/读取碰撞。
满队列收到新字节时丢弃损坏输入并回复错误，不依赖碰撞时 RAM 的不确定行为。

最终位流重新生成；`tools/run_hc05_pnr.ps1` 正常退出，实际 PNR 串口模型在 50MHz/9600 下通过。
所有八个命令字母均正确，包括空队列首次入队及前一回复期间的查询排队，完整回复为 `PONG` 和 `MAP,60,62,64,65,67,69,71`。
诊断副本保留原始 UART/解析器/RAM 的 430 个时钟输入，其他模块时钟停止以限定运行范围；生产网表未改动。
这是串口和同步 RAM 的功能复核，不是完整音频 PNR 或 SDF 延迟仿真。
本阶段全部检查已完成，无需下载中间版本；当前应使用 UserCode=`0x0000A575` 的位流。
本次未下载到开发板，尚需用户按改键说明进行手机接收回复与喇叭验收。

## 2026-10-12：缩短 1～7 键响应和松键尾音

用户反馈“1～7 键发声慢，或松开后拖音”。此前音符键使用 20 个 1ms 采样确认，
按下和松开均额外等待约 19～20ms，松开后又有 4883 帧（100.00384ms）释放。
本次只为现场音符键缩短这两项；按下仍保留约 2ms Attack，尾音用渐弱避免硬切。

| 参数 / 路径 | 此前 | 当前 |
| --- | --- | --- |
| 1～7 键按下和松开确认 | 20 个 1ms 采样 | 两个 1ms 采样，边沿等待约 1～2ms |
| 1～7 键 Release | 4883 帧，100.00384ms | 488 帧，9.99424ms |
| 8 键模式确认 | 20 个 1ms 采样 | 保持原值 |
| 歌曲 Release | 4883 帧，100.00384ms | 保持原值 |

顶层两次实例化共享 `ttp229_gpio_input.v`，分别读取音符键和模式键，未使用的输入按实际极性置为闲置。
两个实例继续使用双级同步及 600ms 启动等待，共享源文件和屏幕工程参数未改。
新增 `TOUCH_MODE_DEBOUNCE_MS`、`TOUCH_ADSR_RELEASE_SAMPLES`；压力音量/音高方向、引脚和 DDS 相位策略沿用。
SDC 为模式键的第一级同步寄存器补齐异步输入例外，报告确认该约束已生效，第二级仍参与正常时序分析。

`tb_fsr_modes` 重跑通过：两种模式全部 1024 个压力码、七音全部 32768 个比例、原音/低八度端点、
模式使能/平滑/复位，以及启动已按住、短脉冲、长按和无新 ADC 数据时切换。

新增 `tb_top_touch_response` 在真实 50MHz / I²S 时钟下使用生产默认输入确认和 ADSR，
只将一次性的上电等待缩短到 3ms。完整通过 7491 个立体声帧，覆盖：

- 每个 1～7 键 OUT 边沿到门控、首次非零外部 I²S PCM，以及松开到包络归零/严格数字静音。
- 0.3ms 音符噪声脉冲拒绝、单键释放后在尾音期间快速重按，其余六个按住的声部保持发声。
- 默认 20ms 模式键的短按拒绝、长按一次、2ms 短松开不能重新触发、确认松开后再次切换，模式键不发声。
- 外部 I²S 的 BCK/LRCK 周期、16bit 样本/32bit 槽、立体声一致、最终静音及无混音削顶。
- 核对歌曲仍使用 4883 帧释放；本场景未播放或重新验证完整歌曲。

本场景键 1 的首次 PCM 等待 1.644451ms，键 2～7 均为 1.884151ms；
七键松开到确认静音均为 11.950392ms。Release 归零后等待六帧排空音频流水，再核对后续八帧全零，
避免将正弦过零点误当成静音。上述最大值是本次数字仿真结果，不包含 TTP229 感应/扫描、DAC 滤波或功放。
[TTP229-BSF 原厂手册第 5 页](https://www.tontek.com.tw/uploads/product/97/TTP229-BSF_V1.1_EN.pdf)列出的
8 键正常工作输出响应典型值为 16ms，休眠唤醒取决于扫描设置；实际触摸到喇叭总延迟仍需上板测量。

三个既有音频场景 `tb_top_touch`、`tb_top_fsr`、`tb_top_fsr_modes` 已更新缩短参数并通过编译；
本次未重跑其七音/压力频谱长场景、全曲或 PnR 动态网表仿真。此前结果保留在各历史节。

Gowin 综合、PnR 和位流生成通过（构建于 2026-10-11 21:28，12 日完成结果核对）。
50MHz fabric Fmax=56.344MHz，Setup/Hold 违反端点均为 0。
资源为 11144 Logic（49%）、3185 Register（14%）、21/28 DSP、15 个数字 IO、1/1 ADC。
J8/K8 仍为 IOT56[A]/[B] ADC_IN，无上下拉；模拟和音频接线未改。
无编译错误或 EX3791；五条 NL0002 仍是关闭的第八触摸声部及子模块被优化删除的提示。

- 当前位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x0000C6A5`。
- SHA256：`2FBD497A6BE3097522336740551BD4C9E508ACB5349D0764DBA326F18A87B0C6`。
- 构建日志：`sim/build/touch_response_build_20261011.log`。
- 响应日志/外部 PCM：`sim/build/tb_top_touch_response.log`、`sim/build/decoded_pcm_touch_response_rtl.csv`。
- 修改前实际位流备份：`sim/build/fsr_0CF5_D1EC50A2_before_touch_response.fs`，
  SHA256=`D1EC50A274EE7D25FC60A668309435DA3BC37778753C014E137462AE38172CB6`。

本次未下载 SRAM 或 Flash；由用户下载当前 C6A5 位流后试听。

## 2026-10-11 历史：K8 切换压力控制音量或音高

K8（`touch_out[7]`）成为模式键，音符门控第 7 位固定为 0；K1～K7 保留 C4～B4。
上电默认音量模式，轻压约 100%、重压约 25%；音高模式原频率→0.5 倍，重压低一个八度。
长按只切换一次，校准期间按住 K8 时须先松开再按；利用同步原始电平和防抖后电平避免启动误切换。

`fsr_dynamics` 持续保留压力目标，新增表达使能，让未选中的控制平滑回到满比例。
音高比例单独使用 32768～65535、每音频帧 64-LSB 平滑；七路相位步进两级流水乘法，
满比例保留原始步进，重压半频率。DDS 相位和 ADSR 门控不因模式切换重置。
歌曲音量/音高不经过这两个压力控制，触摸七声部和歌曲四声部合奏共 11 声部。

已通过 `tb_fsr_dynamics`、`tb_fsr_modes` 和生产参数 `tb_fsr_pipeline`：
两种模式各全部 1024 个压力码、独立整数参考误差≤1 LSB、全部 32768 个可用音高比例的七音步进、
精确原音/低八度端点、长按/短脉冲/启动已按住、无新 ADC 时模式切换、平滑及 CE/复位，
生产 ADC 模型三次转换、185 个静音立体声帧。

`tb_top_fsr_modes` 完整通过 21240 个立体声帧，使用真实 50MHz/I²S/ADC 模型时序和缩短的触摸确认、ADSR。
同一 C4 持续按住时，外部 I²S 的音量模式轻压/重压幅度为 1228.10 / 307.21；
音高模式在 C3（130.813Hz）、中间频率（196.219Hz）、C4（261.626Hz）的幅度为
1225.69 / 1228.48 / 1228.13，确认频率变化而维持音量；切回音量模式的重压 C4 幅度为 307.20。
校准期间按住/短脉冲/长按 K8、K8 不发声、DDS 相位连续、七键与歌曲共 11 声部不削顶、
歌曲 C5 音高独立、独立松键、停止后严格静音均通过。
七音所有频率比例由单元测试检查，外部 I²S 频谱检查针对 C4 的三种压力音高及歌曲 C5；未重复完整七音频谱或全曲长场景。

Gowin 综合、PnR、位流生成完成，50MHz fabric Fmax=57.038MHz，Setup/Hold 违反端点均为 0。
资源为 11145 Logic（49%）、3156 Register（14%）、21/28 DSP、15 个数字 IO、1/1 ADC。
ADC 引脚仍为 J8/K8 的 IOT56[A]/[B]，`ADC_IN`、无上下拉；外部接线不变。
没有 EX3791 或编译错误。五条 NL0002 是固定关闭的第八触摸声部及其子模块被删除的优化提示。

- 本节历史位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x00000CF5`，已被响应修订版覆盖。
- SHA256：`43A6ECEB6E61DB5F22376ED391A6329A22F458C99FA442AB3156C44D34385E72`。
- 构建日志：`sim/build/fsr_key8_modes_build.log`。
- 修改前位流备份：`sim/build/fsr_2FCD_35518E94_before_key8_modes.fs`。

模拟采样仍使用 ADC 接口行为模型，实际 AO 电压和 FSR402 标定需上板测量；本次不写 SRAM 或 Flash。

## 2026-10-11 历史：消除 ADSR 的 EX3791 位宽警告

`adsr_env.v` 的增益加减先保存在两个 17bit 中间信号，再显式取 `[15:0]` 写回 16bit `gain`。
保留原来的低 16bit 赋值行为，没有改变 ADSR 时长、门控优先级或力度映射。

修改前和修改后分别运行 `tb_adsr_env`，均通过 106459 个精确线性样本及边界测试：
中途释放、连续重触发、取消在途除法、低增益释放、CE 停顿、零/一采样时长、极限 Sustain 和复位。
两次 `envelope_samples.csv`（增益和状态）逐字节一致，SHA256 均为
`161FC5B87B12FCB89C91AAF3CC48F500D8511D1ADF9B6E17D5EF255DD9BCE94A`。

`tools/build.tcl` 完成 Gowin 综合、布局布线及位流生成，日志中 WARN/ERROR/EX3791 均为 0。
50MHz 静态时序通过，Fmax=54.037MHz，Setup/Hold 违反端点均为 0。
资源保持 11588 Logic、3155 Register、14 DSP、15 个数字 IO 和 1 个 ADC。

- 本节历史位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode 为 `0x00002FCD`，后续构建已覆盖。
- 本节 SHA256：`6ADE71A4C6F743BB2FC03FDF7174A904213C7CDB3D0C0DE5433046F683E9BCE5`。
- 构建日志：`sim/build/adsr_width_build_20261011.log`。
- 修改前实存位流备份：`sim/build/fsr_2FCD_63E383B2_before_adsr_width_20261011.fs`，
  SHA256=`63E383B2BACB70D16B057F60531D064E909C9342730AB3C3F8FA3AE588AE17F9`。

本次未重复运行下节的完整 FSR 音频场景，也未下载 SRAM 或 Flash。

## 2026-10-10 历史：一路转换模块 AO 改用片内 ADC，不使用 MCP3008

已读用户指定 `.doc` 的四张内嵌说明图：一路模块同时输出 AO/DO，AO 随压力升高，DO 为低有效阈值开关。
RP-C18.3-ST 的 6000g 和曲线系数只作为说明书示例，不用于本工程 FSR402 标定。
先前“必须外接 ADC”不适用于本板：GW5A-25 有片内 ADC，本版已接入该硬核。

主工程移除 SPI ADC 实例、四个 SPI 端口及其 CST/SDC，原驱动/模型/测试保存在 `debug/mcp3008_history`。
新增 `gowin_fsr_adc.v`：2.5MHz 用户采样时钟、glo_left PAD、1024 次采样、64 周期抽取、
1kHz 请求、1.28µs 请求保持、完成信号同步和先低后高确认；2ms 超时保留结果并重试。
14bit 原始码转为 `min(raw/2,1023)`，然后使用既有平滑增益。

保留用户明确要求“按得越重声音越低”，顶层 `FSR_GAIN_REVERSE=1`；
按本说明书 AO 方向设 `FSR_ADC_INVERT=0`，初始校准范围为 32～600。
一枚 FSR402 共同控制八键，歌曲独立；32/600 尚待实物校准，不对应克或牛顿。
`FSR_GAIN_REVERSE=0` 可改为重压大声，但不改变 AO 电压极性。

已通过：

- `tb_gowin_fsr_adc`：2.5MHz 时钟、1kHz 请求、1.28µs 请求宽度、1024 次采样模型、
  五种原始/归一化边界码、单周期 valid；ADC 模型只模拟接口与转换时序。
- `tb_fsr_adc_capture`：拒绝旧 ready 高值、异步 ready/稳定数据总线、完成脉冲、超时保留数据、重试恢复及复位。
- `tb_fsr_dynamics`：两种增益方向、全部 1024 个码、单调/端点、误差不超过一个增益 LSB、平滑和 CE/复位。
- `tb_fsr_pipeline`：生产参数通过三次 ADC 模型转换、重压降低音量、松压恢复满增益、185 个静音立体声帧。
- `tb_top_fsr`：最终重压小声配置通过完整 19970 个立体声帧；同一 C4 持续按住时，轻压、中间、重压、松压恢复的
  I²S 解码幅度分别为 1228.12、767.99、307.20、1228.11。
  压力不触发音符、独立释放、十二路同奏不削顶、歌曲音量独立均通过。
- `tb_top -Quick`（片内 ADC 接入时通过，方向修正后未重复）：3205 个立体声帧通过，S1 响应延迟 1.105484ms；首段旋律、S1 持续按住、
  停止/释放、S2 开始/重启及 I²S 格式通过。

实际 Gowin 综合、PnR、位流生成通过，50MHz fabric Fmax=54.037MHz，Setup/Hold 违反端点均为 0。
SDC 同时识别 400ns / 2.5MHz 的生成 ADC 时钟；硬核内部没有可分析路径，其采样频率限值按原厂资料执行。
资源：11588 Logic（51%）、3155 Register（14%）、14/28 DSP、15 个数字 IO、1/1 ADC。
仅保留原 ADSR 两条 EX3791 位宽提示，无新增 ADC 编译错误。

CST `USE_ADC_SRC bus0 IOT56;` 生效，PnR 报告确认：

| 实际球号 / 物理脚 | ADC 通道 | 配置 |
| --- | --- | --- |
| J8 / J3 第36脚 | IOT56[A]，正端 | ADC_IN，DRIVE=OFF，PULL=NONE |
| K8 / J3 第35脚 | IOT56[B]，负端 | ADC_IN，DRIVE=OFF，PULL=NONE |

AO 经 22kΩ / 4.7kΩ 分压后接正端，负端接地，确保 ADC 输入 ≤1V。
此处不是普通数字 GPIO 读电平，IO 已通过工具配置成真实模拟 ADC 输入。

- 本节历史下载文件：`impl/pnr/PCM5102_PAM8403.fs`，后续构建会覆盖。
- UserCode：**`0x00002FCD`**。
- SHA256：`91027BCB01E5B979EDC8F29D69E0B42C68FC124DB13C772E3BB5741D023BE35C`。
- 外接 ADC 版备份：`sim/build/fsr_C09D_before_onchip.fs`。

模拟模型不验证 ADC 电压精度、噪声、物理引脚或传感器实际特性。
原语库 ADC 为空，本次不沿用旧 SPI ADC 的网表采样验证结论。
本次未写 FPGA SRAM 或 Flash，仍需安全接线后上板采样并按 FSR402 实物标定。

## 2026-10-10 历史：外接 ADC / C09D 重压降低音量

本节保留 C09D 历史记录；当前主工程已切换片内 ADC，以下 SPI 接线和网表结果不适用于当前版本。



按用户要求新增独立的 `FSR_GAIN_REVERSE` 参数，默认 1：
无压力/轻压约为原音量的 100%，压力增大时线性降低，最大力度为 25%，松压平滑恢复。
复位、未获得 ADC 数据时的默认增益也改为满增益。
`FSR_ADC_INVERT=1` 继续正确表示模块 AO 随压力下降，不用改传感器电压方向或校准阈值。
`FSR_GAIN_REVERSE=0` 可切回此前重压更响的映射；ADC、引脚、八键、歌曲、平滑范围均沿用。

- `tb_fsr_dynamics` 遍历全部 1024 个采样值，验证当前音量单调递减和原方向可选，
  与独立整数除法参考误差不超过一个增益 LSB；端点、64-LSB 升降、CE 停顿和复位通过。
- `tb_fsr_pipeline` 的生产默认参数 RTL 场景通过三次外部 SPI 转换、
  重压降低增益、松压恢复满增益及 166 个静音立体声帧。
  同一场景在本版 C09D 的 PnR 原语网表也通过；未进行 SDF 延迟回标或触摸发声网表长场景。
- `tb_top_fsr` 的 C4 I²S 检查通过：同一音符持续按住，轻压、中间、重压、松压恢复的
  解码幅度分别为 1228.12、767.99、307.20、1228.11，确认反向音量变化。
  完整场景共 19970 个立体声帧通过，包括压力不触发音符、独立释放、十二路同奏不削顶及歌曲独立。
  本次未重跑未修改的 ADC 协议单元、旁路八音、完整曲谱和 S1/S2 长场景；初版结果保留在下节。

`tools/build.tcl` 重新完成综合、布局布线、位流和原语网表生成，50MHz 静态时序通过。
Fmax=54.598MHz，Setup/Hold 违反端点均为 0，最小报告裕量为 1.684ns / 0.275ns。
资源为 11353 Logic（50%）、3131 Register（14%）、14/28 DSP、19 个 IO。
只有原 ADSR 的两条 EX3791 位宽提示，未出现新的 FSR 综合警告。

- 本节 C09D 历史文件名：`impl/pnr/PCM5102_PAM8403.fs`，现已覆盖。
- UserCode：**`0x0000C09D`**。
- SHA256：`026A1C7A5534ED7F1541B497C4451AA6F355F9812F1E562015E992885B0E15CF`。
- 重压更响的 B215 位流保存在 `sim/build/fsr_B215_before_reverse.fs`，不作为当前下载文件。

本次未下载 FPGA 或写 Flash；新版力度音频与硬件范围按本节结果为准。

## 2026-10-10 历史：最初压力越大音量越高的 B215 版本

本节保留初版 B215 的结果。该版为轻压 25%、重压约 100%，与当前默认方向相反，采样硬件也不同。

直接修改原 `PCM5102_PAM8403.gprj`，新增 `mcp3008_adc.v` 和 `fsr_dynamics.v`。
AO 经外接 MCP3008 CH0 采样后由 FPGA 硬件处理，未移植或运行 STM32 固件。
用户提供的 `FSR402.c` 使用 `4095-ADC值`，本次据此默认 `1023-ADC值`，支持参数切换方向。
ADC 为 SPI mode 0、500kHz、24 个时钟；每 1ms 读取一次 10bit 数值。
两级同步后读 MISO，所有内部寄存器使用 50MHz 主时钟。

八路触摸音先混音，再使用 Q0.16 力度增益，最后与原歌曲混音送 I²S。
默认从原触摸音量的 25% 到约 100%，每音频帧最大变化 64 个增益 LSB。
一个传感器共同控制八键，在音符保持期间连续生效，不触发音符，不改变歌曲音量。
`FSR_ENABLE=0` 恢复此前的触摸混音通路。ADC、量程、最低音量和平滑参数见 [FSR402 接入说明](FSR402.md)。
量程 32～900 是起始参数，尚未实物校准；力度码不表示牛顿或千克。

### 新增功能仿真

- `tb_mcp3008_adc`：独立串行模型按线上 start 位定位返回 null 位及 B9～B0，加入 200ns DOUT 延迟；
  验证 CH5 命令、0/1/512/682/1023 五种读数、500kHz 时钟、1kHz 采样、单周期 valid 和事务中复位。
- `tb_fsr_dynamics`：遍历全部 1024 个 ADC 值，用独立整数除法计算参考映射；
  方向、死区、饱和、单调性通过，与参考相差不超过一个增益 LSB。
  另测正向 AO、最低增益为零、增益升降/端点、CE 停顿及复位。
- `tb_top_fsr`：真实 50MHz、500kHz SPI、1kHz ADC 和 I²S 时序，仅缩短触摸校准/防抖及 ADSR。
  经外部 SPI 输入改变压力，保持同一个 C4 音符，解码 19970 个完整立体声帧。
  C4 幅度分别为最低 **307.20**、中间 **767.93**、最大 **1228.13**、松压返回 **307.20**。
  证实连续音量变化、压力本身不发声、触摸独立释放、八键与歌曲十二路同奏不削顶、歌曲独立。
- `tb_fsr_pipeline`：使用全部生产默认参数，经外部 SPI 输入完成三次转换，
  ADC 原始值及增益升降/最低值正确，增益步长不超过 64；解码 166 个静音立体声帧。
  同一场景在本版 **PnR 原语网表** 上也通过，未 force 内部信号，使用保留的 ADC/增益总线观察结果。
  这是启动阶段的压力流水验证，不包含八键等待 600ms 后的网表力度音频，也不包含 SDF 延迟回标。
- 原 `tb_top_touch` 以 `FSR_ENABLE=0` 验证旁路，22168 个完整立体声帧通过；
  八音频率/幅度、独立释放、启动/回弹拒绝、八键与歌曲同奏、停止歌曲后触摸继续及最终静音均通过。
- 原 `tb_top_song` 在力度默认开启、触摸不发声的配置下通过全部 42 个事件，
  解码 12727 个完整立体声帧，12382 个非零左声道样本，曲末严格静音。
- 生产默认参数的 `tb_top -Quick` 通过 3205 个完整立体声帧；S1 起音延迟 1.105484ms，
  首次旋律、长按不重复触发、播放/停止及释放、S2 开始/重播、I²S 格式、SCL 恒高均通过。
- 对 `envelope_gain.v` 的有意截位改为显式切片，保持数学行为并去掉零右移配置的新增位宽警告。
  `tb_envelope_gain` 的 1010 组有符号乘法、负端点、零/半/满增益、随机对、CE/复位均通过。

### 新位流与引脚

`tools/build.tcl` 完成综合、布局布线、位流、原语网表和静态时序报告生成。
50MHz 静态时序通过，Fmax=**56.961MHz**，Setup/Hold 违反端点均为 **0**；
最小报告 Setup 裕量 2.444ns，Hold 裕量 0.275ns。
资源为 11554 Logic（51%）、3131 Register（14%）、14/28 DSP（50%）、19 个 IO。
仅保留原 ADSR 两条 EX3791 位宽提示，FSR 和增益乘法没有新增综合警告。

PnR 引脚报告确认四个新增端口均为 LVCMOS33，3.3V：

| 信号 | FPGA 球号 | J3 物理脚 | 方向 / 电气 |
| --- | --- | ---: | --- |
| ADC CS | E1 | 18 | 输出，DRIVE=8，上拉 |
| ADC CLK | D1 | 19 | 输出，DRIVE=8，下拉 |
| ADC DIN | E3 | 20 | 输出，DRIVE=8，下拉 |
| ADC DOUT | J1 | 22 | 输入，上拉，DRIVE=OFF |

SDC 仅排除 MISO 到第一级同步触发器的路径，第二级及后续逻辑保持 50MHz 时序分析。
本次 STA 没有建立外部 AO、ADC 或排线时序模型，串行边沿预算由协议仿真检查。

- 本节 B215 历史版本下载文件名：`impl/pnr/PCM5102_PAM8403.fs`，已由后续修订版覆盖。
- UserCode：**`0x0000B215`**。
- SHA256：`0316CFB7BAB78D5AD2889B63091B4E6B3DA6E4F3E4F82077329FEA9307900260`。
- 加入 FSR 前现有位流备份到 `sim/build/pre_fsr.fs`，不把它作为本版下载文件。

本次未下载 FPGA、未写 Flash，未测实物 FSR402/ADC 的 AO 电压、噪声、量程或喇叭音量。
用户连接 MCP3008 后自行下载，按接入说明校准；下文旧版本实板记录不代表本版硬件已验证。

## 2026-10-10：用户反馈 9～16 也发声

用户在实板反馈按 9～16 也发声，并补充“9～16 声音一样”。尚未确认这是各键彼此相同，
还是分别与 1～8 对应音相同。随后用户确认没有任何选项焊盘短接，并确认 SCL 没有连接、悬空。
当前生产源码只有八路 OUT 门控，没有串口 16 键解码或给 9～16 分配音符。
核对原厂手册确认 TP8～TP15 与 TPQ0～TPQ7 共脚，16 键模式下不能作为八路直出使用。
选项开路按手册应为默认八键单键，不能断言用户还配置在 16 键模式。

本轮使用 Programmer CLI 的 Read Device Codes（`operation_index 0`）读取实际开发板：
UserCode=`0x0000DCC1`，ID=`0x0001281B`，确认运行的是上次八键集成位流。
本轮未执行 SRAM Program 或写 Flash。

### 已确认的 SCL 接口漏项

原厂手册第 14 页明确要求，不用串口时 SCL 必须接 VDD 或 VSS，不能悬空。
此前 README 的“SCL/SDO 无需连接”不正确；原显示工程即使在八键模式，也由 F6 将 SCL 保持空闲高。
上次音频集成只加入八路 OUT，漏了这个固定电平端口。

现已在生产 `src/top.v` 增加 `touch_scl=1`，CST 约束到 F6、3.3V 输出；八路按键、DDS、歌曲和 I2S 算法没有改动。
README 已纠正为：SCL 可直接接模块 3.3V，或者接本工程 F6 固定高，SDO 不接。
直接接模块 3.3V 可在板上现有 DCC1 位流上先验证；断电重启并等待至少 600ms，校准期间不触摸。
默认 `tb_top` 新增从启动开始检查 SCL 始终为高的断言。

用户随后确认“我把 SCL 接地就可以了”，本次 9～16 误响问题已通过固定 SCL 低电平解决。
接线说明同步以用户实测的 SCL 接 GND、SDO 不接为当前方案；F6 固定高输出保留为可选接法，接地方案不连接 F6。
这是用户实板反馈，未新增 OUT 波形或模拟输出测量；没有因接地接法重新改动 RTL、生成位流或下载开发板。

### SCL 修订版构建与验证

- 仍使用同一个 `PCM5102_PAM8403.gprj`、生产顶层与下载文件名，未新建诊断工程。
- `tools/build.tcl` 成功生成综合、PnR、位流和原语网表；时序 Setup/Hold 违反端点均为 0，Fmax=54.592MHz。
- PnR 报告确认 `touch_scl` 位于 F6，3.3V 输出、DRIVE=8；网表 OBUF 的输入来自常量高。
- 资源仍为 11040 Logic、2997 Register、12 DSP，IO 从 14 增至 15。
- `tb_top -Quick` 通过 3205 个完整立体声帧及新增 SCL 始终为高检查，S1 起音延迟仍为 1.105484ms。
  同时覆盖首次旋律、停止释放与 S2 开始/重播；音频算法未改动，未重复跑未改动的单元或八音长场景。
- 当前下载文件 `impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x00008EDB`，创建时间 2026-10-10 18:59:12。
  SHA256=`F945FE452973FC6C1880367F296B1F66508D6ACAA2F82AB3FD7323E5D8B32B48`。
- 本次没有重新下载开发板，没有重跑 8EDB 的网表动态仿真；下文 DCC1 的八音回归和网表记录是前一版历史结果。

## 2026-10-10：TTP229 八键直连与原音频工程集成

本次直接修改 `PCM5102_PAM8403.gprj` 和 `src/top.v`。主工程、RTL 仿真脚本及音乐试听脚本
直接引用 `../pmod_hub75e/src/ttp229_gpio_input.v`，同步器、600ms 上电等待、20ms 每键独立确认
均来自显示工程同一份源码；没有另存一份可能失步的触摸驱动。

OUT1～OUT8 对应 C4/D4/E4/F4/G4/A4/B4/C5，分别使用八个独立 DDS、ADSR 和包络乘法器。
两组四声部核心生成触摸音，原四声部核心继续演奏《小星星》，三组输出再经过饱和混音和同一个 I2S。
每键按住保持、松开独立释放、重新按下重触发；八键同时按住不抢音。
S1/S2 保持歌曲播放/停止和重播功能，停止歌曲不影响触摸音。

### 引脚和工程同步

- 原音频 K2/K1/L1 的 BCK/LRCK/DIN 接线保留；OUT1 从显示工程的 K1 改到 K4/J3 第 5 脚。
- 其余 OUT2～8 为 L2/J4/G1/G2/L3/L4/J2，分别对应 J3 第 4/6/7/8/9/10/21 脚。
- PnR 报告确认八路均为 3.3V 输入，弱下拉、DRIVE=OFF，无端口或球号冲突；模块固定使用 8 键模式。
- SDC 新增仅到八个 `input_meta` 第一级同步寄存器的异步例外，第二级继续进行正常时序分析。
- 两个完整流程配置保留 CPU/SSPI=GPIO、JTAG=下载接口；旧 DDS/debug/压缩包是历史工程。
- 尝试刷新已打开的音频 Gowin 窗口时，当前截图为 Windows 锁屏。磁盘 `.gprj` 已更新；
  本次没有在锁屏状态下注入窗口操作。解锁后关闭并重新打开同一个 `.gprj` 即可加载共享模块。

### 编译与下载文件

- `tools/build.tcl` 完成综合、布局布线、位流及原语网表生成。
- 50MHz 静态时序通过：Setup/Hold 违反端点均为 0，Fmax=54.592MHz。
- 资源：11040 Logic（8764 LUT、2276 ALU，48%）、2997 Register（13%）、12 DSP（43%），14 个 IO。
- 此八键初版位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x0000DCC1`，创建时间 2026-10-10 17:10:09；现已由上面的 SCL 修订版覆盖。
- SHA256=`C9631F3D216190B2CCDFCBBC97192A139125C110D0DEE1BC24BBA55E7A73B747`。
- 原 ADSR 的两条 EX3791 位宽提示仍保留；没有新增综合错误或引脚约束错误。

### 本次仿真结果

- 默认 RTL 的十二项测试全部通过：共享 `tb_ttp229_gpio_input`、新增 `tb_top_touch`，以及
  曲谱、完整短节拍歌曲顶层、DDS、板载键、ADSR、包络乘法、混音、四声部、默认音频顶层和历史音频单元。
- 共享输入测试覆盖八个位置、两种极性、真实 600ms 启动等待、20ms 独立防抖、回弹、禁用/重启及 20µs 有效脉冲。
- `tb_top_touch` 使用真实 50MHz/BCK/LRCK，仅缩短触摸启动至 3ms、防抖至 2ms、ADSR 至 4/4/32 个样本。
  解码 22168 个完整立体声帧，八音频谱全部存在，幅度为 1227.41～1234.47；独立释放 C4 后其余七音保持。
  逐键按下/释放、重触发、短脉冲拒绝、八音与四路歌曲同奏、停止歌曲后触摸继续、最后严格静音均通过。
  最接近的 E4/F4 采用 8192 样本 Hann 窗分辨；初始 4096 窗的频谱串扰已通过延长测试窗口解决。
- `tb_top_song` 检查全部 42 个事件、12727 个完整立体声帧、12382 个非零左样本和最后静音。
- 生产参数 `tb_top` 解码 23665 个完整立体声帧，四个歌曲音频率、板载键回弹、保持、停止到零、重播和 I2S 协议通过。
  S1 到首个非零解码 PCM 为 1.105484ms，比历史版本增加一帧；这是板载键数字路径，不是触摸或模拟输出延迟。
- 生产参数短场景 RTL 测试通过 3205 个完整立体声帧，覆盖第一次旋律、停止释放与 S2 开始/重播。
- 本次 PnR 原语网表对照**限定于启动和首次 S1 发声**：360 个已完成 PCM 样本及时间戳逐点匹配 RTL，
  截至 7.359171ms。网表较慢，65ms 场景有意提前停止，不能把本次结果称为完整短场景或触摸网表验收。
  此段触摸输入全为 0，尚在默认 600ms 等待期；未验证网表下的触摸发声，未加 SDF。
  记录为 `sim/build/netlist_startup_equivalence.json` 和两份 `decoded_pcm_*_startup.csv`，
  相同 SHA256=`2781ECE427D230AEE2AD7B62E31D5C9071B238CBE9B2FDB8680696BDB8FBF530`。
- 静态检查确认 `.gprj` 的全部文件存在、14 个端口/球号约束唯一、CPU/SSPI/JTAG 配置正确。
  Gowin 时序报告确认主时钟和三个同步器例外均已启用。

日志在 `sim/build/*.log`。共享模块没有自己的 `timescale`，Icarus 的继承提示不影响功能；
Gowin 原语库的隐式 wire 提示来自厂商仿真库，生产综合没有新增错误。

本次没有下载开发板或测量 DAC/功放模拟输出。触摸芯片检测时间、20ms 防抖与模拟通路共同决定总延迟，
不能将本次功能集成当作此前 ≤10ms 指标已通过。新一级混音增加一个采样帧（20.48µs）管线延迟。

下文 `0x0000655D` 和 `0x00002064` 的结果对应历史歌曲/固定和弦版本，不能替代本次位流。

## 2026-10-10：修复当前 Gowin 窗口的 EX3937

用户在 GUI 编译报告找不到 `twinkle_sequencer`。磁盘源码和 `.gprj` 正确，实际查看当前 Gowin 窗口发现：
文件树仍包含旧 `poly_demo_control.v`，缺少 `twinkle_sequencer.v`，顶层编辑器还有磁盘文件已改变的 Reload 提示。
这是窗口保留旧工程文件列表，而编译器读取新顶层导致的加载状态不一致。

已在用户当前音频 Gowin 窗口执行“文件 → 关闭工程”，再打开同一个原工程 `.gprj`。
关闭前后工程文件 SHA256 相同，没有覆盖新文件列表。重新打开后，Design 文件树出现
`src/twinkle_sequencer.v`，模块层次出现 `twinkle_sequencer(u_control)`，EX3937 消失。
随后在该窗口执行 Run All，综合、布局布线及位流生成完成；GUI 控制台显示生成报告完成。

- 当前位流仍为 `impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x0000655D`，创建时间 16:49:56。
- 当前文件 SHA256=`DD79DD7D18186C9822216EC242886AA7EF7354C2BA33082E9B91DFF367A62591`。
- 仅在内存中把创建时间注释替换为此前 16:28:03，SHA256 精确匹配下文已验证《小星星》位流；
  硬件内容完全一致，因此沿用已有音频与 RTL/网表逐样本验证结果。
- 重新生成的静态时序报告：50MHz，Setup/Hold 违反端点均为 0，Fmax=58.498MHz。
- 当前综合日志确认读取了 `twinkle_sequencer.v`，无 EX3937；只保留此前已验证的两条 EX3791 包络位宽提示。

本次没有修改 RTL 或下载开发板。README 第 8 节加入工程列表刷新说明。

## 2026-10-10：原工程同步《小星星》硬件试听

用户明确要求在硬件上播放旋律。本次直接修改一直使用的 `PCM5102_PAM8403.gprj`，
没有新建 Gowin 工程；`src/top.v` 实例化新增生产模块 `twinkle_sequencer.v`。
启用的 12 个 RTL 文件均位于本工程 `src/`，旧 `poly_demo_control.v` 不再参与综合。

- S1 按一下开始／停止；S2 从头重播，长按只触发一次。全曲播放一次后自动停止。
- 42 个旋律音、48 拍、三路伴奏；生产播放时间为 `1953+48×19531+17100=956541` 个采样，约 19.58996s。
- 每拍 19531 个采样，每次音符间隔 4883 个采样；六个句尾占两拍。
  普通音起音为 14648 个采样，两拍音为 34179 个采样。
- 顶层 Release 从 24414 改为 4883，约 100ms。A=98、D=3906、S=39321、每路峰值 1/16 沿用。
- 一路旋律和三路伴奏的 DDS、ADSR、乘法及混音仍全部在 FPGA 中逐样本生成。
  本版本按用户要求自动演奏预设曲谱，属于硬件试听，不是此前赛题要求的现场实时演奏入口。

### 源码与音频验证

- `tb_twinkle_sequencer` 按独立字母曲谱及数学频率核对全部 42 个音、采样计时与六个两拍句尾；
  验证曲尾自动停止、不循环、非首音处停止保持尾音音高、非首音处重播、同时按键优先级和复位。
  测试保留生产音乐采样数，仅加速采样使能，不能当作外部时序验收。
- `tb_top_song` 在真实 50MHz/BCK/LRCK 下用缩短的音乐和 ADSR 参数走完整顶层，
  检查 42 个事件、12727 个完整立体声帧（12728 个左样本）、12382 个非零左样本及最后静音。
- 默认参数 `tb_top` 通过 23664 个完整立体声帧及左样本，检查 S1 抖动、长按不重复、
  松开后继续、停止后 100ms 释放到零、S2 从停止／播放状态开始或重播、I2S 延迟位／补零／下降沿更新／左右一致。
  外部混音的 C4/E4/G4/C5 投影幅度为 1239.61 / 1257.14 / 1251.88 / 1229.59，确认四路同时存在。
  S1 数字输入到首个解码非零 PCM 为 1.085004ms，包含伴奏起音；不包含 DAC/功放或实际机械抖动。
- DDS、按键、ADSR、乘法、混音、四声部独立性及历史音频单元回归均通过。
  ADSR 单元保留 R=24414 的较长参数边界测试；生产顶层和音乐试听采用 R=4883。
- 新 `tb_music_preview` 共用生产 `twinkle_sequencer`，不再独立存储另一份旋律。
  仿真开始时逐项断言音乐／ADSR／音量参数与实际生产 `top` 默认值相同，不一致即失败。
  20 主时钟的加速采样使能生成 957516 个 HDL 样本（含前后试听静音），WAV=19.6099375s。
  输出范围为 [-5788,5827]，无未知值、无限幅，最后 100ms 严格为零。
- 独立音频分析对 42 个音逐一作 Hann 窗频率投影，旋律幅度均在 1228.63～1228.84；
  结果存于 `sim/build/music_preview_analysis.json`。WAV 仅为电脑播放作 48kHz 重采样及整段固定增益归一化。

### 编译与当前下载文件

- 原工程 `tools/build.tcl` 综合、布局布线、位流及原语网表生成成功。
- 50MHz 静态时序通过：Setup/Hold 违反端点均为 0，Fmax=58.498MHz。
- 资源：3902 Logic（3136 LUT、766 ALU）、1036 Register、4 DSP。
- 引脚保持 E2/H11/H10/K2/K1/L1，对应 clk/S1/S2/BCK/LRCK/DIN；CPU/SSPI 作为普通 IO，JTAG 保留。
- **位流：`impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x0000655D`**，
  创建时间 2026-10-10 16:28:03。
  SHA256=`82ADFCD55D20344797B7EA3ED820A8C5A9DA7A2A5B020129743FE7DEE65D4171`。
- 原包络中的两条 EX3791 位宽提示仍在；独立数值检查和顶层混音检查通过。

### 网表功能对照与现场范围

短场景 RTL 与本次布局布线后的原语网表均通过，保留生产 50MHz、音乐及 ADSR 参数，
包含第一次旋律起音、S1 停止释放和 S2 开始／重播。两者均解码 3204 个完整立体声帧及左样本，
全部 PCM 数值和时间戳逐点相同；S1 起音延迟同为 1.085004ms。
两份 CSV 的 SHA256 均为 `6BC3F5E89772CE63D021D85F5C6C663E74E65FE7619043CD129990A06B20804F`。
场景约 65.615ms；它不是生产节拍下整曲 19.6s 的完整网表仿真。
日志位于 `sim/build/tb_top_quick.log`、`tb_top_netlist_quick.log`，数据为 `decoded_pcm_rtl_quick.csv`、
`decoded_pcm_netlist_quick.csv`；`tools/check_pcm_equivalence.py` 对照通过。
仿真不加 SDF，实际路径时序由上述静态时序检查覆盖。

本次生成可下载位流，由用户自行下载并试听，没有执行硬件下载或模拟录音。
实际 DAC/功放音量和整机模拟延迟仍需上板确认；操作见 README 与 MUSIC_PREVIEW。
下文按历史时间保留此前记录，其中的“当前”指相应记录当时的版本。

## 2026-10-10：确认旋律试听与板端控制没有同步

用户指出《小星星》试听与板上声音不同。源码核对确认：生产 `top.v` 实例化 `poly_demo_control`，
只有 S1/S2 四音和弦控制；14 个旋律音符和三个伴奏声部仅在 `sim/tb_music_preview.v` 中。
该测试平台不在 `.gprj` 中，旋律控制未加入生产位流。两者共用合成核心，不代表整个演奏程序相同。
板端 Release=24414（约 500ms），旋律试听 Release=4883（约 100ms）。

当前磁盘位流创建时间为 15:42:37，UserCode=`0x00002064`，
SHA256=`721E5F3D9CBE574B94615C40E7CA3E03E226DAF19128C7070CC22E5B97533298`。
只在内存中将创建时间注释替换为第三步原文件的 12:09:40，SHA256 精确匹配下文第三步验证记录，
确认硬件内容仍是已验证的四音和弦版本。没有改写位流或下载开发板。

已在 README 和 MUSIC_PREVIEW 开头明确标出旋律尚未进入板端，并列出控制器、音符、释放时间及综合范围差异。
与生产顶层对应的试听为 `polyphony_reference.wav`（1.472s），《小星星》试听为 `music_preview.wav`（6.000s）。
本次修正说明，没有修改 RTL 或把仿真曲谱加入生产播放通路。

## 2026-10-10：音乐能力参考试听

用户确认当前有声音，但不像音乐或变化不明显。当前生产顶层只有固定和弦和单路变化，没有连续旋律。
在本原工程的 `sim/` 与 `tools/` 内新增电脑参考试听，未另建 Gowin 工程。

- 当前和弦参考：从既有外部 I2S 解码 `decoded_pcm_rtl.csv` 导出 1.472s 的 `polyphony_reference.wav`。
- 旋律参考：`tb_music_preview.v` 使用同一生产四声部核心，模拟《小星星》开头 14 个旋律音符与三声部伴奏。
  生成 292975 个 HDL 样本，四声部求和无未知值、没有溢出或限幅，释放后严格归零。
- 旋律渲染采样使能加速为 20 主时钟，Release=4883（约 100ms）；它不是实际 I2S 或延迟验收。
- WAV 导出为 48kHz / 单声道 / 16 位，音乐参考时长约 6.000s。整段固定增益归一化只用于电脑试听。
- 对导出音乐独立检查 C5、G5、A5 的 FFT 主峰，分别为 521.484 / 785.156 / 878.906Hz，
  均在 FFT 的 5.859375Hz 分辨率内匹配目标频率；最后 100ms 为严格数字零。
- 这些 WAV 来自 HDL 仿真，不是开发板模拟录音；音符表仅位于仿真演奏输入中，未加入生产工程文件列表。
  接入实际演奏键盘后，现场音符事件可驱动同一个合成核心演奏旋律。

核对时磁盘位流已被重新编译，UserCode 仍为 `0x00002064`，创建时间为 12:55:11。
当前文件 SHA256=`CB3AE21913159C8D7B3A1D1143E2CF79B8EBB77E00921240F7532410E1ADE014`。
仅在内存中将创建时间注释恢复为之前的 12:09:40，SHA256 精确匹配第三步原验证文件；
证明硬件内容完全一致。未改写该位流。试听说明见 `MUSIC_PREVIEW.md`。

## 2026-10-10：工程与下载入口核对

用户指出可能曾将新功能只放到独立测试工程、原工程未同步。核对现有源码及历史记录后确认：

- 第一步初版确实先在 `../pcm5102_dds_step1/` 实现，原工程当时仍是固定单音版。
  该历史验证记录还记载 Programmer 指向旧主工程位流：新变调版下载后，板上 UserCode 又从
  `0x00005C06` 变回 `0x00007A8C`，随后才修正下载路径。
- 2026-10-09 第一阶段已合回本原工程；第二步 ADSR 和本次第三步四声部均直接修改本目录。
- 当前 `PCM5102_PAM8403.gprj` 明确列出本目录 `src/` 内的 12 个生产 RTL 文件，
  含 `synth_voice.v`、`poly_synth.v`、`audio_mixer.v`、`poly_demo_control.v`；顶层实际实例化 `poly_synth`。
- 构建脚本打开本工程并输出本工程的 `impl/pnr/PCM5102_PAM8403.fs`。
  当前位流头部 UserCode=`0x00002064`，SHA256 与第三步验证记录相同。
- 只读检查两个压缩包中的顶层：`../pcm5102_pam8403.zip` 没有 S2、ADSR 或四声部；
  `../pcm5102_pam8403 (2).zip` 有 S2 与单声部 ADSR，但没有四声部。二者均为历史快照。
- 已更新仓库首页、独立第一步和两个诊断工程说明，区分当前入口与历史下载记录。

本次核对只调整说明，没有更改已验证 RTL、工程文件列表或位流，也没有读取或下载开发板。
磁盘文件一致不代表当前 IDE/Programmer 窗口已经重新加载；重新打开本工程并选择本工程位流，
可避免继续使用旧工程文件列表或旧下载路径。

## 2026-10-10：第三步，四声部与混音

沿用原工程、原顶层接口和约束，新增 `synth_voice.v`、`poly_synth.v`、`audio_mixer.v`、
`poly_demo_control.v`，共 12 个生产 RTL 文件。旧 `pitch_control.v` 留作历史源码，不参与当前综合。
四路分别使用独立 DDS/ADSR/包络乘法，默认每路峰值 1/16、Sustain≈60%、Release≈500ms。
混音在 24 位有符号域进行，采用固定缩放和 16 位饱和，增加一帧 20.48µs 流水延迟。

板载 S1 控制演奏；S2 按四个状态循环：完整 A4/C5/E5/A5 和弦、仅释放第 2 路、
恢复第 2 路 C5、仅第 2 路改为 D5。全部状态变化源自实时按键事件，没有自动播放曲谱。
核心具有四组独立 `gates` / `phase_increments`，四路演奏键和自动声部分配器尚未接入。

### RTL 自检

- 混音：1011 组数据通过，覆盖四路正/负满幅、超过输出范围时饱和、正负抵消、固定 1/4 缩放、
  1000 组随机向量、采样停顿和复位。
- 四声部核心：4825 帧数学正弦/整数乘法/混音参考通过，12315 次未改变声部轨迹对照通过。
  覆盖四路同时 Sustain、单路变调、独立释放和恢复、尾音中连续重触发、每个门控位分别释放、
  全部静音和复位。该核心测试使用 64 主时钟的加速采样使能和缩短包络，仍保留硬件斜率准备时间。
- 现有 DDS、按键过滤、ADSR、包络乘法及历史音频诊断回归全部通过。
  ADSR 的 106459 个采样与独立线性参考逐点一致，包含生产参数的 24414 个采样释放。
- 完整顶层使用真实 50MHz、1024 主时钟每采样和生产包络参数，通过 71873 个完整左右声道对，
  导出 71874 个左声道 PCM 样本；测试结束时最后一个左声道还没有配对的右声道。
  共六个 Hann 窗频率投影窗口，确认四个音同时存在、第 2 路单独消失/恢复、C5→D5→C5，
  其余三路的音高与自身幅度保持。还验证按键抖动、长按不重复、500ms 整体释放到严格数字零、
  BCK/LRCK 周期、I2S 延迟位/补零、下降沿更新以及左右一致。
- 单独释放后，A4/E5/A5 的投影幅度为 1228.81 / 1228.69 / 1228.83；
  C5 为 9.79，低于缺席阈值 35。有限窗口有频谱泄漏，核心测试另外检查该路实际样本归零。
  D5 变调窗口的幅度为 1229.00，其余三路为 1228.41 / 1229.34 / 1228.61。
- S1 数字输入到首个完整解码非零 PCM 为 **1.085004ms**；这是当前起音测试的结果，
  不是所有输入相位的最坏值，也不包含机械抖动或 DAC/功放模拟延迟。

### 综合与布局布线

- 原工程 CLI `tools/build.tcl` 综合、布局布线、位流及原语网表生成成功。
- 50MHz 静态时序通过：Setup/Hold 违反端点均为 0；Fmax=57.503MHz。
- 资源：3712 Logic（2928 LUT、784 ALU），1004 Register，4 DSP（MULTALU27X18）。
- 引脚报告确认 E2/H11/H10/K2/K1/L1 均按约束放置；实际 `device.cfg` 中
  CPU/SSPI GPIO=true、JTAG GPIO=false。
- 位流 `impl/pnr/PCM5102_PAM8403.fs`，UserCode=`0x00002064`；
  SHA256=`4749C6DDBBD497408A805C51209C80E9C13B01D3EB2B93C4A39C72BA6E49EEC4`。
- 原有两条 EX3791 包络中间位宽提示仍在；上述独立包络参考检查端点及范围，未发现数值回绕。

### 布局布线后的功能仿真

原语模型运行较慢，因此默认 `-Netlist` 使用约 31.8ms 的短场景，保留真实主时钟、采样率和
500ms 释放参数，不 force 内部状态。覆盖四个试听状态、单路释放中重触发、连续变调、整体释放早期、
按键确认和 I2S 格式；500ms 完整释放及最终静音由上面的完整 RTL 和 ADSR 测试验证。
完整长场景网表仿真没有运行至完成，不能把它当作通过记录。需要时用 `-Netlist -FullNetlist` 运行。

短场景 RTL 和配套布局布线网表均通过 1553 个完整声道对；两份 CSV 中全部 1554 个左声道样本
及时间戳逐点相同。两份文件 SHA256 均为
`A03E82DC491E335D9D4F49A28569B4BC0C1CFA0B83E305D7EAB6FC23E2046EE2`。
网表也得到相同的 1.085004ms 首个非零 PCM 延迟，以及 5638 的整体释放早期峰值。
所有原语网表仿真均未标注 SDF，属于功能检查；实际路径时序由静态时序报告检查。

### 数据与现场验收

- 完整 RTL：`sim/build/tb_top.log`、`decoded_pcm_rtl.csv`。
- 短场景：`tb_top_quick.log`、`tb_top_netlist_quick.log`，以及相应 `decoded_pcm_*_quick.csv`。
- `tools/check_pcm_equivalence.py` 对同一短场景的每个 PCM 样本与时间戳进行 RTL/网表比较。
- 已生成并检查 `sim/build/polyphony_rtl.png`、`polyphony_rtl.svg`；数据来自外部 I2S 解码，
  图中可见 C5 单独释放、恢复及变为 D5，其余三个频率继续存在。图片不是上板模拟测量。
- 本轮生成供用户下载的位流，没有执行硬件下载。第三步仍需现场试听及 DAC 模拟输出测量；
  整机总延迟 ≤10ms 尚未实测验收。操作说明见 `STEP3.md`。

## 2026-10-09：加长释放尾音，便于试听

根据用户“试试”的要求，直接把原工程 `src/top.v` 中 `ADSR_RELEASE_SAMPLES`
由 4883 改成 24414，即 100.00384ms → 499.99872ms；包络模块默认值同步更新。
Attack=98、Decay=3906、Sustain=39321，峰值音量和 S2 变调继续沿用。
建议按住 S1 一秒，再松开听约半秒的渐弱尾音。

- 包络自检：106,459 个采样与独立线性参考逐点一致，验证 24414 个采样释放、
  起音中松开、低音量释放和尾音中重按，最终归零。
- 完整 RTL I2S 仿真通过：59,436 个左右声道对；六个音高窗口、起音、维持、
  500ms 释放、短音、重新起音及最终静音。释放早期/后期窗口峰值为 1226/339，
  重新起音峰值为 2044；数字输入到首个非零解码 PCM 为 1.064524ms。
- 在当前原 Gowin 工程窗口显示了 `24414` 参数，并直接点击 Run All，综合、布局布线成功。
  同一原工程构建脚本随后生成当前 500ms 版的配套原语网表，避免保留旧 100ms 网表。
- 50MHz 静态时序通过，Setup/Hold 违反端点均为 0；Fmax=59.104MHz。
- 资源：1018 Logic（802 LUT、216 ALU），315 Register，1 DSP，0 BSRAM。
- 位流仍为原路径 `impl/pnr/PCM5102_PAM8403.fs`；UserCode=`0x0000CD0D`。
  本次构建 SHA256=`0C43AD577F99E34707C2EBD2D1BF30F0894585A9A0F3576BD52155F4F946ADEE`。
- Programmer 的 FS File 已自动刷新为 `0x0000CD0D`；下方已有 `0x00009016` Finished 日志
  属于用户下载的上一版。此次由用户重新下载试听，没有自动执行硬件下载或修改 Flash。

本次参数调整完成 RTL 与静态时序验证，没有重复运行完整布局布线原语网表功能仿真。
下节 `0x00009016` 的 100ms 版网表记录属于历史版本。
本次重新生成的包络/PCM 仿真图均使用 500ms 尾音数据，仍不代表 DAC 模拟输出实测。

## 2026-10-09：第二步，原工程单声部 ADSR

直接修改 `src/top.v`，新增 `src/adsr_env.v`、`src/envelope_gain.v`，
并加入同一个 `PCM5102_PAM8403.gprj`。当前主工程共九个 RTL 文件。
下载文件仍为 `impl/pnr/PCM5102_PAM8403.fs`，S1、S2、时钟与 I2S 引脚保持原定义。

按下 S1 进入 Attack，98 个采样从当前音量上升至峰值；Decay 用 3906 个采样降至
39321/65535≈60%；按住维持；松开用 4883 个采样从当前音量降至零。
快速重新按下从当前音量重新起音，不清零包络或相位。提前松开也保留完整释放时长。
总音量保持峰值 1/16，S2 四档实时变调保持原行为。

### RTL 和编译结果

- ADSR 单元测试：28,335 个采样与独立线性公式逐点一致，默认 A/D/R 为 98/3906/4883。
  覆盖维持、起音/衰减中松开、释放中重按、硬件除法中改变门控、低音量释放、采样停顿、
  0/1 采样时长、0/满幅维持值及阶段中复位。
- 有符号包络乘法：1010 组数据通过，包含 1000 组随机数据、负满幅、无符号满幅包络、
  零/半/满幅、采样停顿和复位；未出现符号反转。
- 完整顶层 RTL：20,374 个左右声道对，验证起音峰值、60% 维持、释放前后幅度、
  短音、释放中重按、最终数字零、六个音高窗口、S2 抖动/长按、I2S 格式和时钟。
- 首个非零 PCM：本次仿真从 S1 数字输入到完整外部 I2S 解码样本为 **1.064524ms**。
  这不包含真实按键抖动、DAC 与功放模拟延迟。
- 原 DDS、按键确认及历史音频诊断单元回归均通过。
- 本次布局布线原语网表也通过同一完整顶层测试：20,374 个左右声道对、六个音高窗口、
  释放到零、短音及释放中重按；未标注 SDF，属于功能仿真。
  释放早期/后期窗口峰值分别为 1211/346，重新起音窗口峰值为 2038。
- RTL 与网表导出的全部 20,374 个 PCM 样本及时间戳逐点相同，两份 CSV 的 SHA256 均为
  `FDBD4F7A17CB08F84B24A6BB929D86C707A5D51575B93BAD5E910BD81830924D`。
- 原工程综合和布局布线成功；重载同一个原工程后，在当前 Gowin 图形界面点击 **Run All** 也成功。
- 50MHz 时序：Setup/Hold 违反端点均为 0，Fmax=63.293MHz。
- 资源：994 Logic（785 LUT、209 ALU），316 Register，1 DSP（MULTALU27X18），0 BSRAM。
  正弦表本次被映射为 LUT。
- 图形界面生成的位流 UserCode=`0x00009016`，
  SHA256=`666972DE1F8745BB55213FC53751BB8003881622EF579BC6A86511C960B3AA3E`。
- E2/H11/H10/K2/K1/L1 均按约束放置，实际 `device.cfg` 为 CPU/SSPI GPIO=true、JTAG GPIO=false。

命令行与图形界面生成的位流只有创建时间注释不同，硬件内容完全一致；
将图形界面文件的创建时间注释恢复为命令行的 `19:42:07` 后，SHA256 精确匹配
`443590EF46EC55AD86336C134AA8EC789BB44FAC182E8D5AC6F276FA34E04285`。

综合的两条 EX3791 提示对应 17 位中间加减结果写回 16 位包络；
段终点保证范围 0～65535，逐点参考测试也确认未出现数值回绕。
乘法结果注册后进入 I2S，比第一步增加一个 20.48µs 采样周期。
硬件除法仅在阶段开始时工作 16 个主时钟，之后每采样使用整数步进与余数累加。

### 用户编译下载与验收

Gowin 当前窗口已重新载入新增模块并打开最新 `src/top.v`，顶部可见 ADSR 参数。
Programmer 的 FS File 仍指向本工程路径，自动检测更新为 `0x00009016`。
当前 Programmer 下方历史 `0x00005C06` 下载日志属于之前版本，不能当作新 ADSR 已下载。
本轮没有执行硬件下载或烧写 Flash；由用户自行在原工程 Run All、SRAM Program，现场试听。

生成了 `sim/build/adsr_envelope.png`、`adsr_envelope.svg`、`adsr_pcm.png`。
包络图来自单元测试采样域数据，按 48,828.125Hz 换算横轴；维持段为测试指定的 200 个采样。
音频图来自顶层外部 I2S 解码 RTL 数据。两者均不是上板模拟测量。
运行 `tools/plot_adsr.py` 可重新生成，需 Python 与 matplotlib。

本步骤完成单声部包络，尚未实现四声部，尚未实测整机总延迟。
日志位于 `sim/build/tb_adsr_env.log`、`tb_envelope_gain.log`、`tb_top.log`、`tb_top_netlist.log`。
`tools/run_sim.ps1` 将 RTL 与网表解码数据分别保存为
`sim/build/decoded_pcm_rtl.csv`、`sim/build/decoded_pcm_netlist.csv`，避免互相覆盖。

## 2026-10-09：在原工程源码中合并实时变调

根据用户要求，后续统一使用原目录、原工程名和原下载文件名：
`PCM5102_PAM8403.gprj` → `impl/pnr/PCM5102_PAM8403.fs`。

直接修改 `src/top.v`，加入 S2 输入、两个按键的 1ms 确认、运行时音高控制和 DDS；
新增 `button_filter.v`、`pitch_control.v`、`dds_voice.v`、`sine_rom.v` 并加入工程文件列表。
固定音高的 `nco_sine.v`、`volume_key.v` 留作历史诊断用途，不参与当前主工程综合。
S2 约束为 H10、LVCMOS33、内部下拉，S1 与三个音频输出引脚保持原定义。
更新 SDC 的两路第一级同步器例外，完整 JSON 保存 CPU/SSPI GPIO 配置。

行为：按住 S1 发声，松开静音；S2 每次按下只切换一次，依次为
440、523.2511306、659.2551138、880Hz，再循环回 440Hz。默认数字音量 1/16。
变调保持相位连续，静音期间可以选择音高。当前仍是单声部，ADSR 在下一步加入。

### 源码与构建验证

- RTL 自检：1024 个正弦地址、8203 次 DDS 更新/保持、按键抖动/长按/释放检查通过。
- 顶层仿真：3985 个完整左右声道对、六个音高窗口、静音和音高循环通过。
- 原诊断模块单元回归通过，包括原正弦表、音量符号和 I2S 帧边界。
- 重新编译本工程，综合、布局布线和位流生成成功。
- 本工程生成的原语网表功能仿真也通过相同顶层检查，未标注 SDF。
- 50MHz 静态时序检查：Setup / Hold 违反端点均为 0，报告 Fmax=113.206MHz。
- 资源：219 Logic（131 LUT、88 ALU）、143 Register、1 BSRAM。
- 本次位流 UserCode=`0x00005C06`，SHA256=`E1A026872EFEECDD2064ED58A90C17BC8734066EA8F24983B4B07178B2FD336F`。

仿真中单次 S1 输入到首个完整解码非零 PCM 样本为 1.023564ms；
这个结果不包含真实按键抖动和 DAC、功放的模拟延迟。

### 用户可见的编译下载路径

在当前 Gowin 窗口关闭并重新载入同一个原工程，确认源码列表包含七个当前 RTL 文件；
打开了已修改的 `src/top.v`，可以看到 `key_s2` 输入。
从原工程打开 Programmer，确认 FS File 指向本工程的 `PCM5102_PAM8403.fs`，操作为 SRAM Program。
关闭了此前指向独立 `DDS_STEP1.fs` 的重复 Programmer 窗口。

本轮由用户自行编译、下载，没有再次执行硬件下载或修改 Flash。
此前的独立第一步工程保留为验证快照，后续开发使用本主工程。
历史 GAO 与自动播放诊断使用各自保存的旧顶层或约束，保持原来的诊断行为。

日志：`sim/build/tb_dds_voice.log`、`tb_button_filter.log`、`tb_top.log`、
`tb_audio_units.log`、`tb_top_netlist.log`；报告位于 `impl/pnr/`。

## 2026-10-08 无声问题排查

再次执行 RTL 顶层和模块自检，通过。另使用 `tools/build_audit.tcl` 生成
Gowin 布局布线后的 `impl/pnr/PCM5102_AUDIT.vo`，并使用
`tools/run_netlist_sim.ps1` 与原厂 `IDE/simlib/gw5a/prim_sim.v` 运行功能仿真。
独立 I2S 引脚解码仍通过：146 个立体声对、131 个静音声道字、162 个非零声道字。
这次网表仿真**未标注 SDF 延迟**，不是时序仿真。
网表也确认自动复位计数器 INIT=0、正弦 ROM 初始化内容存在。

为区分仿真结果和板上实际行为，新增 `debug/audio_gao/AUDIO_GAO.gprj`，
引用主工程原来的五个 RTL 源文件及约束，加入四路 GAO 探针。
该调试工程关闭输出寄存器放入 IOB，以便 GAO 捕获输出节点。
构建通过，并已通过官方 Programmer CLI 将 `debug/audio_gao/impl/pnr/ao_0.fs`
下载到实际 FPGA SRAM：USB Location 385、扫描器件 GW5A、下载返回成功。
本次没有烧写 Flash，也没有改写原来的 `PCM5102_PAM8403.fs`。

GAO 以板载 50MHz 时钟采集，导出时设置 20ns。
16,384 个有效采样点解码结果如下：

| 信号 | 本次板上结果 |
| --- | --- |
| H11 / S1 | 捕获窗口内始终为低；实际按下后的高电平尚待验证 |
| K2 / BCK | 1,023 个完整周期均为 320ns，即 3.125MHz |
| K1 / LRCK | 30 个完整周期均为 20,480ns，即 48.828125kHz |
| L1 / DIN | H11 为低时整段为零；31 个完整声道字均解码为 PCM=0 |
| I2S | 每声道 32 个 BCK；延迟位、16bit 数据和补零通过；15 对左右声道一致 |

原始数据位于 `debug/audio_gao/captures/key_low.csv`，解码结果位于
`debug/audio_gao/captures/key_low_analysis.json`，复现方法见该调试目录 README。
频率按照板载 50MHz 标称值换算，片内捕获未独立测量晶振绝对频率，
也不能代替 DAC 接收端的电压、边沿和负载测量。

### 随后的自动播放诊断：数据链路实测通过

用户离开后，在 `debug/audio_autoplay` 增加独立诊断工程，引用原来的四个音频模块及约束。
诊断顶层将音频使能固定为高、默认音量改为 1/16，并以单独寄存器观测 H11。
65,536 深度 GAO 构建通过并下载到 SRAM，User Code=0x000051B2，
Status Code=0x70026020，下载日志保存在该目录 `programmer_sram.log`。

本次实际捕获 65,536 个有效点、跨度 1.3107ms。BCK 的 4,095 个完整周期全部为 320ns，
LRCK 的 126 个完整周期全部为 20,480ns。DIN 确实存在非零数据，
解出 64 个左声道采样（63 个非零），数值范围 -2048～1375；63 对完整左右声道全部相等。
32 BCK/声道、一位延迟、MSB 优先、补零和下降沿更新均通过。

独立数学模型验证 64 个采样均符合原相位增量和 1/16 缩放，并能对应同一个连续相位序列。
没有读取 RTL 波表或硬件内部相位寄存器作为期望值。
原始 CSV、解码 JSON 及实际波形图保存在 `debug/audio_autoplay/captures`，
复现和试听说明见 `debug/audio_autoplay/README.md`。
本次说明中的约 440Hz 根据通过逐点验证的相位模型及 50MHz 标称时钟计算。

采集后已恢复原按键行为的 GAO 位流 `debug/audio_gao/impl/pnr/ao_0.fs`，
恢复下载 User Code=0x00002E44、Status Code=0x70026020、Finished，
日志为 `debug/audio_gao/restore_key_sram.log`。当前板上没有自动持续播放。

**目前结论：静音路径与绕过按键后的正弦生成/I2S 发送均实测通过；
原版实际按键使能及 DAC 到喇叭的出声情况仍未闭环。**
主工程音频 RTL 没有因未经证实的推测而修改。

## Verilog-2001 编译与自检：通过

2026-10-06 执行 `tools/run_sim.ps1`；两组测试均使用 Icarus 的 `-g2001 -Wall` 编译，
编译和仿真退出码均为 0。
本次仅修复工程配置，RTL 保持该次通过仿真的版本。

```text
PASS [top 3ms]: BCK=3.125MHz LRCK=48.828125kHz ratio=64, I2S one-bit delay/MSB/padding, 146 stereo pairs, 131 muted words, 162 nonzero words
PASS [units]: all 256 sine values and phase wrap, two-stage key sync, signed half/quarter gain, 7 adversarial stereo TX frames
PASS: PCM5102 + PAM8403 audio simulations completed.
```

顶层仿真覆盖两次按下和松开，包括非时钟对齐的按键变化。解码只使用外部
BCK/LRCK/DIN，与独立的数学正弦及按键同步模型比较，检查以下行为：

- BCK 周期 320ns、半周期 160ns，LRCK 完整周期 20,480ns，BCK/LRCK=64。
- 每声道 32 个 BCK，首位为延迟位，随后 16bit MSB 优先，其余补零。
- DIN 与 LRCK 只在 BCK 下降沿变化，在上升沿采样得到正确 PCM。
- 同一帧左右相等，按键松开后下一帧提交零数据，按住时有正负非零采样。
- 默认右移一位后的 PCM 在 -16384～16383 范围。

模块级测试检查 256 点完整正弦表、相位累加回绕、两级输入同步、
有符号 1/2 与 1/4 缩放，发送 `8000、7FFF、A501、5A80、0001、FFFF、0000`
七种帧，并刻意改变帧中途和右声道边界的输入，验证帧锁存与使能停顿。

## Gowin 综合、布局布线与位流：通过

工具：Gowin **V1.9.11.03 Education**。
器件：**GW5A-LV25MG121NC1/I0**，顶层 `top`。
2026-10-07 在用户已经打开的 Gowin 图形界面中修改 CPU 复用配置，点击 Apply / OK，
随后通过该窗口的 **Run All** 重新编译。综合、布局布线、时序分析和位流生成完成，
实际 PnR 日志没有 ERROR，生成了新的位流。此次验证不依赖命令行脚本覆盖参数。

### CPU/SSPI 持久配置修复

图形界面报 `PR2028` / `PR2017` 的原因是此前 CPU/SSPI 复用仅在 `build.tcl`
中设置，缺少图形界面使用的持久配置。报错时实际生成的 `device.cfg` 显示
`CPU regular_io = false`，E2 因此仍被保留为 CPU 专用脚。

现已补充并保留以下两个工程配置文件：

- `impl/PCM5102_PAM8403_process_config.json`
- `impl/project_process_config.json`

第一次仅补充磁盘配置并通过命令行构建，不能证明当前图形界面的设置已经同步。
00:12:13 再次失败的日志及配置显示，图形界面已重新写入 `CPU=false`。
随后直接检查实际 Configuration → Place & Route → Dual-Purpose Pin 窗口，
确认 **Use CPU as regular IO** 未勾选，而 SSPI 已勾选。

已直接在该窗口勾选 CPU 复用并保存，以图形界面生成的完整配置同步上述两个文件。
两者均保存 `CPU=true`、`SSPI=true`、`JTAG=false`，顶层自动识别为 `top`。
图形界面 Run All 完成后，实际 `impl/pnr/device.cfg` 确认
`CPU regular_io = true`、`SSPI regular_io = true`、`JTAG regular_io = false`，
E2 正确放置为 `clk`，原来的五个引脚约束均正确落实。
`.gitignore` 只忽略构建产物，明确保留这两个配置文件。

| 检查项 | 结果 |
| --- | --- |
| 主时钟约束 | 50MHz / 20ns |
| 内部时钟域 | 一个，板载 `clk` |
| 分析路径 / 端点 | 232 / 322 |
| Setup 违规端点 | 0 |
| Hold 违规端点 | 0 |
| 最小 Setup 裕量 | 11.281ns |
| 最小 Hold 裕量 | 0.278ns |
| Logic | 163 / 23040 |
| Register | 102 / 23280 |
| BSRAM | 1 / 56 |
| I/O | 2 个输入、3 个输出 |

引脚报告确认 E2=clk、H11=key_s1、K2=BCK、K1=LRCK、L1=DIN；
全部为 LVCMOS33，音频输出 BANK2=3.3V、DRIVE=8，S1 下拉。
源码保持参考提示词的五条引脚分配、整数分频、相位增量和默认 1/2 音量。

结果文件：

- `impl/pnr/PCM5102_PAM8403.fs`：可供 Gowin Programmer 使用的位流。
- `impl/pnr/PCM5102_PAM8403.pin.html`：引脚报告。
- `impl/pnr/PCM5102_PAM8403.tr.html`：时序报告入口，需保留配套 HTML 文件。
- `impl/pnr/PCM5102_PAM8403.rpt.txt`：布局布线和资源报告。
- `sim/build/tb_top.vcd`：3ms 顶层波形。

2026-10-08 检查时现有正式位流 SHA256（文件修改时间为 2026-10-07 00:26:58）：

```text
F63419DF95403C01A730EE28B9198B38A18EAC7CE4C65C5E6B222791FFF1825C
```

## 验证范围

2026-10-07 的构建没有下载 FPGA。2026-10-08 已下载 GAO 调试版，
并完成 H11 为低时的片内采集以及自动播放诊断版的 PCM/I2S 实测；
尚未测试原版实际按键使能、DAC 模拟输出、功放或喇叭声音。
RTL 仿真与内部 50MHz 时序通过，不代表模拟音量、失真或模块接线已经实测。
SDC 未建立 FPGA 到 DAC 之间线缆、负载及接收端的外部时序模型。

README 已依据原厂资料澄清两处参考提示词的硬件表述：芯片 SCK 需要保持低电平，
模块外部 SCK 排针是否可不接取决于板上电路；数字音量 0.5 不能保证 PAM8403 不削波。
首次播放先降低功放电位器，无电位器时按 README 调小数字音量并重新构建。
