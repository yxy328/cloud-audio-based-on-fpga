# TTP229_SERIAL16 验证记录

日期：2026-10-12。目标：Tang Primer 25K，GW5A-LV25MG121NC1/I0，50 MHz。

当前版本已按用户确认的 **TP1、TP2 黄色跳帽均装上** 改为 **16 键、高有效**。
顶层和核心驱动默认 `ACTIVE_LOW=0`，SCL 空闲低，按下数据为高。
本版本取代此前低有效位流（旧 UserCode 0x00005BDC），请重新选择并下载当前文件。

## 结论及实测边界

自检仿真、Gowin 综合、布局布线、位流生成均通过。
50 MHz 约束下 setup/hold 违规端点均为 0。
本轮未下载硬件，也未验证用户模块的实际跳线、供电或触摸响应。
仿真模型验证串口时序与状态处理；实际传感灵敏度、上电校准和模块布线不由模型保证。

## 自检仿真

执行 `tools/run_sim.ps1`，Icarus Verilog 编译并运行 `sim/tb_ttp229_serial16.sv`。
最终输出 `ALL TESTS PASSED`，覆盖：

- 两种极性分别检查 69 个完整帧；16 个 one-hot 按键位序全部正确，包含最后的 K16。
- 无键、多键、全键；传感器首位锁存整帧，SDO 经异步延迟输出。
- 每帧恰好 16 个有效时钟，完整帧后才提交 `raw_keys`，帧脉冲单拍。
- 逐键 3 帧确认按下/松开，1～2 帧毛刺不改变稳定状态，中断的确认重新计数。
- 一键波动不影响另一键确认；长按不重复产生按下事件，按下/释放事件为单拍。
- FPGA 在帧途中复位，传感器继续供电；启动静置后从第一位重新对齐。
- 高有效与低有效模式均反转时钟方向和数据解释。
- UART 从 TX 引脚按实际位时间接收 8N1，检查十六进制字符、CR/LF、完整冻结快照和 ready 门控。
- 顶层自动复位、按键 LED、运行 LED 第一次 250 ms、第二次 500 ms 的翻转，以及按下/松开串口报告。
- 实际 50 MHz 下，高有效默认配置、10 μs 半周期、16 个时钟、10 ms 帧间隔的计数换算。

多数功能测试将启动等待缩短为 3 ms 以加快仿真；硬件工程保留 1 秒默认值。
SDO 模型分别使用 350 ns / 77 ns 异步传播延迟；模型不模拟触摸电容和供电噪声。

## Gowin 构建与约束

执行 `tools/build.ps1`（内部调用 `gw_sh tools/build.tcl`）。
工具：Gowin V1.9.11.03 Education；最终构建报告时间：2026-10-12 14:17:37。

| 项目 | 结果 |
| --- | --- |
| 时钟约束 | CLK_IN / E2，20.000 ns，50 MHz |
| 时序报告实际 Fmax | 154.529 MHz，仅作为本次静态时序报告结果 |
| setup 违规端点 | 0；最小报告裕量 13.529 ns |
| hold 违规端点 | 0；最小报告裕量 0.275 ns |
| 逻辑资源 | 469 / 23040 |
| 寄存器 | 278 / 23280 |
| SCL / SDO | F6 / F7，LVCMOS33，SDO 内部上拉 |
| 按键灯 / 运行灯 | E8 / D7，READY/DONE 已复用为 GPIO |
| UART TX | C3，经板载调试器输出 |

报告：`impl/pnr/TTP229_SERIAL16_tr_content.html`、`TTP229_SERIAL16.rpt.txt`。
报告确认 SDO 假路径约束为 **Actived**，仅豁免首级 `u_touch/sdo_meta*/D`；
二级同步器和内部逻辑继续按 50 MHz 检查。外部电缆时延不在此静态时序模型内。
布局后的 Verilog 模型确认自动复位计数器的 8 个寄存器初值均为 `INIT=0`。
`device.cfg` 确认 READY/DONE `regular_io=true`。
保存的工程选项在 `impl/TTP229_SERIAL16_process_config.json`，构建脚本也明确设置相关 GPIO 选项。

## 下载产物

位流：`impl/pnr/TTP229_SERIAL16.fs`，UserCode **0x00004EC3**。

SHA256：

```text
B03B30D0D4DEAD9D98106F98280ECD7A78B76554465B7401805A3D5CD80DF255
```

源文件 SHA256：

```text
ttp229_serial16.v
E5539F78EC8F5DF54A76F3BFF83349A475222DAA1A6A7553EF21FFBA18F19DBC
ttp229_serial16_top.v
2E9C1F86B78498FC30336248E07764362588369E61929BC377063AC2B451DE7E
ttp229_uart_report.v
E36B4D27C75E373818A207390E9B360E50744CA28DB86FE13F9BB3175BA1FB89
TTP229_SERIAL16.cst
A76EF88938F831D79172D6E0B338D662CBA973ACFE6C100BEDD33D72CE1BCADE
```

再次编译或改动源码后，应以新报告和新位流校验值为准。
实板成功标准：保持 TP1、TP2 跳帽、四线接好并重新上电后，逐个触摸 K1～K16，
LED3 随按下/松开变化，串口稳定位图分别为 `1 << (键号-1)`，松开返回 `0000`。
