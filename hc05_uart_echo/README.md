# HC-05 手机串口最小验证

适用仓库当前 Tang Primer 25K / GW5A-LV25MG121NC1/I0，50 MHz 时钟。
独立工程 `HC05_UART_ECHO.gprj`，顶层 `hc05_uart_echo_top`。
默认 **9600 baud、8 数据位、无校验、1 停止位（8N1）、无流控**。
手机发来的每个有效字节原样回传，不定时发提示，也不添加换行。
验证链路：手机 → 蓝牙 → HC-05 TXD → FPGA RX → FPGA TX → HC-05 RXD → 手机。

## 先单独验证模块（无需 FPGA 程序）

1. 给 HC-05 正确供电，暂时断开它与 FPGA 的 TXD/RXD 连线。
2. 将模块自身 **TXD 和 RXD 短接**。
3. 用安卓手机配对 HC-05，然后在支持**经典蓝牙 SPP**的串口终端 App 中连接它。
   普通 BLE 调试 App 不适用。常见出厂配对码是 `1234`，以你的模块说明为准。
4. **关闭 App 本地回显**，发 `abc123`。若接收区收到 `abc123`，模块与手机能双向传输。
5. 拆掉 TXD/RXD 短接线，再接下面的 FPGA 回显工程。

普通 HC-05 不支持 iPhone/iPad 的一般串口 App；需要先用安卓手机验证。
厂家示例说明：[DSD TECH HC-05](https://www.deshide.com/product-details_HC-05.html)。
该型号底板 VCC 为 3.6～6 V、TTL 为 3.3 V、出厂数据波特率为 9600；
其他厂家的固件/底板可能不同，不能把这些值当作所有 HC-05 的固定规格。

## FPGA 接线

断电接线；HC-05 改用 J3 第 15/16 脚（F1/F2），不占用 TTP229 的 F6/F7，TTP229 原接线可保留。
如 J3 插着 SDRAM 扩展板，先拔掉扩展板，保证第 15/16 脚没有其他设备连接。
本工程仍是独立的 HC-05 测试，下载它后不会运行触摸/音频功能；同时运行这些功能需要后续集成。

| HC-05 接点 | Tang Primer 25K Dock 60033 接点 | 方向 |
| --- | --- | --- |
| TXD | **J3 第 16 脚 / F2** | 模块输出 → `hc05_rx` |
| RXD | **J3 第 15 脚 / F1** | `hc05_tx` → 模块输入 |
| GND | **J3 第 12 脚 / GND** | 共地 |
| VCC | 确认有稳压器且明确支持 5 V 的底板，可接 **J3 第 11 脚 / 5 V** | 电源 |
| EN / KEY | 正常数据模式按模块说明保持未使能 AT 模式 | 不连接 FPGA |
| STATE | 暂不接 | 不参与程序 |

**裸 HC-05 核心板不能按带稳压底板的方式接 5 V。** 不清楚模块版本时，先核对供电标识。
UART 信号使用 **3.3 V TTL**，不要把 5 V 信号或 RS-232 信号接 FPGA。
J3 编号为连接器物理脚号，按 1 脚标识数脚，不能按 FPGA 球号数脚。
F1/F2 排针映射和 BANK5 的 3.3 V 电平依据官方原理图第 1 页；仓库现有约束没有使用这两个 GPIO。原理图：
[Sipeed Dock 60033](https://dl.sipeed.com/fileList/TANG/Primer_25K/02_Schematic/Tang_Primer_25K_Dock_60033_Schematic.pdf)。

## 编译与测试

1. 用 Gowin 打开 `HC05_UART_ECHO.gprj`，顶层设置 `hc05_uart_echo_top`。
2. 工程配置启用 **CPU、SSPI、READY、DONE as GPIO**（E2 时钟与 E8/D7 两盏 LED 使用这些复用引脚）。
   在 Gowin 的 `Project → Configuration → Place & Route → Dual-Purpose Pin` 中勾选这四项；JTAG 保持未勾选。
   已保存配置在 `impl/HC05_UART_ECHO_process_config.json`。若修改文件时 IDE 正开着工程，关闭并重新打开工程，让 IDE 重读配置。
   使用 `tools/build.tcl` 也会自动设置这些选项。
3. 编译下载 `impl/pnr/HC05_UART_ECHO.fs`，确认 Programmer 文件路径为本工程。
4. LED4 / DONE 每 0.25 秒翻转一次，说明工程正在运行。
5. 正常上电，不按 HC-05 上的 AT 按钮；安卓系统配对后，还需在终端 App 内连接 HC-05。
6. 关闭 App 本地回显，发 `Hello HC05!`，接收区应出现完全相同的文字。
   可关闭自动追加换行，或接受 CR/LF 也被原样回传。
7. 收到有效字符时，LED3 / READY 亮约 200 ms。LED4 若持续亮，表示出现过停止位错误或队列溢出，重新下载/上电可清除。

**配对成功只证明蓝牙配对；收到 FPGA 回传的数据才证明整个串口链路。**
若 LED3 不亮：检查 TX/RX 交叉接线、共地、App 已连接、数据模式和模块实际 UART 波特率。
若 LED3 亮却没有回传：检查 F1（J3 第 15 脚）→ RXD 这根线和终端接收显示。
若乱码或 LED4 持续亮：核对 8N1 与波特率。顶层 `BAUD` 可改成模块实际值后重编译。
手机无线 SPP 连接本身不靠 App 的“9600”选项设定模块 UART 速率。
AT 模式速率与正常数据速率可能不同；本工程不进行 AT 配置。

## 仿真

运行 `powershell -ExecutionPolicy Bypass -File hc05_uart_echo/tools/run_sim.ps1`。
自检覆盖全部 256 字节、连续帧、±2% 发送速率偏差、假起始位、坏停止位、持续低电平及恢复、复位。
32 字节缓冲用于短消息测试；没有 RTS/CTS，不保证无限连续数据流无损。
仿真与编译不能替代实际手机/模块测试。
