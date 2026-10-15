# 三传感器 top 集成

`src/top.v` 是 Gowin 工程入口。所有音源共用 50MHz 时钟、
48828.125Hz 音频帧使能、饱和混音器以及一套 PCM5102 I²S 输出。

## 操作

- S1：保留 Karplus–Strong 吉他拨弦。
- TTP229 OUT1～OUT7：C4、D4、E4、F4、G4、A4、B4，可同时按。
- OUT8：每次按下切换压力音量/音高模式，不发音。
- FSR402：默认轻压大声、重压小声；音高模式重压降低至一个八度。
  压力只作用于触摸音符，校准参数见 `FSR402.md`。
- APDS-9960：上→下 C4、左→右 D4、下→上 E4、右→左 F4。
- S2：短按释放轮换正弦、钢琴、长笛、尤克里里、鼓；长按切换手势颤音。

## 接线（FPGA 封装球号）

| 信号 | 引脚 |
| --- | --- |
| TTP229 OUT1～8 | K4、L2、J4、G1、G2、L3、L4、J2 |
| TTP229 SCL | F6，固定高；SDO 不使用 |
| APDS-9960 SCL | H4，J3 2×20 排针物理第23脚，开漏，上拉到 3.3V |
| APDS-9960 SDA（数据线） | G4，J3 2×20 排针物理第24脚，开漏，上拉到 3.3V |
| FSR402 AO 分压中点 / ADC 负端 | J8 / K8，负端接 GND |
| PCM5102 BCK / LRCK / DIN | K2 / K1 / L1 |
| S1 / S2 / 50MHz 时钟 | H11 / H10 / E2 |

TTP229 使用八键并行、高有效模式，电平为 3.3V。ADC 正端必须在
0～1V，使用已有说明中的 22kΩ/4.7kΩ 分压。各模块共地。
APDS-9960 采用轮询，无需 INT；初始化期间保持感应区域无遮挡。
手势原 K11/L11 接线迁移到 J3-23/J3-24，二者是同一排上的相邻一对。
请按排针的 1 脚标记确认方向。代码中的 I²C 数据端口是 `sda`，不是
TTP229 的 `SDO`；手势模块数据线接 G4，时钟线接 H4。
球号和物理针脚号按 [Sipeed Dock 官方原理图第一页](https://dl.sipeed.com/fileList/TANG/Primer_25K/02_Schematic/Tang_Primer_25K_Dock_60033_Schematic.pdf) 核对。

## 验证与来源

普通构建已移除空的 RTL GAO 配置，不需要运行 GAO 源生成。直接使用
本机 Gowin 命令行工具可避免 IDE 仍保留旧文件列表的情况：

```powershell
./tools/build.ps1
```

脚本执行综合及布局布线，输出 `impl/pnr/PCM5102_PAM8403.fs`；
仍须检查最新时序报告。它不会向 FPGA 下载。

运行 `./tools/run_sim.ps1` 执行默认六项测试，也可单独运行：

```powershell
./tools/run_sim.ps1 -Tests tb_top_sensors
./tools/run_sim.ps1 -Tests tb_gesture_audio
```

- `tb_top_sensors`：短脉冲拒绝、七键独立按下/释放、多键并发、ADC
  音量、K8 音高切换/长按/再次按下、手势混音、默认增益无削波。
  通过 `i2s_pcm_monitor` 解码实际输出引脚，检查 BCK/LRCK 周期、
  数据变化沿、延迟位、填充零、左右声道一致及非零音频输出。
- `tb_gesture_audio`：测试本次替换后的新音源，覆盖八种音符映射、未就绪/无效方向/原始采样事件过滤、
  重触发、切组不改变已发音的音高、S2 短按音色/长按颤音、最终静音。
- `tb_gesture_nco_pipeline`：正弦查表输出寄存器与原组合查表在音频采样
  时刻的 1024 个 PCM 数值逐个一致，包含相位回绕。
- `tb_karplus`、`tb_guitar_top`、`tb_audio_units`：已有吉他算法、吉他
  I²S 输出与音频基础单元回归。

联合测试的手势事件以注入方式验证，不代表已经完成实物 I²C/FIFO
或模拟输入验证。手势音源单元测试还覆盖备用音符组；当前 top 固定使用
C4～F4 组。测试失败用 `$fatal` 和非零退出码报告；联合测试解码的 PCM
写入 `sim/build/decoded_pcm.csv`。

触摸/压力连接参考本机 `D:/GOWIN/11/pcm5102_pam8403/src/top.v`；
APDS 驱动和手势音源来自 `D:/GOWIN/1/fpga_project_1/src`。
手势音源已改为输出 PCM，共用 top 的音频时钟与串行器。
原 top、约束和工程文件保存在 `integration_backup/`。
新增的手势代码现已替换原来的手势通路：

```text
top.u_gesture (gesture_top)
  ├─ u_i2c (i2c_master) → H4/G4
  ├─ u_ctrl (apds9960_ctrl) → 手势方向和有效事件
  └─ u_audio (gesture_audio) → PCM → top.u_output_mix → top.u_i2s_tx
```

`gesture_top.v` 改为接收主 top 的复位和音频帧使能；按本次选择只接入
手势识别与发声。`gesture_audio.v` 增加 `SHARED_AUDIO_CLOCK=1` 模式，
输出 PCM，保留五种音色、颤音和手势事件处理。音源使用已通过 50MHz
时序检查的动态正弦与钢琴模块。触摸和压力控制维持原连接，S1 仍拨弦，
S2 仍控制手势音色/颤音，主 top 的手势音符组仍为 C4～F4。

旧的 `gesture_voice.v` 已从工程启用列表中关闭，主 top 不再实例化它。
本次替换前的主 top、新手势原文件和工程配置保存在
`integration_backup/new_gesture_before_replace/`。

## 2026-10-12 构建验证

使用 Gowin V1.9.11.03 Education 完成综合、布局布线和位流生成。
50MHz 主时钟约束下，替换新手势模块后的最新时序报告最高频率为 54.409MHz，建立/保持违规
端点均为 0。手势正弦查表输出增加一级 50MHz 寄存器，将查表和钢琴
包络乘法路径分开；音频帧采样值保持一致。

已修正 Gowin 综合警告：APDS 原始通道和调试输出显式留空；颤音乘积
显式选取缩放位；吉他平均值除数和指针运算明确位宽。触摸声部按 4+3
实例化，不生成 K8 声部。最新综合日志无 WARN/ERROR，`EX0101` 仅提示
顶层模块为 `top`。
引脚报告确认 `scl` 位于 H4、`sda` 位于 G4，K11/L11 不再分配给任何
工程端口。重新综合、布局布线和位流生成均完成，构建日志无 WARN/ERROR。
新 `gesture_audio` 单元仿真与新手势子系统的 top 联合仿真均通过，联合
测试验证 5063 帧外部 I²S PCM，触摸、压力、模式切换和手势音频均正常。
