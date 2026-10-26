# 第二步：LED 显示 RAM 读口优化（2026-10-26）

**已撤回默认接入。** 该候选功能和时序通过，但新增 77 CLS，不符合当前以减少 CLS 为主的目标。默认工程已恢复 11387 CLS / 53 BSRAM；以下为实验与历史接入记录。

| 资源 | 本轮基线 | 本轮结果 | 增量 | 剩余 |
|---|---:|---:|---:|---:|
| Logic | 22447 | 22607 | +160 | 433 |
| CLS | 11387 | 11464 | +77 | 56 |
| Register | 10732 | 10759 | +27 | 12521 |
| BSRAM | 53 | 49 | -4 | 7 |
| DSP | 26.5 | 26.5 | +0 | 1.5 |

比较基线为第一轮 HC-05 优化已经接入的当前工程，而非调研时的 11470 CLS。历史 83 CLS 收益没有计入本轮。本轮只改变显示 RAM 读口结构及报告列明的物理策略；没有迁移其他存储。

## 行为与成本

音符位图由七份 64×7 RAM 改为三份：插入读改写保持独立，上下半屏各一份 RAM 维护三行滑动窗口。每拍只补读一个端点，保留两行并逐拍转发写入；31→0 行先交换上下原始窗口。保持音符每拍接收、OR 合并、滚动有效位、同址读写转发、133 拍扫描、RGB5 PWM、显示模式和快照边界。
实验构建减少 4 个物理 BSRAM；整机 CLS 变化 +77，余量 56，扣除原有 35 CLS 安全余量后的功能预算为 21。新增缓存调度开销已经包含在整机统计中，不能将 RAM 释放解释为同等 CLS 回收。

详细窗口位移、换行交换和冲突语义见 [DESIGN.md](DESIGN.md)。

## 构建与时序

GW5A-LV25MG121NC1/I0，Gowin V1.9.11.03 Education，top_unified，50 MHz；物理策略 {'place_option': 2, 'route_option': 0, 'route_maxfan': 23}，本轮基线为 place1/route0/fan23。sharing=1、retiming=1、enable_dsrm=1、ram_rw_check=0 保持。物理策略改变时，整机 CLS 差值包含 RTL 与放置的联合影响。
未布通 0；setup/hold 违例端点 0/0。原始最差 setup/hold slack +0.895/+0.165 ns，基线 +0.081/+0.153 ns。

## 验证

10 组最终功能检查通过：

- `tb_hub75e_ram_equivalence`：PASS circular display: 179908 cycle/pin checks and full 64-row comparisons, dense 128-clock bursts, consecutive scrolls, OR forwarding, STOP/reset races
- `tb_hub75e_window_raster`：PASS hub75e_rhythm_display: external RGB5/133-clock scan, descent/bursts/scroll/STOP, 3002 arithmetic cases, 6174 reference row pairs
- `tb_hub75e_audio_display`：PASS HUB audio display: external wave/XY pixels, FFT startup blanking, RAM prefetch, three group bars, unchanged 133-clock scan, whole-PWM four-mode switch, hidden guide descent
- `tb_hub75e_status`：PASS HUB status: 32-plane external RGB reconstruction, 8/16 keys, hold, IR, fonts, exact bars, ADC alarm, whole-frame snapshots, guide transition, 133-clock scan
- `tb_display_window_differential`：PASS window differential LEAD=1500 cycles=649972 scan_swap=147 circular_wrap=205 down/up=8535/4814 read_collision=15272 retained_write=30276 OR_merge=243060 clear_write=0 stops=88 frames=4 modes=1111
- `tb_display_window_differential64`：PASS window differential LEAD=64 cycles=649972 scan_swap=147 circular_wrap=3219 down/up=201202/3390 read_collision=15333 retained_write=30035 OR_merge=229045 clear_write=0 stops=88 frames=4 modes=1111
- `tb_top_touch16_recovery`：PASS fixed16 recovery: high-active sensor from boot, SERIAL1 accepted while not ready, all16 voiced, busy protection and TOUCH8 rejection retained
- `tb_fx3_frame_take`：PASS frame budget: real UART/TTP229, 16 voices, four slewing bends, playing score, C+D+R and pressure/ADS1115, independent deadlines and overlap；PASS FX3 actual UART/TTP/dual ADC/TAKE playback: states A=196 B=99 events=102, stored wet overrides changed live slider
- `tb_fx3_replay_decode`：PASS FX3 replay old/new version and unchanged musical fields: 2075 checks
- `tb_fx_take_atomic_528`：PASS full528 FX atomic snapshot: 34 checks; complete capture and no mixed words at any audio frame

两个 LEAD 参数的当前 RTL 差分每拍比较全部面板引脚、握手/overflow、112 位快照、全部 64 行位图及六个逻辑读口。长时间连续播放与毫秒节拍加速均覆盖；这是动态仿真，不是任意内部状态的形式证明。
原扫描测试的六镜像层级注入改为两镜像及缓存的等价初始化，全部原有断言保留。初次层级名编译失败及图片目录缺失日志均保留，不计为通过。整机回归保持 50MHz/1024 拍音频帧；启动、轮询等参数沿用原测试的加速配置。

## 产物与复现

候选输入与审计：[sources.json](window3_place2/sources.json)、[audit.json](window3_place2/audit.json)、[verification.json](window3_place2/verification.json)、[exit.json](window3_place2/exit.json)。
当前生产的 102 项输入先按上一轮接入清单重新核验，然后冻结。另两项 build_inputs JSON 只在冻结目录注入，不计为生产源码漂移。工具、实际综合设置、PNR 命令、资源/时序报告和测试日志均有 SHA256。
候选位流 SHA256：`CB9A5EEE4227DB681E73A0E05EACB00A243597F0AF8465F334BEDF341FA93006`。
回退显示源文件及原综合/PNR 输出见 `production_before/`；原测试夹具位于 `baseline/pcm5102_pam8403/sim/`，接入时另存回退副本。
默认位流已恢复第一轮 HC-05 版本。此实验的独立副本 [PCM5102_UNIFIED_DISPLAY_PORTS_20261026.fs](PCM5102_UNIFIED_DISPLAY_PORTS_20261026.fs)，接入核验见 [integration.json](integration.json)。
未烧录 FPGA、未写板上 Flash，也未进行实板显示/听音验收。

```powershell
python work.py test window3 tb_hub75e_ram_equivalence tb_hub75e_window_raster tb_hub75e_audio_display tb_hub75e_status tb_display_window_differential tb_display_window_differential64
python finish.py collect window3_place2
# 原构建日志不覆盖；复建请另建快照，或在主工程调用 tools/build_unified.tcl。
```

该实验已撤回，未形成已交付 CLS 收益；后续仍需单独测量完整 PNR、扫描/冲突与音频期限。本轮未宣称达到 500 CLS 回收目标，也不将不同候选差值相加。

## 完整实验记录

| 候选 | 策略 | 状态 | 未布通 | 采用 |
|---|---|---|---:|---|
| window3 | place1/route0/fan23 | routing_failed | 221 | 否 |
| window3_place2 | place2/route0/fan23 | validated | 0 | 已撤回 |

place2 与 place1 的全部 RTL/ROM/约束及综合选项完全相同，只改变物理放置选项；功能证据沿用同一 RTL 的十组检查，各策略分别完成构建和审计。失败构建不算收益，各候选差值不相加。
