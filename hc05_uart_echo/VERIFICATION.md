# 验证记录

日期：2026-10-13。

- Icarus Verilog 自检通过，458 个字节原样回显。
- 覆盖全部 256 种字节、背靠背发送、±2% 波特率偏差、短低脉冲、错误停止位、break 及恢复、复位清除错误。
- 仿真采用 100 时钟/位以缩短运行时间；板上默认 50 MHz / 9600，取整后 5208 时钟/位。
- Gowin V1.9.11.03 Education 完成综合、布局布线与位流生成。
- 换脚后重新完成综合、布局布线和位流生成；时钟约束 50 MHz，报告 Actual Fmax 为 166.311 MHz，Setup/Hold TNS 均为 0。
- 占用 489/23040 逻辑资源、449/23280 寄存器。
- PnR 引脚报告确认 CLK_IN=E2、hc05_rx=F2、hc05_tx=F1、led_rx=E8、led_run=D7；F1/F2 均为 BANK5 的 LVCMOS33。
- 官方 Dock 原理图第 1 页核对 F1=J3 第 15 脚、F2=J3 第 16 脚；现有其他工程约束未使用 F1/F2，保留 TTP229 的 F6/F7 接线。
- 位流：`impl/pnr/HC05_UART_ECHO.fs`。
- 本次没有下载到硬件，没有验证实际 HC-05 版本、供电、UART 波特率或手机连接。

复现：`powershell -ExecutionPolicy Bypass -File hc05_uart_echo/tools/run_sim.ps1`；
构建：`powershell -ExecutionPolicy Bypass -File hc05_uart_echo/tools/build.ps1`。
硬件判定步骤见 `README.md`。

## 2026-10-14 GUI 配置修复

GUI 保存的流程配置中 CPU、READY、DONE 为 false，导致 E2/E8/D7 被保留为专用引脚并报 PR2017/PR2028。
已将 CPU、SSPI、READY、DONE GPIO 复用全部启用，并保存顶层名。
配置文件 `impl/HC05_UART_ECHO_process_config.json` 纳入保存范围；CLI 再次完整编译通过并生成位流。
正在打开的 GUI 工程需重新打开或手动勾选相同选项，避免使用内存中的旧配置。
