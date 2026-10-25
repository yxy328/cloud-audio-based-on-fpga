# 阶段 1：共享执行资源的精确兼容方案

2026-10-24。状态：设计契约，数值/周期上界须由阶段 2 仿真验证，资源须由完整 PnR 验证。

## 选择与理由

采用两个固定分区控制器、一个 33×18 有符号乘法器、一个同步 1024×16 正弦 ROM。传感器 controller/RAM 和触摸 controller/RAM 各自保留，传感器资源请求优先，触摸仅在资源请求状态等待 grant。核心共享的是昂贵执行资源，不强行串行全部 RAM 和包络控制。

这是 V2 允许保留独立段准备逻辑的具体实现。触摸的精确 16 拍商/余数除法与原误差累加保留，和传感器计算并行；触摸 RAM 连续读流水省出 192 拍，用于仲裁等待。因不使用近似包络，ADSR 配置/默认值/restore/录制回放格式无需改变。

24 位 reciprocal 相位插值不逐样本等价：对 duration=2..65535、delta=65535、段末前一采样 k=duration−1，比较 `floor(delta*k/duration)` 与 `floor(delta*k*floor(2^24/duration)/2^24)`，存在显著 Q16 增益差。这里不以近似替代精确包络，也不修改旧测试期望。

## 上下文布局

传感器沿用 32×16×36 context，556 有效位/576 填充位；每个槽的字段均保持原符号、范围、初始化及写入状态。没有增加总槽号，TEST32 继续只作用于 32 槽，事件配额保持 32。

| 传感器字段 | 位宽 | 语义 |
|---|---:|---|
| pending / delay_frames | 1 / 6 | 替换及延迟 |
| pending_inc / pending_timbre / pending_frames | 32 / 3 / 17 | 等待起音快照 |
| note_inc / note_timbre / remaining / gain | 32 / 3 / 17 / 9 | 当前声部 |
| body_env / bright_env | 24 / 24 | 音色衰减 |
| phase / aux_phase / aux2_phase / drum_glide | 各 32 | 振荡器状态 |
| noise_state / air_low / prev_pcm | 17 / signed 18 / signed 16 | 噪声、滤波及 PCM |
| stage_gain / frame_gain | 各 9 | 既有流水 |
| env_enabled / env_cfg / env_state | 1 / 129 / 3 | 运行时 ADSR 快照 |
| env_left / env_phase / env_start / env_target | 16 / 24 / 9 / 9 | 包络进度 |

完整打包位序及字写入表以冻结的 `before/src/tdm_synth.v` 为参考，候选不得更改。对每帧全部 512 字逐字比较，覆盖超出 peek_context 的 ADSR 高位。

触摸沿用 256×16 context，固定 16 键，每键地址 `{index,field}`。字 0/1 为 phase，2 为 tail_part/seen_physical/seen/stage，3..12 为 gain/target/ticks/length/step/remainder/error/decay/sustain/release_time，13/14 为 age，15 未用。所有有效值及未用字均与参考逐帧对照。

## RAM 读流水

旧触摸每字 READ_WAIT+READ_WORD，共 26 拍。快速路径只保留首次 READ_WAIT，随后每拍读一个字：

| 边沿 | 消费旧 context_q | 设置下次读地址 |
|---|---|---|
| LOAD | 无 | 0 |
| READ_WAIT | 无 | 1 |
| READ_WORD field=0 | 字 0 | 2 |
| READ_WORD field=1..11 | 对应字段 | 下一预取字 |
| READ_WORD field=12 | 字 12 | 13 |
| ENV | 处理包络，启动 age 预取 | 14 |

age 的原两拍预取和 GAIN/GAIN_WAIT 写回保留。仲裁等待时不得多次推进 age、phase 或包络；等待的 GAIN_WAIT 只可能重复写同一个 age 高字，不能提前推进 field。

## 乘法调度

传感器的原乘法操作数寄存器保留，共享乘法在下列状态执行，并在下一个消费沿前完成：

| 运算 | 资源占用状态 | 结果消费状态 |
|---|---|---|
| LFO 深度 | LFO2 | LFO3 |
| 包络 | LOOK_H2 | LOOK_H3 |
| 调音比率，非 unity 时 | LOOK_AUX、LOOK_AUX2 | PITCH_MUL |
| 振音增量 | PITCH_WAIT | BODY_MUL |
| body | BODY_WAIT | BRIGHT_MUL |
| bright | BRIGHT_WAIT | GAIN_MUL |
| gain | GAIN_WAIT | VOICE_COMMIT |

LOOK_AUX2 必须继续保留调音结果，避免触摸在结果消费前覆盖共享 product。这使最长连续保留窗口为两拍。其他请求不连续。传感器不因触摸请求停顿，既有事件起音和每帧 PCM 完全一致。

触摸在 PITCH_WAIT、GAIN_WAIT、PUBLISH 的第二拍请求乘法器；grant 后下一状态消费结果。每声部两次，加最终归一化一次，共 33 次，每次最多等待两拍。共享 product 直接供两边消费，不加独立结果缓存；正确性依赖上述一拍消费和调音保留规则，测试必须覆盖这些冲突。

## ROM 调度

传感器在接受 sample_ce 的 IDLE、LOOK_BASE..LOOK_AUX2 请求 ROM。传感器索引 `{phase[31:24],2'b00}` 与旧 256 点表逐点一致。传感器连续最多占用六拍。

触摸在 WAVE_WAIT 请求 ROM，地址 `lookup_phase[31:22]`；grant 后 GAIN 消费结果。每声部一次，每次最多等待六拍。原始 synchronous ROM 结果直连两个消费者，每次消费发生在下一边沿覆盖之前。

## 周期与帧契约

传感器保持原最大 `16*32+13*32+23=951` 拍，TEST32 仍为 889 拍，不降低事件配额或改变起音帧。

触摸快速读取后的无仲裁最坏周期：`1012−12*16=820`。保守仲裁上界：`33*2 + 16*6=162`，合计 **982/1024**，余量至少 42。这个保守界略超过 V2 的 960 拍目标，但符合硬 deadline；需实测可达最坏值及调度枚举，不能将 982 写成已测值。

两边同一 sample_ce 原子采样输入，在下一个 sample_ce 前提交各自结果。下游仍在原帧边界消费上帧结果；内部提前提交不改变每帧可见 PCM。touch normalizer 读取上一帧 voice_count 的时机可能与新的提早发布交互，必须逐帧比对并在有差异时固定快照，不接受“只是时序不同”的解释。

独立 reset/clear 不重置另一分区。共享乘法器不需要独立复位，只有在 grant 后才消费它的结果；sensor/touch 的请求均由各自 resetn 门控。触摸模式切换不应丢弃传感器待处理命令。

## 阶段 2 证据要求

冻结原两引擎为独立参考模块。每帧比对完整 contexts、active/count、PCM、clipped 和正常场景 overrun，覆盖八种音色、runtime ADSR、调音/振音、16 键边界、踏板/限制、配置更新、弯音和分区复位。记录最大周期、最长仲裁等待、冲突命中数。调音保留状态和触摸 grant 必须做负例检查。

综合/PnR 对比采用同策略隔离快照，分别报告 CLS、Logic、Reg、BSRAM、DSP。若只是资源转移或时序变差，保留候选与证据，不默认启用。

## 实测结果（2026-10-24，`tb_synth_shared_equivalence` / `tb_synth_shared_arith`）

| 契约项 | 本条设计值 | 实测 | 备注 |
|---|---|---|---|
| 传感器最大帧占用 | 951 | **951** | 与改动前逐帧相同 |
| 触摸无仲裁最坏 | 820 | — | 直接依据 `FAST_READ` 省下的 192 拍 |
| 触摸保守上界 | 982 | **842** | 仲裁只用掉 22 拍；实测值优于保守界，仍按 982 记录为未被证伪的上界 |
| 乘法等待上界 | 2 拍 | 联合负载 **1** 拍；定向用例 **2** 拍 | 两拍窗口只在调音非 unity 的 LOOK_AUX→LOOK_AUX2 出现 |
| ROM 等待上界 | 6 拍 | **6** 拍 | IDLE(sample_ce)+LOOK_BASE..LOOK_AUX2 |
| 调音保留 | LOOK_AUX2 不得被触摸覆盖 | **39808 次消费点逐值相等** | `PITCH_MUL` 拍校验 `note_inc*frame_tuning>>14`，非 unity 调音时每声部每帧一次 |
| 触摸 grant 与传感器申请同拍 | 禁止 | 0 次（`both_req == both_stall`） | 联合负载 13756 次冲突全部由传感器胜出 |
| 版本化等价 | 逐帧逐字 | 1668 个联合帧，传感器 512 字 + 触摸 256 字 context 全等 | PCM/active/count/clipped/overrun 全等，八音色全覆盖 |

周期表里 982/960 的目标与硬限制仍需保留口径差异：**842 是实测最坏值，982 是解析上界**，未做调度枚举穷举，不能把 842 当作所有负载形式的上界。

§"阶段 2 证据要求"中"调音保留状态和触摸 grant 必须做负例检查"已由 `sim/tb_synth_shared_arith.v` 承担：它直接构造两拍保留窗口，并有一次把优先级改成"触摸立即 grant"的负例运行（9 处断言失败、非零退出）。

资源侧结论见 [README.md](README.md)：合并候选在完整 PnR 中 Logic +709、CLS +66、217 条未布通，因此不启用，`SHARED_SYNTH` 默认 0。

