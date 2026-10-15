# HUB75E 七轨音游指引（待接入主顶层）

本目录 `src/rhythm_guide.v` 是可独立仿真的像素渲染模块，尚未加入
`PCM5102_PAM8403.gprj` 或音频顶层，现有音频试播接线保持不变。
现有 `../pmod_hub75e` 屏工程使用 **64×64、1/32 扫描、RGB 各 5 位 PWM**。

默认界面从左到右对应触摸键 1～7：七条竖轨、从上往下的青色音符、
`y=54` 判定线、底部按键状态。当前应按键在判定线显示橙色；
已按键显示绿色，按中当前目标时显示白色。仅提供显示，暂不计分或判定命中。

`guide_keys[6:0]` 表示当前到时目标，`touch_keys[6:0]` 接现有去抖后按键。
它们不会自动生成下落音符，因为当前目标不能提供未来音符的时间。
要显示真正提前下落的提示，曲谱读取器需提前送出一拍 `note_spawn`，
同时给出 `spawn_keys[6:0]` 和距判定时刻的 `spawn_delay_ms[15:0]`。
通常提前 1500 ms 送出；更短时间会从轨道中途出现，更长时间先等待。
多键掩码表示和弦，相邻相同音符按独立事件显示。

`ms_tick` 是系统时钟域内每毫秒一拍的使能信号，不能用作新时钟。
默认同时容纳 8 个在途事件；发送方须观察 `note_ready`。
无空位仍发送时，`note_overflow` 保持为 1，直到停止或复位。
`playing=0` 会清空队列；此时仍显示触摸键反馈。

接入屏扫描时保留原 `hub75e_if`，令 `x=ram_addr[5:0]`，
上半屏 `y={1'b0,ram_addr[10:6]}`，下半屏 `y={1'b1,ram_addr[10:6]}`。
可用两个渲染实例接收相同事件，再把 RGB 输出按原同步 ROM 的读时序打一拍。
三路 `red/green/blue[4:0]` 分别与原 PWM 门限比较，连接到 R/G/B 引脚。
原 ROM 内存字段顺序不能直接当成普通 RGB 顺序使用：旧代码实际把 G 放在低 5 位、
B 放在中间 5 位。

合并引脚时，屏主信号与 PCM 当前引脚不冲突。需要删除旧屏工程的
`dbg0=K2`、`dbg1=L1`，因为它们与 I2S BCK、DIN 重合；
触摸键 1 必须采用 PCM 当前 `K4`，旧屏工程的 `K1` 已用于 I2S LRCK。
旧 `dbg2=K4` 也应删除，它会与迁移后的触摸键 1 重合。
屏主信号为 R1/G1/B1=G10/G11/D10，R2/G2/B2=B10/B11/C10，
ABCDE=A10/A11/E10/E11/C11，CK/LAT/OE=L11/K11/K5。

已通过 `sim/tb_rhythm_guide.v`：1500 ms 下落、半途加入、提前等待、
和弦、重复音符、按键反馈、队列满溢出及停止清空。
尚未做合并工程综合、布线或实板显示验证。

```powershell
& C:/iverilog/bin/iverilog.exe -g2012 -s tb_rhythm_guide -o sim/rhythm_guide_sim.vvp src/rhythm_guide.v sim/tb_rhythm_guide.v
& C:/iverilog/bin/vvp.exe sim/rhythm_guide_sim.vvp
```
