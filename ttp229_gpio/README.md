# TTP229：S2 选择 8 键 GPIO / 16 键串口

打开 `TTP229_GPIO.gprj`，顶层为 `ttp229_gpio_top`，Tang Primer 25K
`GW5A-LV25MG121NC1/I0`。保留独立触摸调试，不包含 HUB75E 显示逻辑。

**本工程没有 LED 点阵显示。** 带显示的 OUT1～OUT8 直读已接入
`../pmod_hub75e/HUB75E.gprj` 的 `mode_16=0`；16 键串口为 `mode_16=1`。
要用触摸控制 HUB75E 屏幕，请使用该显示工程，接线表见 [使用说明](../MODE_SELECTION.md)。

**上电默认 8 键**，板载 **S2 / H10** 每次稳定按下 20 ms 切换一次：
`mode_16=0` 用 OUT1～OUT8；`mode_16=1` 用 SCL/SDO 读 16 键。
长按只切换一次，松开后保持模式；稳定松开 20 ms 后才接受下一次按下。

S2 只切换 FPGA 的读取方式，不能改写模块上电锁存的 TP2 选项。
GPIO 直读要求模块为 8 键；16 键串口要求模块配置为 16 键。
更改模块焊盘后需断电重新上电；只按 S2 不能自动实现这两种硬件配置互换。
详细行为与屏幕工程的差异见 [S2 使用说明](../MODE_SELECTION.md)。

## 接线

模块 VCC 接 **3.3V**、GND 共地，保留八根 OUT 输入；新增 SCL/SDO：
**先拆除旧接法中模块 SCL 到 3.3V 的固定连接**，再把 SCL 接 FPGA F6。
F6 是 FPGA 输出，SDO 接 F7 是 FPGA 输入，开启上拉。
S2 使用板载按键，无需另外接线。

以下物理编号是 FPGA 底板 J3 的 40Pin 排针编号。

| 模块 | J3 物理脚号 | FPGA 球号 | 顶层端口 |
| --- | ---: | --- | --- |
| OUT1 | 2 | K1 | touch_out[0] |
| OUT2 | 4 | L2 | touch_out[1] |
| OUT3 | 6 | J4 | touch_out[2] |
| OUT4 | 7 | G1 | touch_out[3] |
| OUT5 | 8 | G2 | touch_out[4] |
| OUT6 | 9 | L3 | touch_out[5] |
| OUT7 | 10 | L4 | touch_out[6] |
| OUT8 | 21 | J2 | touch_out[7] |
| SCL | 按 F6 对应引出脚连接 | F6 | touch_scl（输出） |
| SDO | 按 F7 对应引出脚连接 | F7 | touch_sdo（输入） |

OUT1～OUT8 都是输入、3.3V、DRIVE=OFF、PULL_MODE=NONE。
芯片在 16 键模式下把这些直出引脚复用为触摸输入，因此不施加 FPGA 内部下拉。
原 dbg0/dbg1/dbg2 和 PMOD 引脚不使用，只有原 F6/F7 为新增串口所复用。

## 模块与状态机

模块默认直出高有效（`ACTIVE_LOW=0`），串口低有效（`SERIAL_ACTIVE_LOW=1`）。
模块 TP2 开路为 8 键，配置为低为 16 键；TP0/TP1 默认，TP3/TP4 都配置为低可多键。
更改选项后重新给模块上电，校准期间不要触摸。

自动复位后等待 **600 ms**，两个模式都每键独立连续 20 个 1ms 样本确认按下/松开。
`keys_raw` 和 `keys_stable` 统一为 16 位，8 键时高八位清零。
S2 用两级同步和四状态 `case` 防抖；切换清除旧键值及计数。
GPIO 模式 SCL 保持空闲；串口启用先静置 3 ms，读帧完成后再静置 3 ms，
避免串口位序错位。`S2_TOGGLE_MODE=0` 可改成电平选择，默认是按下切换。

工程共享 `../pmod_hub75e/src/ttp229_mode_select.v` 和 `ttp229_ctrl.v`，
这两个相对路径已经加入 `.gprj` 和仿真脚本。

## GAO

用当前 `impl/pnr/ao_0.fs` 与配套 `src/TTP229_GPIO.gao`，
GAO 时钟 195.3125kHz，深度 **8192**，窗口约 **41.943ms**，触发前约 **31.457ms**。
快照在主时钟下降沿更新，启动等待期间采样时钟也继续运行。

| 信号 | 含义 |
| --- | --- |
| mode_16 / S2 | 保持的模式 / 按键电平 |
| touch_out[7:0] | 八根 OUT 电平 |
| keys_raw[15:0] / keys_stable[15:0] | 当前来源键值 / 防抖键值 |
| touch_scl / touch_sdo / serial_valid | 串口波形及完整帧有效 |
| serial_state[2:0] / serial_bit_cnt[3:0] | 串口状态与当前键位 |
| mode_state[1:0] | S2 稳定低、确认高、稳定高、确认低 |
| power_resetn / ready / heartbeat | 自动复位、600ms 等待结束、1Hz 心跳 |
| key_event | 模式改变或稳定键值改变时的 1ms 触发事件 |

8 键的 K1/K8 对应 `0001` / `0080`，16 键的 K9/K16 对应 `0100` / `8000`。
按下/松开应看到 `keys_stable: 0000 → 对应位图 → 0000`。

## 构建与验证

```powershell
.\tools\run_sim.ps1
gw_sh tools/build.tcl
```

脚本运行 GPIO 基础自检和 S2 模式集成自检，构建脚本只生成位流。
本轮仿真与 Gowin 构建通过，setup/hold 违规均为 0；没有下载或进行实板采集。
当前产物、时序及 SHA256 见 [VERIFICATION.md](VERIFICATION.md)。

来源：[Sipeed Dock 原理图](https://dl.sipeed.com/fileList/TANG/Primer_25K/02_Schematic/Tang_Primer_25K_Dock_60033_Schematic.pdf)、
[TonTek TTP229-BSF 手册](https://www.tontek.com.tw/uploads/product/97/TTP229-BSF_V1.1_EN.pdf)。
