# 板上 I2S 采集

本工程引用主工程的五个 RTL 源文件和原来的 CST/SDC；音频逻辑、按键极性、
引脚和分频均保持一致。另加 GAO 观测 `key_s1 / i2s_bck / i2s_lrck / i2s_din`。
调试构建关闭输出寄存器放入 IOB，避免 GAO 无法布线到输出节点。
片内观测不能代替 DAC 端的外部电压和波形测量。

## 本次实测（2026-10-08）

已经通过 Programmer 将 `impl/pnr/ao_0.fs` 下载到 FPGA SRAM。
使用 FT2CH USB 下载器，Location 385，器件扫描为 GW5A。
原主工程 `../../impl/pnr/PCM5102_PAM8403.fs` 文件没有改写，Flash 没有烧写。

50MHz 时钟采样，共 16,384 个有效点、跨度 327.66us。原始导出和独立解码结果：

- `captures/key_low.csv`
- `captures/key_low_analysis.json`

| 检查 | 板上捕获结果 |
| --- | --- |
| H11 / key_s1 | 整段为 0；还未验证实际按下后的高电平 |
| K2 / BCK | 连续时钟；1,023 个完整周期均为 320ns，即 3.125MHz |
| K1 / LRCK | 连续时钟；30 个完整周期均为 20,480ns，即 48.828125kHz |
| L1 / DIN | H11 为 0 时整段为 0；31 个完整声道时隙 PCM 均为 0 |
| I2S 格式 | 每时隙 32 个 BCK；一位延迟、16bit 数据、补零检查通过 |
| 左右一致 | 15 个完整立体声对全部一致 |

以上确认时钟和静音路径正常。按住 S1 后的 DIN 数据流仍待采集，
未对 DAC 模拟输出、功放或喇叭声音作出通过结论。

随后已用 `../audio_autoplay` 的独立工程绕过按键实测正弦 PCM 和 I2S 发送，检查通过。
详细结果和波形见该目录 README；这次检查没有验证原版实际按键使能。
检查结束后已恢复本目录的按键版 SRAM 位流，日志为 `restore_key_sram.log`。

## 重复采集

1. 在此目录执行 `gw_sh build.tcl`，或在 Gowin EDA 打开 `AUDIO_GAO.gprj` 构建。
   GUI 需保留 CPU/SSPI 作为 GPIO、JTAG 下载接口，以及三个 IOB 寄存器放置选项关闭。
2. 用 Gowin Programmer 下载这里的 **`impl/pnr/ao_0.fs`** 到 SRAM。
3. 在 Gowin Analyzer Oscilloscope 打开 **`AUDIO_GAO.gao`**，选择实际的 USB 下载器。
4. Start 后按下 S1 触发；若 S1 已保持按下，使用 Force Trigger。
5. Export 选择 CSV，**Clock period = 20，单位 = ns**。导出的文件名会带 `_core0` 后缀。
6. 复制 CSV 到 `captures/`，使用新的文件名保留不同状态。

```powershell
python analyze_capture.py captures/key_low.csv --output captures/key_low_analysis.json
```

解码器仅依赖捕获的 BCK 上升沿、LRCK 与 DIN，检查周期、更新边沿、
I2S 延迟位、补零与左右一致性。初始 X 行不作为有效采样。
时间按板载 50MHz 标称值计算，GAO 本身不是独立测频仪。
