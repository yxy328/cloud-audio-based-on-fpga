# 引擎合并：阶段 1～3 实现、等价证据与资源判定

日期：2026-10-24。方案：[提示词_引擎合并_V2.md](../../提示词_引擎合并_V2.md)。字段/调度契约：[ARCHITECTURE.md](ARCHITECTURE.md)。

本轮把共享运算核心做成可综合、可回归、可回退的原型并跑完 A/B；判定为**不启用**，`top.v` 的 `SHARED_SYNTH` 默认值保持 0。下面是判定依据、可复现命令和未完成项。

## 1. 结论

| 项目 | 结果 |
|---|---|
| 功能等价 | 通过。1668 个联合帧内，传感器 32×16×36 位 context 全 512 字、触摸 256 字 context 逐字与冻结参考相同；`sample`/`active`/`voice_count`/`clipped`/`overrun` 相同；八种音色、16 键、踏板、poly 限制、运行时 ADSR、调音/振音/逐键弯音、连续复位全部覆盖 |
| 周期 | 传感器最坏 951 拍（与基线相同）；触摸最坏 842 拍（基线 1012 拍）。两路都在 1024 拍内提交，无 overrun |
| 仲裁等待 | 联合负载下乘法等待最多 1 拍、ROM 等待最多 6 拍；定向用例把乘法等待的 2 拍上界真正打出来 |
| 资源（完整 PnR，同工具同策略） | Logic 22312（+709）、CLS 11392（+66）、Reg 10410（−51）、BSRAM 46（−1）、DSP 24.5（−2），**217 条网络未布通** |
| 判定 | **不启用。** 本器件最紧张的资源是 CLS（基线 11326/11520 = 98.3%），合并后 CLS 反而 +66，并导致布线失败；只回收了 2 个 DSP 与 1 个 BSRAM |
| 默认构建 | `SHARED_SYNTH=0` 与改动前基线资源、时序完全一致（21603/11326/10461/47/26.5，0 未布通，WNS +0.083/+0.152 ns），参数化改造本身零代价 |

按方案 §7.5：保留可复现原型和原因，不为了完成"合并"替换已工作的默认实现。

## 2. 本轮改动

生产 RTL（`SHARED_ARITH` / `SHARED_SYNTH` 全为参数，默认关闭）：

| 文件 | 改动 |
|---|---|
| `src/synth_shared_arith.v`（新） | 传感器优先的 33×18 共享乘法器与 1024×16 共享 ROM，触摸侧 grant |
| `src/tdm_synth.v` | 共享端口；`shared_mul_request` 在 LFO2/LOOK_H2/PITCH_WAIT/BODY_WAIT/BRIGHT_WAIT/GAIN_WAIT 及非 unity 调音的 LOOK_AUX、LOOK_AUX2 拉高；`shared_sine_request` 在 IDLE(sample_ce) 与 LOOK_BASE..LOOK_AUX2 拉高 |
| `src/touch_tdm_synth.v` | 共享端口；`shared_mul_request` 在 PITCH_WAIT/GAIN_WAIT/PUBLISH 第二拍；`shared_sine_request` 在 WAVE_WAIT；`FAST_READ` 把上下文读流水从每字两拍压成首次等待后每拍一字 |
| `src/sensor_poly_audio.v`、`src/gesture_top.v`、`src/top.v` | 端口透传 + `generate if(SHARED_SYNTH)` 实例化；默认 0 |
| `PCM5102_UNIFIED.gprj` | 登记 `synth_shared_arith.v` |

测试与工具：

| 文件 | 改动 |
|---|---|
| `sim/tb_synth_shared_equivalence.v`（新） | 旧/新实现并行实例化，逐帧逐字比较；本轮修正了其中一条不可达的覆盖断言（见 §5） |
| `sim/tb_synth_shared_arith.v`（新） | 仲裁定向用例：传感器优先、LOOK_AUX2 保留窗口、有符号与满位宽乘积、ROM 相位选择、等待上界 |
| `tools/run_sim.ps1` | 登记两个新用例（默认回归） |
| `tools/check_unified_build.ps1` | 新增可选 `-ParameterOverride Name=Value`：只在快照内改写一个顶层参数，用于同源码 A/B |

## 3. 仿真证据

命令（在 `pcm5102_pam8403` 目录执行）：

```powershell
./tools/run_sim.ps1 -Tests tb_synth_shared_equivalence     # 联合全长度等价
./tools/run_sim.ps1 -Tests tb_synth_shared_arith           # 仲裁定向
./tools/run_sim.ps1 -Tests tb_engine_merge_baseline,tb_tdm_queue,tb_runtime_adsr,tb_touch_tdm_synth,tb_tdm_adsr,tb_sensor_eight_timbres
```

结果：

| 用例 | 结果 |
|---|---|
| `tb_synth_shared_equivalence` | PASS `joint_frames=1668 sensor_frames=1671 touch_frames=1671 sensor_max=951 touch_max=842 mul_stalls=13756 rom_stalls=40569 max_wait=1/6 tuning_hold_hits=39808 timbres=ff` |
| `tb_synth_shared_arith` | PASS `sensor priority, look_aux2 retention, signed and 51-bit products, rom phase mux, wait 2/6, 17 rom comparisons` |
| `tb_synth_shared_arith`（负例：把优先级改成"触摸立即 grant"） | FAIL，9 处断言失败并 `$fatal`。证明断言真的会失败，不是空通过 |
| `tb_engine_merge_baseline` | PASS，双引擎路径 `sensor_max=951 touch_max=1012`（`FAST_READ=0`，即改动前行为仍可复现） |
| `tb_tdm_queue` / `tb_tdm_adsr` / `tb_sensor_eight_timbres` / `tb_runtime_adsr` / `tb_touch_tdm_synth` | PASS（951 拍预算、FIFO64、替换、八音色、1001 档 ADSR、16 键频谱均未变） |
| `tb_top_idle` / `tb_top_ir_tdm` / `tb_top_touch16`（`-Quick`，默认 `SHARED_SYNTH=0`） | 全部 PASS：顶层 idle 不发声、IR8+手势+TEST32 32 个独立频率+外部 I2S、16 键 UART/TTP 集成与 hold/panic/K16 |

负例复现（不修改生产源码）：

```powershell
# 生成一个去掉传感器优先级的临时副本，用例必须失败
(Get-Content src/synth_shared_arith.v -Raw).Replace(
  'assign touch_mul_grant=touch_mul_request && !sensor_mul_request;',
  'assign touch_mul_grant=touch_mul_request;') | Set-Content sim/build/synth_shared_arith_broken.v
C:/iverilog/bin/iverilog.exe -g2001 -s tb_synth_shared_arith -o sim/build/tb_broken.vvp `
  sim/tb_synth_shared_arith.v sim/build/synth_shared_arith_broken.v src/touch_sine_rom.v
C:/iverilog/bin/vvp.exe sim/build/tb_broken.vvp   # 期望非 0 退出
```

## 4. 周期证据

| 通道 | 改动前 | 本轮（`SHARED_SYNTH=1`） | 说明 |
|---|---:|---:|---|
| 传感器最大帧占用 | 951 | 951 | 事件配额、起音帧、每帧 PCM 不变；共享仲裁没有让它变慢 |
| 触摸最大帧占用 | 1012 | 842 | `FAST_READ` 省下 12×16=192 拍，仲裁只吃掉其中 22 拍 |
| 触摸保守解析上界 | — | 982 | 实测 842，说明解析上界成立且留有余量；不把 982 当实测值 |

传感器请求/消费关系是"请求拍 → 下一拍消费"，唯一的两拍窗口是非 unity 调音：`LOOK_AUX` 发出乘法、`LOOK_AUX2` 再发一次（同一操作数）以占住乘法器、`PITCH_MUL` 消费。因此在调音非 unity 时，触摸不可能在保留窗口内被 grant——这一点由定向用例和 39808 次消费点数值校验共同证明。

## 5. 覆盖断言的修正（重要）

上一轮的联合用例有一条断言：

```verilog
if(sensor.state==sensor.LOOK_AUX2 && tuning!=16384 && sm && tm)tuning_holds=tuning_holds+1;
```

它要求"触摸恰好在传感器 LOOK_AUX2 拍申请乘法器"。用临时插桩跑同一负载（1675 帧）得到的分布是：

```text
aux2_any=53536 aux2_tuned=39808 both_req=13756 both_stall=13756
sm&&tm 分布：LOOK_H2=343 PITCH_WAIT=6779 BRIGHT_WAIT=6633 GAIN_WAIT=1
             LOOK_AUX=0 LOOK_AUX2=0 BODY_WAIT=0 LFO2=0
```

即：LOOK_AUX2 共出现 53536 拍、其中 39808 拍调音非 unity 且传感器确实在申请乘法器，但触摸的申请从未落在这两拍上。原因不是运气，而是设计已经消除了该冲突——传感器在 LOOK_AUX 与 LOOK_AUX2 连续两拍申请乘法器，触摸的 grant 在这两拍恒为 0（`both_req == both_stall`）。也就是说原断言在结构上不可达，任何"通过"都无法由它证明。

处理方式不是删除校验，而是换成两条更强、可达的检查：

1. **消费点数值校验**：传感器进入 `PITCH_MUL` 且调音非 unity 时，共享乘积必须恰等于 `note_inc*frame_tuning>>14`。这项检查在联合用例里执行了 39808 次，任何被触摸覆盖的乘积都会立刻失败。
2. **优先级不变量**：`tm && mg && sm` 视为致命错误（触摸 grant 与传感器申请同拍）。
3. 另加 `sim/tb_synth_shared_arith.v` 定向用例，直接构造"两拍保留窗口内触摸申请"，实测传感器两拍都赢、乘积保留、第三拍才 grant，并用负例证明断言会失败。

这是一次**增强**，不是降低期望：旧断言即使通过也不能说明保留语义正确，新检查在每一次消费上验值。

## 6. 资源证据

同一工具（Gowin V1.9.11.03）、同一策略（`build_unified.tcl` 的 `-place_option 0 -route_option 0 -route_maxfan 23`）、同一工作区：

| 构建 | 源码状态 | Logic | CLS | Reg | BSRAM | DSP | 未布通 | Setup/Hold WNS |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `engine_share_base_20261024` | 改动前（15:27 快照，RTL 编辑之前） | 21603 | 11326 | 10461 | 47 | 26.5 | 0 | +0.083 / +0.152 |
| `engine_merge_candidate_20261024_01` | `SHARED_SYNTH=1`，place 0/route 0/fanout 23 | 22312 | 11392 | 10410 | 46 | 24.5 | **217** | — |
| `engine_merge_candidate_20261024_p1r0f32` | `SHARED_SYNTH=1`，place 1/route 0/fanout 32 | 22312 | 11369 | 10410 | 46 | 24.5 | **228** | — |
| `engine_merge_default_off_20261024_02` | 交付源码（`SHARED_SYNTH=0`） | 21603 | 11326 | 10461 | 47 | 26.5 | 0 | +0.083 / +0.152 |

差值（候选 − 基线）：Logic **+709**、CLS **+66**（place 0）或 **+43**（place 1）、Reg −51、BSRAM −1、DSP −2。

读法：

- DSP 与 BSRAM 的回收是真的（触摸与传感器的本地 ROM 都被优化掉，`touch_sine_rom u_sine` 在综合日志中被 swept；块 ROM 47→46）。
- 但换来的代价落在最紧的资源上。**推断（未做模块级归因，属最可能解释）**：33×18 操作数选择、51 位乘积选择、32 位相位选择这三个 MUX 挂在 DSP 输入/输出前，Gowin 把它们算进 Logic/CLS，且非 unity 调音多出一次 33×18 乘法请求；净增 709 Logic、CLS 从 98.3% 涨到 98.9% 后布线失败。要证实需要模块级资源归因，本轮没有做。
- 这不是"策略运气"：同一策略下基线 0 未布通、改动后 217 条；换成 place 1 / route 0 / fanout 32 仍是 228 条未布通（CLS 11369）。两种策略都失败，因此判定为源码级问题，不是布局选项没选对。
- `SHARED_SYNTH=0` 的交付源码与改动前基线资源、WNS 完全一致，说明参数化改造没有把任何成本带进默认构建。
- 对"省 CLS"这个目标的方向性结论：本器件是 CLS 受限（98.3%）、DSP 也接近满（26.5/28），把 LUT 组成的 33×18 乘法搬到一个共享实例上并不能减少 LUT，反而增加选择逻辑。要真正省 CLS，需要让运算落进 DSP 或减少 LUT 型加法树，而不是"合并同类乘法"。

审计文件：[`build_audit.json`](build_audit.json)、[`build_audit.md`](build_audit.md)（含每个快照的 `sources.json` 哈希清单、位流 SHA256、未布通数、时序端点）。

交付一致性：`engine_merge_default_off_20261024_02` 快照里的 `src/top.v` 与工作区交付文件 SHA256 相同（`9D87B26B…8ECD7`），即"已验证为 0 未布通"的那份源码就是工作区源码，没有依赖构建脚本的临时改写。进一步核对该快照 `sources.json` 的 99 个条目与当前工作区逐字节比对：0 缺文件、0 哈希不一致。

### 6.1 工程默认 `Place_Option=3` 会布不通（与合并无关）

工作区 `impl/PCM5102_UNIFIED_process_config.json` 保存的是 `Place_Option="3"`、`Route_Option="0"`、`Route_Maxfan="23"`；而 `tools/build_unified.tcl` 用的是 `-place_option 0`。同一份交付源码，只改这一个选项：

| 构建 | place/route/fanout | Logic | CLS | 未布通 | 位流 |
|---|---|---:|---:|---:|---|
| `engine_merge_default_off_20261024_02` | 0/0/23 | 21603 | 11326 | **0** | 有，WNS +0.083/+0.152 |
| `engine_merge_place3_probe_20261024` | 3/0/23 | 21600 | 11205 | **247** | 无 |

`3/0/23` 那份与用户在 Gowin IDE 里跑出的结果逐项相同（21600 / 11205 / 10461 / 47 / 26.5，247 条未布通），说明差异完全来自 `Place_Option`，不是源码、不是综合选项、也不是合并引擎。注意 place 3 反而**少用 121 个 CLS** 却布不通 —— 该器件 CLS 已到 98%，能否布通由布局算法的合法性决定，不由资源余量决定。工程内历史记录也反复出现同类摆动（同一份源码 0 / 72 / 277 / 4210 条未布通，见 `reports/fx_preflight_20261024/build_audit.md`）。

结论与操作要求：**该工程应以 `place_option 0` 产出交付位流**；用 IDE 直接 Place & Route 前必须把 Project → Configuration → Place & Route → Place Option 改成 0，否则会得到无位流的失败构建。

## 7. 本轮未完成 / 边界

- **未上板。** 触摸与传感器同时发声、踏板、弯音、TEST32 频谱都只有仿真证据，没有硬件实测。
- **合并路径（`SHARED_SYNTH=1`）没有跑完整顶层回归。** 顶层用例以 `SHARED_SYNTH=0` 为默认；合并路径的证据是模块级全长度等价（1668 帧、逐字 context）+ 仲裁定向。若要启用，必须先补 `tb_top_pedal`、`tb_top_voice_bend`、`tb_top_runtime_adsr`、`tb_top_performance`、`tb_top_audio_record` 等全长度顶层用例，并提供可布通的策略。
- **全量默认回归（约 100 个用例）本轮未跑完。** 全长度 `tb_top_pedal` 单条在本机超过 15 分钟 CPU 仍未结束（尾部 58594 帧），本轮改为模块级全长度用例 + 三条顶层 `-Quick` 冒烟（`tb_top_idle`、`tb_top_ir_tdm`、`tb_top_touch16`，均已 PASS）；`tb_top_pedal` 的 58594 采样尾音证据沿用阶段 0 记录，未在本次改动后的默认源码上重跑。
- **方案 §5 的剩余矩阵项**：FIFO64 突发 + TEST32 续发 + 触摸松键同帧、`poly_limit` 小于物理键数时的 victim 快速阻尼、配置更新时旧声部快照，已由既有 `tb_tdm_queue`/`tb_touch_tdm_synth`/`tb_runtime_adsr` 覆盖模块级，但**没有**在合并核心上重跑组合场景。
- **故障注入**只做了仲裁负例；"禁止越分区写入"和"TEST_NOTES 固定 32"的注入断言仍未写。
- 合并候选在两种策略下都未布通（217 / 228 条），未再尝试第三种策略：CLS 没有净收益，继续调策略不会改变投入价值判定。

## 8. 方案 §5 必测矩阵的覆盖状态

合并核心（`SHARED_ARITH=1`）上本轮实际覆盖到的：

| 矩阵行 | 状态 | 承载用例 / 说明 |
|---|---|---|
| TEST32 与 16 键同帧开始 | 部分 | 联合用例开局 `gates=physical=0xffff` 后立即 TEST32；32 个不同频率与 16 键同时存在，但不记录首末起音帧号 |
| 传感器 32 槽满再进事件 | 覆盖 | 联合用例 64 条事件压入 32 槽；两引擎 context 逐字相同即证明触摸 context 未被写坏；替换策略另由 `tb_tdm_queue`、`tb_engine_merge_baseline` 覆盖 |
| `poly_limit` 小于物理按键数 | 覆盖 | 联合用例 `physical=0xffff`、`poly=1` 时断言 `tactive==0xffff` 且 `victim_valid==0`，命中 6 帧 |
| FIFO64 突发 + TEST32 续发 + 触摸松键同帧 | **未覆盖** | `tb_tdm_queue` 只覆盖传感器 FIFO64 单独场景 |
| 故意超 FIFO / 重复 sample_ce | 部分 | `tb_tdm_queue` 覆盖传感器负例；触摸 `overrun` 只做与参考实现的相等比较（两侧均为 0） |
| ADSR 0/1/最大合法时长、中途松键、重触发 | 覆盖（模块级） | `tb_runtime_adsr` 1001 档 + 联合用例随机 A/D/S/R |
| 配置更新时已有音符持续 | 覆盖（间接） | 联合用例每 17 帧改写 `adsr_config`/`touch_cfg`/`steps`/`ratio`/`tuning`，context 逐字相同 |
| 默认/恢复/录制回放配置 | 部分 | `tb_runtime_adsr` 覆盖默认/恢复；回放配置由顶层用例覆盖，本轮未跑 |
| 1200 ms 踏板四段、取消踏板、尾音淘汰 | 未覆盖 | 联合用例用 `PEDAL_TAIL_MS=8`；全长度 `tb_top_pedal` 本轮未跑 |
| 触摸 2/4/8/16 键、传感器静音→满载 | 覆盖 | 联合用例 `poly` 随机 1/2/4/8/16，`gates`/`physical` 随机 |
| 压力、逐键弯音、调音、振音同时变 | 部分 | 弯音由 `ratio`/`steps` 覆盖，调音/振音覆盖；压力是顶层 FSR 信号，模块级用例不含 |
| panic、perf_kill、8/16 键模式切换、连续复位 | 部分 | 联合用例在第 300/500/700/900 帧分别复位单侧引擎；panic/perf_kill 属顶层语义 |
| 47 号槽与 RAM 边界 | 不适用 | 采用 32＋16 固定分区，没有 48 号槽（见架构文档） |
| 断言故障注入 | 部分 | 仲裁优先级负例已做；分区写入与 `TEST_NOTES=32` 注入未做 |

## 9. 复现

```powershell
# 1) 默认（不启用合并）资源与布线
./tools/check_unified_build.ps1 -Label engine_merge_default_off_YYYYMMDD_N

# 2) 合并候选（同一源码仅一个参数不同，便于隔离）
./tools/check_unified_build.ps1 -Label engine_merge_candidate_YYYYMMDD_N -ParameterOverride SHARED_SYNTH=1

# 3) 汇总审计（基线必须是改动前快照）
<bundled-python> tools/audit_fx_builds.py --baseline engine_share_base_20261024 `
  --labels engine_merge_candidate_20261024_01 engine_merge_candidate_20261024_p1r0f32 `
  engine_merge_default_off_20261024_02 --output reports/engine_merge_impl_20261024

# 4) 仿真
./tools/run_sim.ps1 -Tests tb_synth_shared_equivalence,tb_synth_shared_arith
```

注：本机 PowerShell 5.1 下 `./tools/run_sim.ps1` 需要 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`；另外不要对 `run_sim.ps1` 的输出做 `2>&1` 重定向，`$ErrorActionPreference='Stop'` 会把 iverilog 的 timescale 警告当成终止错误。
