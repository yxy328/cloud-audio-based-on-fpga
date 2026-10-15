# 提示词：Tang Primer 25K 部署 PCM5102 + PAM8403 最小音频闭环

> 用法：把下面整段（从「# 任务」到「# 已知硬件坑」）一次性粘贴给 AI 编程助手。
> 所有硬件事实、引脚、时钟参数已锁定，AI 不需要也不允许自行更改。

---

# 任务

在高云 GW5A FPGA 上实现一个最小实时音频通路：按键按下时，I2S DAC 输出 440Hz 正弦音；松开静音。一次性输出全部文件：4 个 Verilog 模块 + 顶层 + 约束文件 + testbench。不要提问，不要给替代方案，直接给完整可综合代码。

# 硬件事实（不可更改）

- FPGA：Gowin GW5A-LV25MG121NC1/I0（Sipeed Tang Primer 25K Dock），Verilog-2001，用 Gowin EDA ≥ V1.9.9Beta-4 综合
- 板上晶振：50MHz，接 FPGA 引脚 E2
- Dock 按键 S1 接 FPGA 引脚 H11，按下为高电平（官方例程对该脚用 PULL_MODE=DOWN）
- I2S DAC：PCM5102 模块（已接好线，SCK 引脚悬空，芯片内部 PLL 从 BCK 恢复系统时钟，无需 FPGA 提供 MCLK）
- 音频格式：I2S Philips 标准（LRCK 低 = 左声道；数据 MSB 在 LRCK 边沿之后延迟 1 个 BCK；数据在 BCK 下降沿切换、上升沿被采样），16bit，立体声（左右声道送相同数据）

# 引脚约束（直接照抄进 .cst 文件，不许改引脚号）

```
IO_LOC "clk" E2;
IO_LOC "key_s1" H11;
IO_LOC "i2s_bck" K2;
IO_LOC "i2s_lrck" K1;
IO_LOC "i2s_din" L1;
IO_PORT "clk" IO_TYPE=LVCMOS33;
IO_PORT "key_s1" IO_TYPE=LVCMOS33 PULL_MODE=DOWN;
IO_PORT "i2s_bck" IO_TYPE=LVCMOS33 DRIVE=8;
IO_PORT "i2s_lrck" IO_TYPE=LVCMOS33 DRIVE=8;
IO_PORT "i2s_din" IO_TYPE=LVCMOS33 DRIVE=8;
```

# 时钟参数（已锁定，不要重新计算，不要用 PLL）

- BCK = 50MHz ÷ 16 = 3.125MHz（4bit 计数器整数分频）
- LRCK = BCK ÷ 64 = 48.828kHz（即每声道 32 个 BCK，左右共 64 个）
- 说明：48.83kHz 在 PCM5102 支持的 8k~384k 范围内，芯片按收到的 LRCK 工作，音高偏差 1.7% 可接受。禁止为了凑精确 48kHz 引入 PLL。

# 模块划分

1. `clk_div`：50MHz → BCK(3.125MHz) 与 LRCK(48.828kHz)，输出 bck 上升沿/下降沿脉冲使能
2. `i2s_tx`：16bit×2ch I2S Philips 发送机。输入 sample[15:0]（有符号），在 LRCK 边沿装载，按 MSB 优先、延迟 1 BCK 规则串行输出到 i2s_din
3. `nco_sine`：32bit 相位累加器 + 256 点正弦查找表（可用 1/4 波表对称重建，也可用全波表 initial 初始化）。采样率 = LRCK。相位增量固定 INC=38_702_432（对应 440Hz；公式 INC = freq × 2^32 / 48828.125，换音高只改此值）
4. `volume_key`：key_s1 按下时输出 sample = nco 输出右移 1 位（×0.5，防止后级 PAM8403 功放削波破音），松开时输出 0
5. `top`：实例化以上模块，端口只有 clk、key_s1、i2s_bck、i2s_lrck、i2s_din
6. `tb_top`：50MHz 时钟激励，仿真 3ms，断言检查：(a) LRCK 周期 = 64 个 BCK 周期；(b) DIN 第一个数据位出现在 LRCK 翻转后第 1 个 BCK；(c) 按键按下期间 DIN 上有非零数据流

# 验收标准

- 仿真中 LRCK≈48.83kHz、BCK/LRCK=64、DIN 时序符合 I2S Philips
- 上板：按住 S1 出声（440Hz 附近），松开静音，无破音

# 已知硬件坑（排查用，不用写进代码）

- 没声先查 PCM5102 模块 H3L(XSMT) 跳线是否在 HIGH 侧（LOW=静音）
- H1L/H2L/H4L 保持 LOW；H4L 若为 HIGH 会变左对齐格式导致无声或杂音
- SCK 悬空即可，不要接地以外的任何信号
- PAM8403 是 BTL 输出，L-/R- 不是地，喇叭独立两线、严禁共地
- 声音尖锐破音 = 音量系数不够小，把右移 1 位改成右移 2 位

---

## 这段提示词为什么省额度（设计说明，不用粘贴）

1. **引脚全锁死**：AI 最常见的额度浪费是编造引脚 → 报错 → 来回修改。这里 .cst 直接给全。
2. **时钟方案锁死**：50MHz 不能整除出标准 48kHz 系时钟，AI 容易陷入 PLL 参数计算死循环。直接指定整数分频到 48.83kHz（PCM5102 明文支持），一步到位。
3. **相位增量给数值**：440Hz 的 INC 已算好（38_702_432），AI 不会算错，也不用解释 NCO 原理。
4. **禁止提问 + 禁止替代方案**：砍掉 AI 的确认轮次。
5. **验收标准写成断言**：AI 输出的 testbench 必须自检，仿真波形对不对不用你肉眼看。
6. **硬件坑单列**：真出问题时不消耗 AI 额度，人先按清单排查。
