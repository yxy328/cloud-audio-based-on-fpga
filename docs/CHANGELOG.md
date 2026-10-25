# 版本记录

[首页](../README.md) · [文档索引](README.md) · [完整验证记录](../pcm5102_pam8403/VERIFICATION.md)

按当前工程文档和App版本整理。以下日期为上海时间；位流标识指已记录构建，重新构建以实际产物为准。下文历史安装包链接对应的旧 APK 已从 `dist/` 下架，可在 Gitee 提交记录中取得。`dist/FPGA-Music-Unified.apk` 是滚动的当前安装入口（内容为 v1.24-hue / Code25 的 2026-10-25 重新构建，含板键联动），带版本号的 `dist/FPGA-Music-Hue33-Code25.apk` 是 2026-10-23 的首个 Code25 构建、不含板键联动，两者 `versionName` 相同但 SHA256 不同；上一版连接诊断另存 `dist/FPGA-Music-LinkDiag-Code24.apk`，更早为 `dist/FPGA-Music-Chromatic.apk` 与 `dist/FPGA-Music-Pedal.apk`。

## 2026-10-25 · 当前默认位流：APDS 运算复用与效果器前置核验，未烧录

`apds9960_ctrl` 的局部累加 / 均值运算复用与两套音源的共享算术（`synth_shared_arith`）合入生产树，相对当日冻结基线净回收 **211 Logic / 134 CLS**。完整 PnR（Gowin V1.9.11.03 Education，place2 / route0 / maxfan23）：Logic **21649**、CLS **11183**、Register 10579、BSRAM 47、DSP 26.5，未布通 0、setup / hold 违例端点 0/0，WNS +0.030 / +0.170 ns。位流 SHA256 `840AE4C47D7BB57048481ACA3ECB6BEEC59E430E66AF0BD32429FDE99E84AD15`，本轮未记录 UserCode；101 项源码 / ROM / 约束 / 工程输入逐项匹配已验证快照。

同轮只做核验、不改生产 RTL：`tb_fx_frame_budget` 在真实 50MHz / 1024 拍帧内实测含接收沿触摸 1012、弯音 43、效果器 5 拍可并行，超限 / overrun / 合成混音 clipped 均为 0；隔离的混响 / 延迟 / 合唱原型保持 2048 / 4096 / 4096 独立存储与 4 comb + 2 allpass，259200 帧与独立模型逐样本相同。**三效果器的正式 RTL、兼容协议 / `TAKE`、三张参数卡片与新版 App 尚未交付**，原型边界不代表联合验收。

升级注意：本份位流同时含压力 / 滑杆双通道、`KLIVE` 板键联动与 33 档色环显示，无需按功能换烧。APDS 均值复用最坏 256→1024 拍，15ms 释放保护仍满足但边界参数可跨到相邻轮询，不能称完整事件逐拍等价；生产 100000 拍活动轮询下分类相对最后有效样本延后 173 拍。未烧录、未安装 APK、未做实体光学与模拟音频验收。逐笔资源账见[验证记录](../pcm5102_pam8403/VERIFICATION.md)顶部、[FX 前置核验](../pcm5102_pam8403/FX_PREFLIGHT_20261024.md)与 `pcm5102_pam8403/reports/fx_delivery_20261025/README.md`（该目录只入库报告正文，PnR 快照树留在本机）。

## 2026-10-25 · 压力与滑杆双通道（ADS1115 + 片内 ADC），完整 PnR 通过、未烧录

压力传感器继续用 GW5A 片内 ADC（J8/K8、22kΩ/4.7kΩ、0～1V），滑杆改接 **ADS1115 AIN1**（3.3V 供电、ADDR 接 GND、地址 0x48），
并使用**独立的 I²C 引脚**：SCL=K10（J3 第31脚）、SDA=L10（J3 第32脚），不再与 APDS-9960 的 H4/G4 共用，因此没有总线仲裁。
新增 `ads1115_ctrl`（自带 `i2c_master`：AIN1 单端、±4.096V、连续 128SPS、10ms 轮询、100ms 超时回退），
`i2c_master` 支持 16 位寄存器两字节写；`top`/`top_unified` 增加 `slider_scl/slider_sda`。
`i2c_arbiter.v` 保留但**不参与构建**（共享总线方案的历史件）。
压力表达不再由 `analog_mode` 门控；`ANALOG,0` 表示滑杆关闭，1～4 仍为音量/音高/颤音/湿度，`CAL` 标定滑杆，
`ANALOG,0` 时手机 ADC 读数显示压力通道。滑杆通道按 `raw[14:5]` 映射到 10 位（3.3V 满行程约 825）。

验证：`tb_ads1115_bus`（配置 0xD283、16→10 位映射、双客户端轮换、超时保持与恢复）、`tb_analog_expression`（压力音高为基准、
滑杆音量/音高/湿度、弯音下颤音、故障与陈旧回退）、`tb_top_dual_analog`（压力增益/压音与滑杆音量同时生效、滑杆故障不影响压力）、
`tb_i2c_master_bus`、`tb_top_idle`、`tb_apds_nack`、`tb_hc05_extensions`、`tb_command_protocol` 通过；26 个顶层测试重新编译通过（以[验证记录](../pcm5102_pam8403/VERIFICATION.md)本轮记录为准）。

完整 PnR（Gowin V1.9.11.03 Education，`build_unified.tcl`，route 0 / fanout 23）：独立总线下 **place_option 2** 布通——
Logic **21860/23040（95%）**、CLS **11317/11520（99%）**、Register 10571、BSRAM 47、DSP 26.5、ADC 1/1、
未布通 **0**、setup/hold 违例端点 **0/0**、Fmax **50.119MHz**，已生成 `.fs`。place 1 虽布通但有 4 个 setup 违例（Fmax 49.813MHz），
place 0 有 200 条以上未布通；换策略必须重测。综合新增一条 `EX3045`（`ads1115_ctrl.v` 的浮空总线保护在综合时恒真），属有意的仿真保护。
**未烧录、未上板测量**。接线与标定见[迁移说明](../pcm5102_pam8403/REFERENCE_MIGRATION.md)。

## 2026-10-23 · App v1.24-hue / Code25，手机 33 档色环频谱

“显示”分区顶部新增手机实时预览卡片，原生绘制 33 档青→蓝→紫→品红→红色环、深色频谱与渐变三源幅度条，色值与 RTL 逐档一致；继续使用原 `VIZ?` 的 0～31 频谱与 0～56 音源幅度并各自归一化，不冒充面板 PCM 峰值或 PK，停止 / 断线 / 过期仍清空数据。蓝牙协议、轮询节奏与 FPGA 均未改动。

全套 `test-core.ps1` 通过（含 SppLink 255 项、新增 `LedHue` 431 项与 64 个色码逐项对比）；36 张桌面排版图覆盖六种宽度 × 六种状态，无文字或绘图越界。Java / D8、APK 对齐、v3 验签与 Manifest 核对通过：`versionCode 25` / `versionName 1.24-hue`，独立包 SHA256 `70059516F69EB2DBF792F22A973A13CF6257EA006D5AE8C9BFF961528D833B2F`。说明见 [HUE33.md](../pcm5102_pam8403/android_app/HUE33.md)，原始日志与源码差异见 [APP_HUE33_20261023](../pcm5102_pam8403/deliveries/APP_HUE33_20261023/README.md)。

升级注意：本独立包**不含板键联动**；`KLIVE_ON` / `KLIVE_OFF` 在 2026-10-25 的滚动入口构建中加入，两者 `versionName` 都是 1.24-hue，需要联动功能请安装 `dist/FPGA-Music-Unified.apk`。排版图为桌面预览不是手机截图，本次未安装实体手机，实机显示与 HC-05 联动仍待验。

## 2026-10-23 · FPGA LED 波形 33 档整帧音量色环，UserCode `0x00002176`

波形颜色改用独立的 PCM/64 色相轴：每 64 个计数一级，0～2048 共 33 个色相点、每档 5.625°，180° 青经蓝、紫、品红到 360° 红，2048 及以上钳为 `(31,3,3)`；一帧内波形与总电平条共用一种颜色，非零但不足 64 计数（含 ±1）仍显示 `(3,31,31)`，只有原轴为零才显示灰色 `(8,8,8)`。量程保护、PK 百分比与电平条长度继续使用 `ceil(abs(PCM)/256)` 原轴，`scope_style.hex` 内容不变，实现只用限幅、移位、加减与取位，**不新增 ROM 表项、BSRAM、DSP 或硬件乘除单元**。

冻结构建 `scope_hue33_20261023_p3r0`（place3 / route0 / maxfan23）：Logic **21503**、CLS **11202**、Register 10326、BSRAM 47、DSP 26.5，相对 8 档基线 `scope_hue8_baseline_20261023`（21590 / 11080 / 10321 / 47 / 26.5）为 **−87 Logic / +122 CLS / +5 Register / 0 / 0**；WNS +0.198 ns、Fmax 50.499MHz、setup / hold 违例端点均 0，位流 SHA256 `A5567DB120334D16B9B72071E0F0D2754B64E1AFE44878D22ED1243700A52B35`。五个 testbench 按顺序单个 `-Tests` 运行至完整顶层 196.117712ms，颜色全 64 码、65536 个有符号 PCM 幅度、33 档渐强回落与跨窗口清零、±1 边界及独立 HSV 模型误差 ≤1LSB 通过。交付包 [LED_HUE33_20261023](../pcm5102_pam8403/deliveries/LED_HUE33_20261023/README.md)。

升级注意：本版满足器件容量与 50MHz 时序，但**后续功能预留未通过**——剩余 1537 Logic / 318 CLS / 9 BSRAM，距 1650 / 365 / 4 的规划分别差 113 Logic / 47 CLS，实施下一功能前需先回收。初次 place2 / route0 时序未过、place2 / route2 留 141 条未布通网络，均未交付。该份已被 2026-10-25 构建取代为默认输出，未烧录，实物面板颜色仍待核对。

## 2026-10-22 · FPGA LED 波形弱信号修正版，UserCode `0x00007D67`

实体照片反馈“X4、PK 约 2%、波形仍挤在零线且接近白色”，据此修正显示链路：基础倍率提高八倍，FSR 建议 X8 /X16 /X32（纵轴 ±4K /±2K /±1K，K=1024 个原始 PCM 计数），超范围时自动退到 X4 /X2 /X1；采集极值保留有符号 10 位、量化步长由 256 降为 64；静音才用低亮白，非零峰值改用饱和蓝 → 紫 → 红渐变，红端按音源 /16 衰减后的正常演奏电平标定（约自峰值 1793 起），PK 数值与电平条保持固定满幅刻度。音频样本、音量、FSR 方向、命令字典与协议均未改动。规则、迟滞与标定见 [SCOPE_DISPLAY.md](../pcm5102_pam8403/SCOPE_DISPLAY.md)。

冻结构建 `scope_weak_signal_v11_20261022`，95 份输入与工作区一致。整机 Logic 21394、CLS 11087、Register 10306、BSRAM 47、DSP 26.5（相对上一版 +7 /−58 /0 /+2 /0）；50MHz 约束下 Fmax 51.441MHz，Setup /Hold 违规端点均 0。剩余 1646 Logic /433 CLS /9 BSRAM，其中 Logic 比后续规划要求的 1650 少 4 个，严格后续预留审计未通过，实施下一功能前需回收这 4 个 Logic。为守住预算只在 `hc05_keymap.v`、`take_nor_store.v` 加 `syn_encoding="onehot"` 属性。15 项相关 RTL 测试与外部 RGB5 独立模型通过，真实顶层 Quick 87.164ms；未烧录开发板、未安装 APK、未做实体面板颜色与摄像验收。位流 SHA256 `C54EF13D2975A7C1BF646A314F207C9D68202129A8D206CC362255D9EFD08B6A`，交付包 [LED_SCOPE_WEAK_FIX_20261022](../pcm5102_pam8403/deliveries/LED_SCOPE_WEAK_FIX_20261022/README.md)；标准 `impl/pnr/PCM5102_UNIFIED.fs` 已同步该份，旧默认产物移至 `sim/build/pre_weak_fix_default_20261022/`。

## 2026-10-22 · FPGA LED 波形刻度、FSR 量程与真实电平渐变，UserCode `0x00006DCF`

波形页改为带时间轴（0 /5 /10 MS）与纵轴数字刻度的布局：48 个采集箱完整覆盖 512 个采样、约 10.486ms；FSR 实际音量增益联动 X1 /X2 /X4 建议量程并带迟滞，混音超出建议范围时优先扩大量程；颜色按真实窗口峰值分 16 级从白蓝渐变到红，PK 与电平条仍为 0～100% 固定满幅刻度。XY /FFT 页的三条音源幅度条与 `VIZ?` 包格式保留，未新增 App 命令、DSP 或音频处理级。显示倍率最高 X4，不是 AGC，极弱信号仍可能很小。

冻结构建 `scope_fsr_gradient_v5_20261022`，95 份输入与工作区逐项匹配。整机 Logic 21387、CLS 11145、Register 10306、BSRAM 45、DSP 26.5（相对四档回声基线 +299 /+85 /+67 /+1 /0，为整套显示的净增量）；剩余 1653 /375 /11，仍覆盖 D、B2、E100 与安全垫的 1650 /365 /4 预留。50MHz 约束下 Fmax 50.438MHz，Setup /Hold 违规端点均 0。11 个相关 RTL 测试通过，含 65536 个 PCM 峰值码、768 组坐标、独立光栅模型的 4096 像素 /12288 个 RGB5 通道；最终顶层 Quick 87.164ms（省略六预设整屏抓图）。位流 SHA256 `2A1BCDE333A880DD7ED8743B2ADDEAEC314638D38511AB568A83558713EB09A0`，交付包 [LED_SCOPE_20261022](../pcm5102_pam8403/deliveries/LED_SCOPE_20261022/README.md)，同日已被上一节的弱信号修正版取代，保留为历史记录。

## 2026-10-22 · App v1.23-linkdiag / Code24，安装版本与超时定位

用户在Code23发布后仍反馈通用超时截图，实际安装版本与失败命令尚未确认。发现旧四档回声冻结包仍带有缺陷的Code22 APK，与dist同名；已给旧包添加停用提示，新增带版本号的 [Code24独立APK](../pcm5102_pam8403/android_app/dist/FPGA-Music-LinkDiag-Code24.apk)。设备状态显示Manifest内的实际版本，4秒超时提示具体命令、期望回复、字节数、最近完整行或缺少LF。

回复识别改为等待命令单处匹配，保留异步事件 /录制溢出与设备拒绝的原有语义；命令正文最多64个可打印ASCII字符且只追加LF。传输测试改用真实VIB回包 `VIB,0008,0D96,100,0000`，补齐完整初始化十步、事件 /其他回复交错、逐字节分片、参数解析和三类超时。核心测试全部通过，SppLink255项；APK构建、v3验签和版本核对通过。SHA256为 `8E2C3AF491B68E6D1755BCFFBF31D470DFD4243F777ABE48D866208608B9A7DD`。本次未改RTL、位流、命令字典或回复模板，实机连接是否恢复仍待新提示 /连接结果核对。说明见 [HC05_CONNECTION.md](../pcm5102_pam8403/HC05_CONNECTION.md)。

## 2026-10-22 · App v1.22-handshake / Code23，修复 v1.21 连接握手必然超时

v1.21 在 `MainActivity.connectSelected()` 的连接流程里追加 `readPerformance()`，发送 `PITCH,?` / `VIB,?` / `EFFECT2,?`，但同一次提交没有改动 `SppLink.java`：读线程的回复白名单与 `commandLocked()` 的期望类型分支都只列到 `TAKE,`，三条新回复被当作非回复行丢弃。后果是命令发出、板子正确回答，App 却干等到 4 秒 deadline 抛「等待回复超时；请重新连接并重新下载，原有效曲谱保留」并 `close()` 关闭会话——**与位流新旧无关，Code22 在任何板子上都完不成连接**。第三方 SPP 终端可同时拿到 `PING`→`PONG` 与 `PITCH,?`→`PITCH,2000,8000,1000,4000`，即链路与协议正常、缺陷在 App 侧。

修复为两处白名单各补 `PITCH,` / `VIB,` / `EFFECT2,`，并在 `core_test/SppLinkTest.java` 增加传输层回归：三条查询的完整回复、与 `EVT` 事件行交错的回复、以及分两片到达的 `PITCH` 回复都必须被等待中的命令取回，防止以后新增命令时再次只改调用方。App 纯 Java 核心测试全部通过，`SppLink` 195 项。

Code23 /1.22-handshake APK SHA256 `21DBFEFE48609B97B48B8DE2108D9F664DD2522509F48811598304DD96C53691`，仍配套四档回声优先版位流（UserCode `0x0000589C`）。同时记录：仓库默认路径 `impl/pnr/PCM5102_UNIFIED.fs` 已被 10-22 12:39 的本地重建覆盖为 `0F42C78FC7A1F40AC3F50C5F8078157246CE8D8A13387AEAE9040066A3047390`，与交付包 `E236EB634F02FB24B93E004C9AA5B68229D1E693EE5D678AAD173DE232F97EDE` 不是同一字节（同源码、同 UserCode、资源与时序逐项一致，仅布局布线结果不同）；严格复现交付记录请取 `deliveries/ECHO_PRIORITY_20261022/` 副本。本轮未改动 RTL、位流与协议，实物演奏验收仍待办。

## 2026-10-22 · App v1.21-echo / Code22，四档回声优先版

按用户确认的取舍，优先保留四档回声 `EFFECT2,tap`（约 84 / 168 / 336 / 504 ms，tap0 每帧读写保持原采样率，长三档每 2 / 4 / 6 帧只捕获湿声并加一阶低通，最长档湿声采样上限约 4.07 kHz，存在残余混叠；干声与原 84 ms 档保持原样，切档清旧尾音）。新增三条 HC-05 命令：59 `PITCH,lower,upper,slew,base`（弯音上下界 Q2.14、滑音斜率 Q8.8、共享基准）、60 `VIB,hi,lo,depth,delay`（32 位颤音增量分高低 16 位、深度 0～1023、起振等待 0～39063 帧）、62 `EFFECT2,tap`；回复模板仅在末尾追加 kind 27 / 28 / 29，原 1～58 号命令与 AREC 七项原位保留，字典共 61 项，61 / 63 号空闲。App 提供草稿 / 确认三态、按 BPM 20～300 就近选档与恢复默认；换算全部在纯 Java `PerformanceParams` 中完成，RTL 不新增除法器或 DSP。

覆盖范围收敛：共享移调 / A4（−12～+12 半音、415 / 432 / 440 / 442 / 466 Hz）只作用红外与手势共享音源，16 触摸键保持 B1 音高映射、Karplus–Strong 吉他保持固定音高；弯音范围只作用 BEND1～7；颤音为红外 / 手势共享并需配合 `VIBRATO` 开关，起振等待是整体使能而非逐音符。合唱速率维持原固定值约 0.745058 Hz，C6 震音与 C8 律制原型超预算撤回，`EFFECT2` 的 chorusInc 字段与 TEMP 查询未交付。

升级注意事项：`PITCH` / `VIB` 的空字段与省略尾字段保持原值，查询回报是定长大写十六进制、不能原样当十进制回填；修改弯音范围需松键、等释音完成并停止曲谱与下载，否则 `ERR,BUSY`；非 16384 基准与 `ANALOG2` 双向互斥，冲突回 `ERR,STATE`；528 位 TAKE 事件格式未扩展，新增参数不写入快照，录制与回放前需保持同一套设置；录制硬条件分别检查（TAKE 为 `HOLD∈{0,1}` 且 `POLY=16`，事件日志为 8 键、`HOLD=0`、`ANALOG=0`），各有一键配置。

`performance_echo_release_20261022` 冻结复现构建，94 份输入与当前源码逐项 SHA256 一致：Logic 21088/23040、CLS 11060/11520、BSRAM 44/56、DSP 26.5/28、Register 10239；相对 B1 的 C 成本为 +121 Logic / +7 CLS / +200 Register，无 BSRAM 或 DSP 增量，低于 400 / 100 预算；50 MHz 约束下 Fmax 50.096 MHz，Setup / Hold 违例端点均 0，无未布通报错。位流 UserCode `0x0000589C`，位流 SHA256 `E236EB634F02FB24B93E004C9AA5B68229D1E693EE5D678AAD173DE232F97EDE`，APK SHA256 `BEF1A3F01945BF32D283B1EF4988A58D2D27793B797A19D4B6AFA46EB5E4226A`。

通过项：六个新增参数相关仿真、默认逐时钟对照、弯音 RAM 180000 时钟比较、四档脉冲与相位回绕、81 次实际 UART 回复、真实 50 MHz 顶层 UART → 参数 → DDS / I2S / 面板联调、RAM 几何检查，以及含 `PerformanceParams` 8690 项检查的 App 纯 Java 核心测试。未通过或未做完项：107 项 RTL 全量回归在交付时点仍在独立目录运行（快照 10 通过 / 10 运行中），不计为全部通过；按用户确认本轮未烧录开发板、未安装手机、未做耳机口对录，实物验收全部待办。范围、公式与逐项预算见[演奏参数与四档回声](../pcm5102_pam8403/PERFORMANCE_PARAMS.md)，交付文件见 [ECHO_PRIORITY_20261022](../pcm5102_pam8403/deliveries/ECHO_PRIORITY_20261022/README.md)，阶段 E 的 100 CLS 缩减口径见 [E_SCOPE.md](../pcm5102_pam8403/E_SCOPE.md)。

## 2026-10-21 · App v1.19-performance / Code20，阶段 C 全覆盖候选（已被取代）

C 阶段的首个通过布局布线的候选包：弯音范围、滑音、红外 / 手势共享颤音与全局起振等待，并把移调 / A4 同时覆盖 16 触摸键与红外 / 手势。`performance_tuning_20261021` 冻结输入与当时活动源码 94 项逐项 SHA256 匹配，Logic 21141 / CLS 11018 / BSRAM 44 / DSP 26.5 / Register 10275，Fmax 50.550 MHz；该包未记录 UserCode、未烧录、未做实物对录。因四档回声与合唱加入后超出 C 预算，本包的触摸调音、C8 律制与 C6 震音均未进入 v1.21-echo，四档回声优先版另用 `EFFECT2,tap` 编号 62。源码、报告与指纹见 [PERFORMANCE_PARAMS_C7_20261021](../pcm5102_pam8403/deliveries/PERFORMANCE_PARAMS_C7_20261021/README.md)，失败与撤回的原型留在各冻结目录，不以「生成了 fs」代替预算或时序验收。

## 2026-10-21 · App v1.16-chromatic / Code17，B1 十二键半音阶

按用户确认的 TTP229 扫描接线，K1～K12 默认音高改为 C4～B4 半音阶，K13～K16 四个独立条暂作 C5/D5/E5/F5。只改前七键默认映射与高键常量，命令号、MAP 键号、七通道曲谱与屏幕指引、RAM 几何均不变。手机琴键换成 7 白 + 5 黑的钢琴布局加独立高音条，七键映射可图形点选并保留高级文本；旧手机录音按录制时音高回放，新录音保存音高快照。MAP、独立弯音和曲谱仍只覆盖前七个扫描键；匹配曲库会改变音高，恢复默认半音阶前执行 `MAP_RESET`。

`chromatic_b1_20261021` 冻结快照完成布局布线：Logic 20967（较踏板版 +28）、CLS 11053（−2）、Register 10039、BSRAM 44、DSP 26.5，符合 B1 的 Logic ≤ +60 预算；50 MHz 约束下 Fmax 52.026 MHz，主时钟与 ADC 时钟的 Setup/Hold 违例端点均为 0。位流 UserCode `0x000015CD`，位流 SHA256 `E40B7502ADC87A6A9F1B0435002E0419D07FD6D618E7ABB58789B40F10E74DFC`，APK SHA256 `1675EF87CCC5FEFB9C1DD0658B2B745758438B72C611628ABA8F8FA92635A888`。通过项与实机测频待办见[半音阶与高音条说明](../pcm5102_pam8403/CHROMATIC_KEYS.md)和[验证记录](../pcm5102_pam8403/VERIFICATION.md)顶部。本轮未烧录开发板、未安装手机、未做耳机口对录。

## 2026-10-21 · App v1.15-sidebar / Code16，阶段 A 侧边栏

界面重组为六分区侧边栏，触摸、红外、手势各固定七个分组；参数区分草稿与设备确认三态，板上事件录制给出前置条件说明和「一键切到可录配置」；撤下已停用的 HC-05 PCM 录音与回传入口。不改 RTL、命令字典、回复模板、曲谱格式和弯音数值语义，其中的后续阶段资源数字只是文档预算复核，未重新综合。分区与状态定义见[侧边栏阶段 A 说明](../pcm5102_pam8403/android_app/SIDEBAR.md)，连续实施前需先解决的两项见[方案审查](../pcm5102_pam8403/SIDEBAR_REVIEW.md)。手机与板上联动待实机验收；该版本的安装包与 v1.16 共用 `dist/FPGA-Music-Unified.apk` 文件名，v1.15 原始字节保留在 Gitee 提交记录中。

## 2026-10-21 · App v1.14-pedal / Code15，钢琴踏板与复音上限

新增 `HOLD,2` 钢琴制音踏板：踩住时松键进入约 1200 ms 的四段有限尾音（58594 采样，段长按余数分配，终点严格为 0），抬起只对已松手音施加约 10 ms 制音，按住键不受影响；再踩不重新起音也不复活已制音尾音，相位连续，PANIC、接口模式切换与 perf_kill 清除尾音。`POLY,1/2/4/8/16`（默认 16）是物理键优先的软上限，每帧至多安排一个最旧的已松手音进入短释音。`POLY` 命令 ID 为 57，新增 `CTRL2?`（ID 58）回报真实模式、上限与实际声部数；原 `CTRL?` 仍是七字段并把非零踏板映射为锁存 1，兼容旧 App。踏板触发源仅来自 App/HC-05，没有新增引脚。

升级注意事项：`HOLD,0/1` 与默认 `POLY,16` 保持原行为和幅度。事件录制与新状态互斥，`HOLD,2` 或上限非 16 时拒绝开始录制、录制期间拒绝写入，回放仍按原 528 位事件格式以踏板关闭、上限 16 运行；手机本地录制不受影响，半踏板（模拟 mode5）暂未实现。同时按用户授权以 `ENABLE_FLASH_AUDIO=0` 关闭板上 Flash 原音 PCM 录制以释放演奏资源，旧 PCM 源码、独立目标与[2026-10-20 交付包](../pcm5102_pam8403/deliveries/UNIFIED_RECORDING_20261020/)保留——该交付包含 PCM 但不含踏板，不能与本轮互换。APK 的能力探测会明确提示当前 PCM 录制关闭。

2026-10-21 16:47（上海时间）完成踏板版布局布线：Logic 20939/23040（91%）、CLS 11055/11520、BSRAM 44/56、DSP 26.5/28，较含 PCM 的基线净减 Logic 1271、BSRAM 2；50 MHz 约束下 Fmax 51.236 MHz，最小 Setup 裕量 0.483 ns、Hold 裕量 0.150 ns，clk 与 fsr_adc_clk 的违例端点均为 0。位流 UserCode `0x0000782D`，位流与 APK 的 SHA256、`tb_top_pedal`、`tb_touch_pedal_timing` 等仿真与复现命令见[验证记录](../pcm5102_pam8403/VERIFICATION.md)顶部。本轮未烧录开发板、未安装手机 App、未做模拟声音实测。

## 2026-10-20 · App v1.13 / Code14，单固件统一版

三个工程入口合并为 `pcm5102_pam8403/PCM5102_UNIFIED.gprj`，顶层 `top_unified`，内部实例化原 `src/top.v`。同一份 `PCM5102_UNIFIED.fs` 同时提供正常演奏、曲谱、LED 遥控、板上事件录制重放与 HC-05 原音质 PCM 回传，不再按功能分别烧录。合并前的工程模板、专用构建与打包脚本原样保留在[历史归档](../pcm5102_pam8403/archive/legacy_projects/README.md)，`tools/build.tcl` 默认只构建统一版。

App 在同一界面提供三种录制：手机琴键本地录制（停止即回放、命名保存、导出 MIDI，不依赖蓝牙）、板上事件录制与重放、板上最长 30 秒原音质录音经 9600bps 回传 WAV（约需 54 分钟）。收到 `ERR,STATE` / `ERR,CMD` / `ERR,BUSY` 时显示拒绝原因并保留连接；新 APK 仍可连接旧固件，缺失功能会提示。操作见[统一录制说明](../pcm5102_pam8403/android_app/UNIFIED_RECORDING.md)。

成功构建 `shared_p2r0` 实测 Logic 22210/23040、CLS 11381/11520、BSRAM 46/56、DSP 26.5/28；50 MHz（20 ns）约束下 Fmax 50.717 MHz，最差 Setup 裕量 0.283 ns，Setup/Hold 违例端点均为 0。逐时钟等价、吞吐与复查脚本见 [RAM 几何优化与统一版验证](../pcm5102_pam8403/RAM_GEOMETRY_VERIFICATION.md)。本轮未记录位流 UserCode；开发板烧录、手机蓝牙与板上 Flash 仍待真机验收。位流、APK、报告与 SHA256 见[统一版交付包](../pcm5102_pam8403/deliveries/UNIFIED_RECORDING_20261020/)。

## 2026-10-20 · App v1.12 / Code13 路线2独立音频版

独立工程 `PCM5102_AUDIO_TAKE.gprj` 经现有 9600bps HC-05 回传板上录制的原音质 PCM，手机校验后保存与播放 WAV；[路线2说明](../pcm5102_pam8403/HC05_AUDIO_ROUTE2.md) 记录带宽与限制，30 秒录音回传约需 54 分钟以上。APK 为 `dist/FPGA-HC05-Audio-Route2.apk`，实板蓝牙与播放待验收。该工程入口与打包脚本现已归档，功能并入 v1.13 统一版，无需再单独烧录音频固件。

## 2026-10-19 · App v1.11 / Code12，仅HC-05通信

按当前硬件选择关闭App启动时的USB接收器初始化；USB录音入口继续不显示，相关驱动、接收代码及FPGA预留接口保留备用。手机与FPGA仅通过HC-05通信，无需USB模块、RTS或OTG；不把完整PCM/WAV改走现有9600bps。保留当前曲库、LED联动及演奏控制，板上事件录制回放仍需相应专用固件。

新增[独立安装包](../pcm5102_pam8403/android_app/dist/FPGA-Score-hc05-only.apk)，旧包保留。该调整不修改FPGA RTL或位流；构建、测试与边界见[验证记录](../pcm5102_pam8403/VERIFICATION.md)。

## 2026-10-19 · App v1.10 / Code11 手机 LED 联动

新增四页远程切换、请求/实际显示状态读回、16 段频谱与三组音源幅度的手机预览。配套 FPGA 增加 VIS/VIZ 查询，复用现有显示缓存和回复寄存器，32 字节快照不混帧；App 限速查询，后台/断线停止，数据过期清图。切页与 S2 冲突有固定优先级，曲谱和实时声音保持运行。

需要同时更新 [App 与独立主工程位流](../pcm5102_pam8403/LED_REMOTE.md)。RTL、Java 跨端数据及 50MHz 构建结果见[验证记录](../pcm5102_pam8403/VERIFICATION.md)；实体手机与面板待联调。

## 2026-10-19 · App v1.9 / Code10 LED 功能包

新增 [LED 轨迹控制](../pcm5102_pam8403/android_app/LED_CONTROL.md)：八字、多瓣、圆、椭圆、直线、实际混音六预设，以及参考频率比/相位选择。复用已有 XY 协议，无需为本功能重新烧录；仍需板上 S2 进入 XY 页面。收到设备 OK 才显示最近发送确认，断线或重连后清除确认提示。

[独立 APK](../pcm5102_pam8403/android_app/dist/FPGA-Score-led.apk)保留旧安装包，签名与旧版一致。APK 构建验证和八组 JVM 核心测试通过，手机/面板联调待验。没有新增远程切页、实时状态查询或手机频谱预览，详见[验证记录](../pcm5102_pam8403/VERIFICATION.md)。

## 2026-10-18 · App v1.6 / Code7

保留v1.5主题素材和界面，新增完整数字演奏录音：最终I²S同帧采样经独立FIFO、CRC与2Mbps UART上行，HC-05仍负责AREC启停/状态；手机USB Host校验并导出WAV。需要3.3V且支持2Mbps、自动RTS/CTS的模块及OTG，不接受预录PCM下载/播放。原REC事件日志范围不变。

712个整机回传采样与外部I²S解码逐个一致；溢出、断连、丢包或缺结束包不能显示完整。FPGA50MHz时序通过，当前位流UserCode为0x000089A9；硬件接线、手机USB持续吞吐与板上声音待验。[接线步骤](../pcm5102_pam8403/AUDIO_RECORDING.md) · [构建记录](../pcm5102_pam8403/VERIFICATION.md)。

## 2026-10-18 · App v1.4 / Code5

- 触摸升级为16份独立DDS/ADSR上下文，支持8键直连与16键串行切换、串行极性读回、延音锁存和PANIC。
- 增加回声/合唱、平滑总音量，原ADC可选接FSR或滑杆；滑杆支持端点标定及音量、音高、颤音深度、音效湿度四种用途。
- 红外/手势增至八种音色，64×64 LED增加空闲状态总览；播放自动显示七列曲谱，波形/XY/FFT保留。
- 曲谱、自动试听、独立手机滑音仍限前七键；16键/锁存/滑杆模式不支持现有七键事件日志。

升级时同时更新App和FPGA；16键模式需拆除OUT直连和SCL固定连接，再按 [迁移说明](../pcm5102_pam8403/REFERENCE_MIGRATION.md) 接线、设置模块与极性。默认仍为8键，上电不会自动进入16键。

最近记录位流UserCode为 `0x00002850`。构建时50MHz时序通过、余量较小，完整资源、SHA256和数字验证见验证记录顶部；本版尚未完成实板改接、模拟音频及手机UI验收。

## 2026-10-17 · App v1.3 / Code4

新增 `AUDITION` 显式自动演奏已下载的音符曲谱，复用触摸DDS/ADSR合成；普通 `PLAY` 和S1/S2曲谱操作仍是无声指引。处理校验期间实体按键取消自动演奏请求的竞争情况。对应历史位流UserCode为 `0x0000859F`。

## 2026-10-16～17 · App v1.2及配套显示更新

增加触摸与红外/手势独立运行时ADSR、前七个触摸声部独立滑音；配套FPGA支持波形、参考/实际混音XY与FFT页面。历史构建参数和验证范围保存在验证记录各日期章节。

更早的单声部、四声部演示及融合版本可通过 [历史文档索引](README.md) 查阅。旧位流、引脚和自动演示操作按对应版本理解。
