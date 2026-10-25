# 提示词包 · LED 波形颜色按音量沿色环变化

**状态：2026-10-23 已实现并过 RTL 仿真。** 决策 4.1 选「拉满明度 V=1.0」，决策 4.4 选「2 档=青、8 档=红」。
下面第 2、3 节保留推导过程，第 3 节的表就是最终写进 RTL 的常数。

配套核对图：`design/led_scope_20261022/hue_ramp/hue_ramp_mapping.png`
（由 `tools/render_scope_hue_ramp.py` 生成，波形像素直接取自 `sim/build/*.ppm` 真实 RTL 帧，
脚本会把每帧的主色与规格表逐一比对，不一致就非零退出）

---

## 1. 一句话目标

混音峰值越大，LED 波形颜色沿色环从**青 → 蓝 → 靛 → 紫 → 品红 → 玫红 → 红**连续推进；
峰值小是青色，峰值到响度参考（2048）时正好是红色。

## 2. 现状事实（可核对，不要凭记忆改）

- 颜色只由一个函数决定：`src/audio_scope.v:35-50` 的 `palette(capture_peak)`，输出 RGB5 15 位。
- 档位断点：`peak==0` 灰 `(8,8,8)`；`peak>=8` 硬钉红 `(31,0,0)`；`1..7` 用 `peak[2:0]` 查 7 个常数，
  从 `(0,0,24)` 纯蓝一路走到 `(31,0,8)`。也就是说**现在只有 6 档有效色，且低端没有青色、≥8 全糊成红**。
- `capture_peak = ceil(abs(PCM)/256)`，见 `src/audio_visualizer.v:38-41`。所以 128→1 档、512→2 档、1024→4 档、2048→8 档。
- 量程保护 `safe_range` 用的也是 `capture_peak`（`src/audio_visualizer.v:48-50`），**颜色改动不许碰它**。
- 底部 PK 电平条与波形同色：`src/audio_scope.v:132` 用的是 `shown_color`，改 `palette()` 会自动跟着变。
- 频谱页和 XY 页不按幅度上色（`src/audio_spectrum.v` 里没有颜色常数），本次不动它们。

## 3. 期望映射（色环公式）

7 个取色样本 `#12b9ba #1258ba #1f12ba #8812ba #ba1297 #ba1247 #ba1812` 的共同点是：
**饱和度固定 S=0.903、明度固定 V=0.729，只有色相在动**，色相从 180° 走到 362°≈0°，
即正好色环的**下半圈**（青→红，不经过绿和黄）。

所以规则写成（最终实现版）：

```
n   = min(capture_peak, 8)
hue = clamp(180° + (n - 2) × 30°, 180°, 360°)   // n=1 与 n=2 同为 180° 青
S   = 0.903（固定）
V   = 1.000（固定，最高通道 = 31）
```

换算成 Verilog 需要的 RGB5 常数（HSV→RGB 后按 `round(v*31)` 量化）：

| n（=capture_peak） | PCM 峰值区间 | 色相 | 最终 RGB5 | 旧值 |
|---|---|---|---|---|
| 0 | 静音 | — | `(8,8,8)` 低亮白 | `(8,8,8)` |
| 1 | 1~256 | 180° 青 | `(3,31,31)` | `(0,0,24)` |
| 2 | 257~512 | 180° 青 | `(3,31,31)` | `(0,0,31)` |
| 3 | 513~768 | 210° | `(3,17,31)` | `(8,0,31)` |
| 4 | 769~1024 | 240° 蓝 | `(3,3,31)` | `(16,0,31)` |
| 5 | 1025~1280 | 270° 紫 | `(17,3,31)` | `(24,0,24)` |
| 6 | 1281~1536 | 300° 品红 | `(31,3,31)` | `(31,0,16)` |
| 7 | 1537~1792 | 330° 玫红 | `(31,3,17)` | `(31,0,8)` |
| ≥8 | ≥1793 | 360° 红 | `(31,3,3)` | `(31,0,0)` |

档位边界**完全沿用现有 `capture_peak` 数值**，不做重划，这样 `safe_range`、PK 百分比、电平条长度全都不变。

## 4. 决策记录（已定）

1. **明度：选 V=1.000。** 你取的色最高通道是 23/31（73%），照抄会让面板整体比原来的 `(31,0,0)` 暗约 26%；
   现场 LED 屏本身偏暗，所以整列提亮到 31，色相关系与你取的色完全一致。
2. **离散 8 档，不做连续插值。** 想更顺滑要把 8 位 `capture_peak` 映射成 6~8 位色相再做 HSV→RGB5
   分段线性，会多一个乘法/大 mux，CLS 余量紧张；先看现场够不够。
3. **≥8 钉红。** 与原来行为一致，只是红色从 `(31,0,0)` 变成 `(31,3,3)`。
4. **色环两端钉在 2 档=青、8 档=红（这条最影响观感）。** 正常演奏时 `capture_peak` 实际只在 **2..8**
   之间动（FSR 25%/50%/100% 分别落在 2/4/8 档）。若按「1 档=青」钉，青色永远看不到；
   现在 1、2 档同为青（低端钳位），2→8 正好走完你取的 7 个色，中间不经过绿和黄。

## 4b. 改颜色必须同步的六处（实际踩出来的，漏一处就是仿真直接 FATAL）

1. `src/audio_scope.v` 的 `palette()` 常数
2. `sim/tb_audio_scope.v` 第 85/90/95/99/101/109/121 行的 `shown_color` 断言
3. `sim/tb_audio_visualizer.v` 第 76/78/87 行的满量程像素断言
4. `sim/tb_hub75e_audio_display.v` 第 89/90/91 行的 PWM 位平面断言
   （`inspect` 等的是 `pwm_phase==0`，判据是「通道值 >0 则亮」，所以绿通道从 0 变成 3 会让 `3'b101` 变 `3'b111`）
5. `sim/tb_top_audio_visual.v` 原第 185 行的「绿色通道必须为 0」判据 —— 这条是旧设计的白化保护，
   色环里的青/蓝绿本来就要开绿通道，已改成「最高通道=31 且最低通道=3」的饱和度判据
6. `tools/check_scope_external.py` 第 10 行的外部独立 RGB5 栅格模型颜色

第 4、5、6 处只有跑到对应测试才会暴露，改完颜色要把这四个 TB 和外部模型一起跑一遍。

## 5. 实现约束（硬要求）

- 只改 `src/audio_scope.v` 的 `palette()` 函数体，**不改端口、不改时序、不新增模块**。
- 不许引入乘除法、DSP、新的 ROM 地址；纯常数查表，资源占用应与现在同级（本项目 CLS 余量紧张）。
- `peak==0` 仍返回 `(8,8,8)`，静音零线不能变色。
- 保留/更新 `src/audio_scope.v:39-41` 的注释：说明 2048 是「响度参考」而不是削峰或声压级。
- 注释里不要写「按需求单 #xxx」这类会过期的话，只写为什么是这个色相区间。

## 6. 验收

1. ~~跑仿真重新生成 PPM~~ **已做**：`tools/run_sim.ps1 -Tests tb_audio_scope` 与 `tb_audio_visualizer` 双 PASS，
   `sim/build/scope_fsr{25,50,100}.ppm`、`scope_weak128.ppm`、`scope_overrange.ppm`、`scope_silence.ppm` 全部重出。
2. **已做**：`python tools/render_scope_hue_ramp.py` —— 该脚本会逐帧取 `sim/build/*.ppm` 的主饱和色，
   与规格表比对，不一致直接非零退出。当前输出 `OK 4 RTL frames match the wheel spec`。
3. **已做**：`python tools/render_scope_verification.py` 出六帧对比图，文字/刻度/零线/PK 数字颜色未被带歪；
   `scope_silence.ppm` 仍是 `(8,8,8)` 低亮白零线。
4. **待做**：综合布局未跑（纯常数替换，`palette()` 的组合逻辑规模不变，CLS 应无变化）；
   上板目视：轻压青、中压蓝紫、重压红，**中间不许出现绿和黄色**。

---

## 7. 短版提示词（想在别的分支重做一遍时粘贴这段）

> 把 `src/audio_scope.v` 的 `palette()` 换成色环映射：`n=min(capture_peak,8)`，
> 色相 `hue=clamp(180+(n-2)*30, 180, 360)` 度，饱和度固定 0.903、明度固定 1.0，量化成 RGB5 写死 8 个常数
> （1、2→`(3,31,31)`、3→`(3,17,31)`、4→`(3,3,31)`、5→`(17,3,31)`、6→`(31,3,31)`、7→`(31,3,17)`、
> ≥8→`(31,3,3)`），`peak==0` 仍为 `(8,8,8)`。只改这一个函数，不动端口、时序、`safe_range` 和 ROM，
> 不引入乘除法。**必须同步** `sim/tb_audio_scope.v` 第 85/90/95/99/101/109/121 行和
> `sim/tb_audio_visualizer.v` 第 76/78/87 行的颜色断言，否则仿真直接 FATAL。
> 改完跑 `tools/run_sim.ps1 -Tests tb_audio_scope`、`-Tests tb_audio_visualizer`，
> 再跑 `python tools/render_scope_hue_ramp.py` 确认四档是 青/青/蓝/红。

---
---

# 阶段 F · 色环丝滑化（8 档 → 33 档）

预览图：`design/led_scope_20261023/hue_smooth_33_preview.png`
（`tools/render_scope_hue_smooth_preview.py` 生成；公式已与真 HSV 逐档比对，33 档全部误差 ≤1 LSB）

## F.0 先接受这 4 条物理事实，否则方案会白做

1. **`capture_peak` 最多只能给 8 档。** 它是 `ceil(|PCM|/256)`（`src/audio_visualizer.v:38-41`），
   响度参考 2048 对应码 8，所以 0~2048 之间只有 8 个格子。**要丝滑必须先换一根更细的峰值轴**，
   光改颜色常数是走不出 8 档的。
2. **33 档是硬上限。** 波形样本存的是 `quantized_sample = mixed_sample[15:6]`，即 **PCM/64** 量化
   （`src/audio_visualizer.v:34`）。2048/64 = 32 → 0..32 共 **33 级**。想再细就得改 10 位极值的量化步长，
   那会动 RAM 几何与波形高度，`RAM_GEOMETRY_VERIFICATION.md` 锁着，**本阶段不许动**。
3. **`range_word` 不能拿来算颜色。** 它是逐列（每 4 像素一列）从显示 RAM 读出来的窗口极值，
   每个像素都在变。用它上色会让颜色沿 x 轴抖动。颜色必须来自**和 `capture_peak` 一样在 publish 边界锁存的快照**。
4. **一帧只有一种颜色。** `shown_color` 整帧共用（`src/audio_scope.v:132` 的电平条也用它），
   每约 10.5ms 换一次。所以「丝滑」体现在**渐强过程中颜色一档档挪**，不是一根线里有渐变。
   要沿线渐变就得给每列存颜色 → 改显示 RAM 字长，属于另一个阶段。

## F.1 目标

在 0 → 2048 计数之间放 33 个色相点，每点只差 5.625°，从 180° 青连续推到 360° 红；
超过 2048 钳在红。纯整数组合逻辑，**不查表、不占 BSRAM、不用 DSP**。

## F.2 已验证的整数公式

`p` = 窗口 |峰值| 按 PCM/64 计，饱和到 63：

```
q = min(p, 32) × 6          // 0..192
扇区 = q ÷ 64               // 0 / 1 / 2
u = q mod 64                // 0..63
d = (u × 7) ÷ 16            // 0..27，即 28×u÷64
扇区0 → R=3,  G=31-d, B=31
扇区1 → R=3+d,G=3,    B=31
扇区2 → R=31, G=3,    B=31-d
q=192 → 钉 (31,3,3)
```

`×7` 用 `(u<<3)-u` 实现，`÷16` 是移位，`×6` 用 `(p<<2)+(p<<1)`。**没有任何除法或乘法器。**

锚点实测值：

| p | PCM 峰值 | RGB5 | 色相 |
|---|---|---|---|
| 0 | <64 | `(3,31,31)` | 180° |
| 2 | 128 | `(3,26,31)` | 191° |
| 8 | 512 | `(3,10,31)` | 225° |
| 16 | 1024 | `(17,3,31)` | 270° |
| 24 | 1536 | `(31,3,24)` | 315° |
| ≥32 | ≥2048 | `(31,3,3)` | 360° |

## F.3 落地骨架

**`src/audio_visualizer.v`** —— 加一根与 `capture_peak` 并列的 6 位饱和累加器：

```verilog
    reg [5:0] capture_peak64;
    // 10-bit unsigned magnitude of the signed PCM/64 sample. -512 wraps to 512,
    // which the saturating compare clamps, so no 11-bit temporary is needed.
    wire [9:0] magnitude64_full=quantized_sample[9] ? (~quantized_sample+10'd1) : quantized_sample;
    wire [5:0] magnitude64=magnitude64_full>10'd63 ? 6'd63 : magnitude64_full[5:0];
```

> 上面两段（`magnitude64` 与 `palette`）已在 Icarus 上单独跑过穷举验证：
> `quantized_sample` 全部 1024 个取值、`p` 全部 0..63，
> 单调性与饱和性 0 失败。**不要写成 `10'h400-q`** —— `10'h400` 会被截断成 0，iverilog 会报
> `Numeric constant truncated to 10 bits`，虽然结果碰巧也对，但那是靠回环撞出来的。

- 复位、`capture_restart` 清零处必须与 `capture_peak` **逐处对齐**（`src/audio_visualizer.v:115`、`:130`），
  漏一处就会跨窗口残留旧峰值，颜色卡在红不下来。
- 累加处与 `src/audio_visualizer.v:150` 同一 `sample_ce` 分支：
  `if(magnitude64>capture_peak64)capture_peak64<=magnitude64;`
- **`safe_range` 继续用 `capture_peak`，一行都不许改。** 量程保护和颜色解耦是这个设计的前提。
- 新增输出端口把 `capture_peak64` 送进 `audio_scope`（`src/audio_visualizer.v:178` 的例化处同步加）。

**`src/audio_scope.v`** —— `palette()` 换成 F.2 的公式，输入改成 6 位 `peak64`。已穷举验证的写法：

```verilog
    function [14:0] palette;
        input [5:0] peak;
        integer q,u,d;
        reg [4:0] r,g,b;
        begin
            q=(peak>6'd32 ? 8'd32 : {2'd0,peak})*8'd6;
            u=q%64; d=(u*7)/16;
            case(q/64)
                0:begin r=5'd3; g=5'd31-d; b=5'd31; end
                1:begin r=5'd3+d; g=5'd3; b=5'd31; end
                default:begin r=5'd31; g=5'd3; b=5'd31-d; end
            endcase
            if(q>=192)begin r=5'd31; g=5'd3; b=5'd3; end
            palette={r,g,b};
        end
    endfunction
```

- **静音判据必须继续用 `capture_peak==0`，不能改成 `peak64==0`。** 因为 |PCM| 在 1~63 时
  `capture_peak=1`（非静音）但 `peak64=0`，若用 `peak64==0` 判静音，最轻的信号会被画成静音灰。
  写成：`shown_color <= capture_peak==0 ? {5'd8,5'd8,5'd8} : palette(peak64==0 ? 6'd1 : peak64);`
- 端口宽度变了，`hub75e_rhythm_display.v` 等所有例化点都要跟着改。

## F.4 资源与风险

- 估算：6 位累加器 + 10 位取绝对值 ≈ 20 CLS；色环公式 ≈ 20 CLS。**合计约 40 CLS，不占 BSRAM/DSP。**
- 改完必须重跑综合看 CLS 与 `WNS`；`palette()` 从 8 项 case 变成带移位/比较的组合链，
  但只在 `publish` 那拍被采样，不在像素扫描路径上，时序压力小。
- 回退方案：若 CLS 不够，把 `min(p,32)` 改成 `min(p>>1,16)` → 17 档（每档 11.25°），
  省掉 `×6` 的加法器，仍然是「看得出在滑动」的连续感。

## F.5 同步清单（比上一阶段更狠，颜色值全变）

第 4b 节那 6 处之外，本阶段还要加：

7. `audio_scope` / `audio_visualizer` 的**端口与例化**（新增 6 位峰值通道）
8. 所有断言了具体颜色的 TB：`tb_audio_scope.v`（7 处）、`tb_audio_visualizer.v`（3 处）、
   `tb_hub75e_audio_display.v`（3 处 PWM 位平面）、`check_scope_external.py`（1 处）
   —— 新值见 F.2 表：128→`(3,26,31)`、512→`(3,10,31)`、1024→`(17,3,31)`、2048/满幅→`(31,3,3)`
9. `tools/render_scope_hue_ramp.py` 的 `OLD` 表与 `FRAMES` 档位（它现在按 `capture_peak` 校验，要改成按 `peak64`）
10. 文档 `SCOPE_DISPLAY.md:13`、`AUDIO_VISUAL.md:23`：把「每 256 计数一级 / 8 档」改成「每 64 计数一级 / 33 档」

## F.6 验收（用单调性断言替代写死 33 个常数）

1. 在 `tb_audio_scope.v` 里加一段 `for(p=0;p<=63;p=p+1) begin force ...; #1; ... end`，
   检查 `palette()` 输出满足：**R 单调不降、G 单调不升、B 单调不升**，且 `p=0` 是 `(3,31,31)`、
   `p>=32` 恒为 `(31,3,3)`。这三条单调性一次性覆盖「不经过绿和黄」与「色相不倒退」，
   比逐个钉 33 个常数好维护。
2. 加静音边界用例：`|PCM|=1` 时 `capture_peak=1`、`peak64=0`，颜色必须是 `(3,31,31)` 而**不是** `(8,8,8)`；
   `|PCM|=0` 时必须是 `(8,8,8)`。这条专门防 F.3 的那个坑。
3. 跑 `tb_audio_scope`、`tb_audio_visualizer`、`tb_hub75e_audio_display`、`tb_top_audio_visual`、
   `tb_display_mode_control` 与 `python tools/check_scope_external.py`。
4. 把 `tools/render_scope_hue_ramp.py` 的校验改成读新档位，重跑后必须打印 OK；
   再用 `render_scope_hue_smooth_preview.py` 出 33 档条带图。
5. 上板：缓慢渐强，颜色应像色环一样滑过去，**中间不许跳档、不许出现绿/黄**；
   松手回落时颜色应倒着滑回青，不许卡在红。

## F.7 短版提示词（只想粘贴一段时用这个）

> 把 LED 波形的色环从 8 档做成 33 档连续：
> **①** `src/audio_visualizer.v` 里加一个 6 位 `capture_peak64` 饱和峰值累加器，
> 输入取 `quantized_sample`（PCM/64）的绝对值并饱和到 63，复位/清零/累加三处都与现有 `capture_peak`
> 严格对齐，新增端口送进 `audio_scope`；`safe_range` 继续用 `capture_peak`，不要改。
> **②** `src/audio_scope.v` 的 `palette()` 改成纯整数色环：`q=min(p,32)*6`、扇区=`q/64`、`u=q%64`、
> `d=(u*7)>>4`，三个扇区分别是 `(3,31-d,31)`、`(3+d,3,31)`、`(31,3,31-d)`，`q>=192` 钉 `(31,3,3)`。
> 不查表、不用 DSP。**静音判据仍用 `capture_peak==0`**，`peak64==0` 但 `capture_peak!=0` 时要出 `(3,31,31)`。
> **③** 同步 F.5 列出的 10 处（端口/例化 + 4 个 TB + 外部 RGB5 模型 + 渲染脚本 + 两份文档）。
> **④** TB 里加单调性断言（R 不降、G 不升、B 不升、首 `(3,31,31)`、`p>=32` 恒 `(31,3,3)`）
> 和 `|PCM|=1` 的静音边界用例，然后跑那 5 个 testbench 加 `check_scope_external.py`，
> 最后重跑 `tools/render_scope_hue_ramp.py` 要求打印 OK。
