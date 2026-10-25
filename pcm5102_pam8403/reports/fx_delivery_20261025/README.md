# 三效果落地与资源回收：本轮交付记录

**任务尚未全部完成。已接入经验证的 APDS 运算复用；完整三效果及其 App 未接入。资源与既定后续预留尚不能同时满足。**

生产目录重新完整综合/PnR通过：**21649/11183/10579/47/26.5**（Logic/CLS/Register/BSRAM/DSP），0未布通，setup/hold违例0/0，WNS +0.030/+0.170 ns。
相对本轮冻结当前基线，实际净回收 **211 Logic、134 CLS**；BSRAM与DSP不变。只修改生产 `src/apds9960_ctrl.v`。没有将历史95 CLS或其他失败候选相加。

## 完成与未完成阶段

- 已冻结全部当前源码、ROM、约束、工程、工具、仿真与起始未提交修改，保存git二进制diff。未发现AGENTS.md；接手时只有IDE，无运行构建。未用Git HEAD替代工作区。
- 已新建当前完整基线，并完成APDS当前工程A/B、手势语义/完整事件时刻/保护边界、双模拟与I²C回归。APDS迁移前当前源与历史原基线逐字节相同，只迁局部算术。
- 已验证显示上下半屏配对存储的功能、碰撞和外部扫描；单独及叠加APDS均测整机。它不满足本轮CLS回收目标，未接入。
- 已尝试Flash FSM取消显式onehot属性；层级综合XML和最终资源与APDS版本完全相同，无收益，未接入。原子快照、NOR提交/掉电模型回归仍通过。
- 已完成隔离最小三效果原型、同步块RAM修正、独立样本模型、8组合回归与同帧期限测试。它用于测成本，并非正式三效果交付。
- 独立参数/湿度、插值及噪声、整体RT60、最终兼容协议/TAKE与App三卡/APK、最终完整联合验收未完成。字段、兼容与TAKE位域提案见 [ARCHITECTURE.md](ARCHITECTURE.md)。未修改协议生成物或App。

## 同策略实际构建

全部完整构建使用 Gowin V1.9.11.03 Education / GW5A-LV25MG121NC1/I0 / 50MHz / resource_sharing=1 / retiming=1 / place2-route0-maxfan23。未靠追加布局策略取得跨条件数字。

| 构建 | Logic/CLS/Reg/BSRAM/DSP | 相对当前基线 | 未布通 | setup/hold违例 | setup WNS ns | 判定 |
|---|---|---|---:|---|---:|---|
| base | 21860/11317/10571/47/26.5 | +0/+0/+0/+0/+0 | 0 | 0/0 | 0.048 | validated: 当前冻结基线 |
| apds | 21649/11183/10579/47/26.5 | -211/-134/+8/+0/+0 | 0 | 0/0 | 0.03 | validated: 通过并接入 |
| display_pair | 22635/11476/10587/44/26.5 | +775/+159/+16/-3/+0 | 0 | 7/0 | -1.167 | timing_failed: 功能通过；时序/面积拒绝 |
| combo | 22140/11369/10589/44/26.5 | +280/+52/+18/-3/+0 | 0 | 0/0 | 0.03 | validated: 布线时序通过；相对APDS多186CLS，拒绝 |
| flash_default | 21649/11183/10579/47/26.5 | -211/-134/+8/+0/+0 | 0 | 0/0 | 0.03 | validated: 与APDS资源完全相同，无收益 |
| fx_proto | 未形成PnR资源报告 | 不计入 | None | -/- | None | synthesis_resource_exceeded: RAM推断失败，淘汰 |
| fx_sync | 22425/11442/10806/53/26.5 | +565/+125/+235/+6/+0 | 0 | 0/0 | 0.002 | validated: 原型通过PnR；未满足未来预留 |
| fx_apds | 22418/11415/10811/53/26.5 | +558/+98/+240/+6/+0 | 0 | 0/0 | 0.001 | validated: APDS上的原型实际增量；未交付 |

最终生产 APDS：21649/11183/10579/47/26.5。实际 `.prj`、`cmd.do`、`device.cfg`、资源报告、STA HTML与原始 timing_paths 的哈希及输入差异在 [build_audit.json](build_audit.json)、[final_production_audit.json](final_production_audit.json)。源码输入在各构建 `sources.json` 与 [final_inputs.json](final_inputs.json)。

早期部分快照包含Gowin自动写出的.gprj.user及测试日志；审计保留这些条目，不将其误称RTL差异。失败fx_proto的.gprj.user被工具重写，原始不一致也保留；失败候选没有交付。

## 资源账与具体缺口

C/B1已实现，不再预留。D/B2/E100/安全垫沿用最低1650 Logic /365 CLS /4 BSRAM。完整E280口径还需额外180 CLS。尚未逐项量化未来Register/DSP，不能据此宣称所有未来需求已验收。

| 资源 | 最终已用/容量 | 现在剩余 | 后续最低预留 | 当前不加新FX的缺口 |
|---|---:|---:|---:|---:|
| Logic | 21649/23040 | 1391 | 1650 | 259.0 |
| CLS | 11183/11520 | 337 | 365 | 28.0 |
| Register | 10579/23280 | 12701 | 未逐项量化 | 未判定 |
| BSRAM | 47/56 | 9 | 4 | 0 |
| DSP | 26.5/28 | 1.5 | 未逐项量化 | 未判定 |

在同一APDS基线上加入最小三效果，实测增量为 **769/232/232/6/0**。按该原型实测总量再保留后续额度，仍缺 **1028 Logic / 260 CLS / 1 BSRAM**。完整参数、协议及插值成本尚未包含，也未以独立综合或Logic/2冒充可兑现CLS。

以上缺口直接由原型最终资源加预留计算；其中已经包含APDS，不能再次扣减134 CLS。显示配对省3块BSRAM，但它的同机面积代价也已实测，不能只拿内存收益拼入这张表。

本轮没有找到同时填平这些缺口的可交付组合。继续原定功能与预留，必须先取得相应净回收，并验证更紧凑存储或其它BSRAM回收。改变器件、降低后续预留、移除功能均需用户另行决定；本轮未自行采用。

## APDS功能与真实事件时刻

四路累加/平均、端点、方向归一化、饱和/噪声、32轮校准、空FIFO、短读、溢出、NACK恢复的完整语义轨迹相同：快速矩阵1108条、默认活动轮询/释放保护矩阵305条。均值最坏256→1024拍。默认活动等待100000拍，释放保护750000拍；只加速启动/空闲等待。

| 活动轮询参数 | 原/候选分类poll | 原/候选最后有效样本后拍数 | 从同一启动计算的分类时刻差 |
|---:|---|---|---:|
| 100000 | 41/41 | 800396/800569 | +2362拍 |
| 93750 | 41/41 | 750396/750569 | +2362拍 |
| 93700 | 42/41 | 843722/750169 | -91364拍 |

93750/93700是刻意逼近保护边界的定向参数，不是生产100000拍。93700时，候选在本次检查跨过15ms阈值，原版差4拍而等下一轮；可提前91364拍（1.82728ms）分类。两者均不提前于750000拍。原型不承诺逐拍事件等价，也没有把768拍均值增加量冒充整个事件的变化上界。完整命令及事件时间戳在 [apds_event_timing.json](apds_event_timing.json)。

本轮基线与候选均重跑：tb_top_dual_analog、tb_ads1115_bus、tb_analog_expression、tb_apds_nack、tb_i2c_master_bus、tb_top_idle。NACK恢复另由完整控制器事务激励覆盖；未宣称完成真实光学/I²C任意锁死场景验收。

## 显示、最小三效果与期限证据

- 显示既有回归：6174对行掩码、3002组位置算术、133拍外部扫描；音频页/FFT启动/页边界测试通过。
- 新旧冻结RTL逐拍对比：599985次检查、446264次写、25802次配对碰撞（1719次跨半屏同字）、222976次滚动同拍写、3324次ROW_PREP同拍写、45次在途STOP、15次复位；全部逻辑行、行快照、外部输出相同。
- 同步RAM原型与独立采样队列模型：259200个输入/输出，逐样本误差0，8组合/四档延迟/四档混响/配置切换/湿度钳位/复位/满幅覆盖，最长37拍，overrun 0。早期29拍原型因RAM推断失败被弃用。
- 同帧压力的guarded用例：1416完整帧，触摸1012、弯音43、效果37、传感器535拍；338压力帧、4次16声部包络边界、每完整帧恰一个效果结果、RTL overrun/超限/合成混音clipped均0。效果自身空闲987拍；三引擎并集1012拍。
- 顶层原型测试保持50MHz/1024拍；UART 500k、TTP启动100µs、短ADSR/60ms前视，进入播放后一次跳过视觉预滚。FSR关闭、滑杆/回放未联合，因此不是最终完整验收。
- Flash回归：528位同拍原子快照5项、NOR行为模型114项、事件状态机25项通过。它们没有带来新资源收益。

原始日志、向量/样本哈希和汇总见 [functional_results.json](functional_results.json)、[functional/](functional/)、[resource_ledger.json](resource_ledger.json)。

## 可复现步骤与交付指纹

在本工程目录使用本机Python运行。prepare/candidate/build均应使用新目录/标签；不要覆盖本轮证据。新label的构建只读取该label快照，和工具只改输出Label的行为不同。

```powershell
$py = 'E:/300_IDE_Compiler/Python313/python.exe'
# 重验本轮现有证据，不启动构建
& $py reports/fx_delivery_20261025/delivery.py audit apds display_pair combo flash_default fx_proto fx_sync fx_apds
# 在新任务目录复制当前未提交源码；完成快照哈希核对后，使用该副本的tools/build_unified.tcl
# 每个已冻结构建的原命令均为：
# gw_sh.exe <label>/pcm5102_pam8403/tools/build_unified.tcl
# 生产重新构建已执行：gw_sh.exe tools/build_unified.tcl
```

- 最终默认码流：`impl/pnr/PCM5102_UNIFIED.fs`；SHA256 `840AE4C47D7BB57048481ACA3ECB6BEEC59E430E66AF0BD32429FDE99E84AD15`。源码/ROM/约束/工程等101项输入构建前后不变，逐项匹配已验证APDS快照。
- 生产APDS源码SHA256：`4AAA3F1F0E20BFFFB35B49567427ED0054B972D9167F98C5337A3E69FDC77492`。本轮冻结基线与旧默认输出分别在 `base/`、`previous_default/`，未删除。
- App未改、未发新版APK；现有 `android_app/dist/FPGA-Music-Unified.apk` SHA256 `40B92B8201DA38F29140129346E8F02579B532AF443C1BCAA8060B847A015AB6`，与开始时一致，不能把它说成三卡App。
- 起始工具、git状态/完整diff与源清单：[freeze.json](freeze.json)、[starting_status.txt](starting_status.txt)、[starting_diff.patch](starting_diff.patch)、[base_inputs.json](base_inputs.json)。最终生产审计：[final_production_audit.json](final_production_audit.json)。

**本轮未烧录FPGA、未安装手机、未做DAC模拟对录或实体面板/光学验收。**

## 后续边界

只有APDS回收已经交付。整体三效果任务未完成，不能把原型码流或协议提案称为“准备好了”。下一步应以本报告实测缺口为准取得更多净回收；若选择改变硬件或功能预留，必须明确变更对象再继续。
