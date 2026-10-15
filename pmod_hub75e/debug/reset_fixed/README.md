# 修正复位后的主版本快照

下载 `LOW_RESET_FIXED.fs`，GAO 加载同目录 `Touch_RESET_FIXED.gao`，不要混用旧 LOW/HIGH 配置。
这是主工程 `impl/pnr/ao_0.fs` 与 `src/HUB75E.gao` 的完整副本，校验值 0x2187。

已实际确认：下载 Finished，强制采集完成，SCL 和 touch_valid 正常出现。
当前捕获的 SDO 仍全程高、键值 0000，**按键 1 尚未验证成功**。
`wave_start.png` 和 `wave_end.png` 是同一次真实采集的前后视图。

本版本修正 S1 按下为高的复位极性及 H11 下拉；GAO 分频自由运行，显示另用 scan_div 保持复位相位。
七套仿真通过；布局布线报告 setup 0、hold 2，尚未完成全部时序签核。

直接连接开发板 3.3V IO 时，模块 VCC 使用 3.3V并共地。若此前仍接5V，应断电后改接3.3V。
上电时松开所有触摸键，等待约1秒；采集开始后轻触1键约半秒即可松开，无需用力或持续按压。
[原厂BSF资料第5页](https://www.tontek.com.tw/uploads/product/97/TTP229-BSF_V1.1_EN.pdf)规定 SCL 高电平下限为0.8×VDD；
5V供电时要求4V，3.3V输出不满足保证值。此处说明电平条件，不能据此断言模块损坏。
