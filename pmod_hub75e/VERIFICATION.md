# S2 模式选择验证记录

## 当前版本：OUT1～OUT8 直读接入 HUB75E

日期：2026-10-07；Gowin V1.9.11.03 Education 最终构建完成时间 **22:19:12（Asia/Shanghai）**。
`mode_16=0` 已改成八根 OUT 输入直读，SCL 保持空闲；`mode_16=1` 仍读 16 键串口。
两种输入都经过同一套 UI 和显示提交逻辑，控制 HUB75E 图案与亮度。
S2 默认按下切换、松开保持，接线由用户手动改变。独立 `ttp229_gpio` 没有 LED 点阵输出。

本轮执行 `tools/run_sim.ps1 -Tests tb_ttp229_gpio_input,tb_top_modes` 和
`tools/run_sim.ps1 -Tests tb_top`，三项自检全部通过：

- 提取的 GPIO 读取模块：OUT1～OUT8 全部位序、两种极性、每键独立 20ms 防抖、
  19 次样本回弹拒绝、停用清零/重新确认、1ms 采样与 20us valid、真实 600ms 冷启动。
- 双输入集成：S2 长按一次、松开保持；GPIO 模式不产生 SCL 时钟，串口模式忽略 OUT；
  双向切换清除旧数据，保留显示设置，K1/K2 切图、K7/K8 与 K15/K16 调亮度，
  更新最终的 `image_active` / `brightness_active`。
- 真实 Gowin ROM 和 RGB 输出：直出 OUT1/OUT7 及随后串口 K2/K16 驱动显示，
  核对 **1,966,144 个 RGB 像素和 30,721 次行锁存**，S1 复位/重新启动通过。

ROM 初始化检查通过；主项目全部源文件路径有效。30 个物理端口管脚互不冲突，
新增八根输入为 K1/L2/J4/G1/G2/L3/L4/J2，LVCMOS33、3.3V、无上下拉、DRIVE=OFF。
历史高有效包装顶层及其源文件依赖已更新，Icarus 编译通过；其旧位流没有重构。

综合、GAO 插入、布局布线和位流生成完成。GAO 当前 **82 位、8192 点**，
增加八根 OUT 电平、直读原始/防抖键值、启动完成和 GPIO valid；分析仪使用 42 个 BSRAM，
加显示 ROM 的 8 个为 **50/56**。

时序分析 4893 条路径、4755 个端点，**setup 违规 0、hold 违规 4**。
最小 setup 裕量 7.035ns，最小 hold 裕量 -1.269ns。违规仍来自 `scan_div` 和
`clkn[3:5]` 的分频反馈，未完全收敛；没有添加时序例外。本轮未下载或采集实板。

当前位流 `impl/pnr/ao_0.fs`，配套 `src/HUB75E.gao`；详细接线见
[使用说明](../MODE_SELECTION.md)。SHA256：

```text
ao_0.fs
C6FDD2F6C2758B0F96E8258E369F1BD8B587FEA582299DD223C7D9CA17AF09E0
HUB75E.gao
4DC797FDBBED29E18A76815CD767075CE14711E9BF9E4A06583974FD27BD6262
```

以下是 **22:19 更新前** 的历史记录；其中“8 键串口”和旧位流哈希不代表当前版本。

## 2026-10-07 21:20：此前 S2 串口位数切换

日期：2026-10-07（Asia/Shanghai）。Gowin V1.9.11.03 Education 构建完成时间 21:20:00。

## 功能验证

Icarus Verilog 的 9 个测试全部通过，ROM 初始化数据检查通过：

- `tb_ttp229`：固定 8/16 键、两种真实时钟/数据极性、同步、复位与串口超时重对齐。
- `tb_ttp229_startup`：默认 600 ms 冷启动、芯片 0.5 s 禁用期间不读帧。
- `tb_ttp229_modes`：默认 20 ms S2 防抖、19 ms 回弹拒绝、长按一次、松开保持、
  完整松开后再按切回；动态 8/16 键全部键位、两种极性、中途切换清零、3 ms 重对齐。
  启动期间两次改模式也不能缩短 600 ms 等待。
- `tb_touch_ui`：完整帧确认、valid 单次采样、长按/松开、图案与亮度边界。
- `tb_top_modes`：真实 S2 切换接入顶层，读 8/16 位，丢弃旧键值及 UI 防抖、
  保留显示设置；K1/K2 切图、K7/K8 与 K15/K16 调亮度。该测试使用轻量 ROM 占位模型。
- `tb_top`：真实 Gowin ROM 和完整 RGB 扫描，自检 1,572,928 个像素、24,577 次行锁存，
  S1 复位与重启。此测试用电平模式固定选择 16 键，动态切换由上一项验证。
- `tb_display_rom`：4096 个 ROM 字、同步读、图案选择和复位。
- `tb_hub75e_scan`：64 列、32 行、每行 67 周期、LAT/消隐与复位。
- `tb_gao_touch_debug`：位域、下降沿快照和 20 μs 事件。

执行入口为 `tools/run_sim.ps1`，新增测试均已列入默认集合，仿真文件不参与综合。

## 构建及限制

`tools/build.tcl` 综合、GAO 插入、布局布线及位流生成完成。
H10 的 S2 为 LVCMOS33 输入，开启下拉；F6/F7 保留串口接线。
GAO 采集 56 位、8192 点，包含模式、S2、串口状态和位计数；使用 29 个 BSRAM，
加两张图的 8 个合计 37/56。直接管脚的 GAO 别名布线问题改用下降沿内部快照解决。

**时序未完全收敛**：分析 3823 条路径、3496 个端点，setup 违规 0，hold 违规 4。
最小 setup 裕量 6.603 ns，最小 hold 裕量 -1.216 ns。违规涉及 `scan_div` 和
`clkn[3:5]` 分频寄存器反馈，属于已有时钟结构；本次实现没有添加 false path
或修改真实时钟约束来隐藏违规。本位流不能作为时序全部验收通过的依据。

本轮没有下载或采集实板，S2 与触摸实际响应尚待硬件验证。S2 不能重写模块
TP2 上电选项，硬件配置和 GPIO 模式的限制见 [使用说明](../MODE_SELECTION.md)。

## 当前产物

- 位流：`impl/pnr/ao_0.fs`
- 配套 GAO：`src/HUB75E.gao`
- 时序：`impl/pnr/HUB75E.tr.html`
- 引脚：`impl/pnr/HUB75E.pin.html`

SHA256：

```text
ao_0.fs
81F6816B426A1C6A6AA6E78198026E513C33DCBE7705014A7843B82B03557B35
HUB75E.gao
EAA61144FF3343F294D3D00792CE85FDA7041B5F3924AB167E78E27753C28919
```
