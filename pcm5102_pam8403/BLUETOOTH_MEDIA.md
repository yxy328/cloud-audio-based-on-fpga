# 蓝牙下载音频、曲谱与演奏记录

2026-10-15，继续使用 `PCM5102_PAM8403.gprj`、原 HC-05/PCM5102/PAM8403 接线和 9600/8N1。
所有命令大写 ASCII，以 LF、CR 或 CRLF 结束，一行最多 64 个字符。**每发一行，收到对应回复再发下一行。**

## 先试播放这段音频

原文件 `所长sama - 结算画面.flac` 为 48kHz 立体声、约 101.81 秒。
现有工程没有压缩音频解码器，因此先取开头 4 秒，在电脑转换为 **8kHz、单声道、有符号 8 位 PCM**。
这用于验证下载和脱机播放通路，音质低于原文件。FPGA 无需实时解码 MP3/FLAC。

已生成：

- `audio_clips/settlement_4s.wav`：电脑试听，内容与 FPGA 下载采样一致。
- `audio_clips/settlement_4s.txt`：完整下载命令，末尾包含 `PCM_PLAY`。
- `audio_clips/settlement_4s.s8` / `.hex`：32000 个实际采样 / 仿真输入。
- `audio_clips/settlement_4s.json`：源文件、格式、sum16、SHA256 和传输量。

重新构建本工程后，将**本次新生成**的 `impl/pnr/PCM5102_PAM8403.fs` 用 SRAM Program 下载。
旧的手机改键版位流不支持这些新命令。Gowin IDE 若已打开旧工程，重新打开 `.gprj` 以刷新文件清单。

电脑与 HC-05 配对后，找到其 **SPP 输出 COM 端口**，执行（`COMx` 替换为实际端口）：

```powershell
& ./pcm5102_pam8403/tools/send_audio_clip.ps1 -Port COMx
```

脚本逐行等待 `OK`，仅对超时的数据块重试。手机调试器也可发送同一协议，但批量发送必须支持逐行等待回复；
不要把两千行一次性灌入接收窗口。当前 2003 行命令约 97KB，9600 下仅发送时间约 101 秒，加回复和软件延迟约两分钟或更久。

完成后自动播放一次，断开蓝牙仍可播放：**S1 播放/停止 PCM，S2 从头重播**。
也可发 `PCM_PLAY`、`PCM_STOP`，或用 `STOP` 停止全部背景播放器。
没有有效 PCM 时，S1/S2 依次选择已下载曲谱、原内置《小星星》。`PLAY` 明确选择音符曲谱，`PCM_PLAY` 明确选择采样音频。
触摸弹奏仍可与背景音频混音；压力控制继续作用于触摸音。

RAM 中每段最多 **32768 采样 = 4.096 秒**，双缓冲共 64KiB，下载中断或校验失败保留旧片段。
当前整首约 101.8 秒不在此 RAM 试听版容量内。整首高音质播放需接入 SD 卡或外部存储，并另行实现读取/解码；
片内 RAM 版本断电后内容丢失，不能作为掉电保存方案。

## PCM 文本协议

| 命令 | 含义 |
| --- | --- |
| `PCM_BEGIN,32000,29699` | 开始暂存 32000 采样，全部传输字节的无符号和低 16 位为 29699 |
| `PCM_DATA,0,000102030405060708090A0B0C0D0E0F` | 从采样地址 0 写入 16 字节 |
| `PCM_END` | 顺序检查全部块与 sum16，成功才切换有效银行 |
| `PCM_PLAY` | 从头播放有效音频一次 |
| `PCM_STOP` | 停止采样音频 |

地址为十进制，必须按 16 对齐。HEX 每两字符表示一个原始二进制补码采样字节，完整块固定 16 字节，末块可不足 16。
`00` 是零，`7F` 是 +127，`80` 是 -128。整块重复发送覆盖原位置，不重复累计校验和。
上述操作成功均返回 `OK`；范围错误返回 `ERR,RANGE`、缺块 `ERR,MISSING`、校验不符 `ERR,CHECKSUM`、未开始下载/无有效内容 `ERR,STATE`。
下载时停止背景音乐、松开音符键并结束录制，否则返回 `ERR,BUSY`。

转换其他片段：

```powershell
python ./pcm5102_pam8403/tools/prepare_audio_clip.py 'E:/Users/Downloads/所长sama - 结算画面.flac' --start 30 --seconds 4 --output ./pcm5102_pam8403/audio_clips/settlement_30s
```

需要 `numpy`、`soundfile`。工具支持工程内依赖目录 `sim/build/audio_deps`，缺依赖时会显示安装命令。

## 音符曲谱下载

```text
SONG_BEGIN,7
SONG_NOTE,0,60,500
SONG_NOTE,1,60,500
SONG_NOTE,2,67,500
SONG_NOTE,3,67,500
SONG_NOTE,4,69,500
SONG_NOTE,5,69,500
SONG_NOTE,6,67,1000
SONG_END
PLAY
```

逐行等 `OK`。支持 1～128 条记录；索引从 0 开始，MIDI 为 60～72，每条 1～60000ms。
按索引覆盖，允许乱序及重发；`SONG_END` 检查记录完整、时长与当前键位覆盖，成功才提交。
缺记录返回 `ERR,MISSING`，所需音符未映射到任一键返回 `ERR,MAP`。
修改映射后 `PLAY` 会重新检查覆盖。中断下载不会覆盖原有效曲谱，重新 `SONG_BEGIN` 可重新开始。
同音连奏之间留 1ms 释放，以重新触发包络；播放时间以 FPGA 50MHz 时钟换算毫秒。

## 演奏记录

`REC_START` 返回 `OK` 后，先输出当前 `MAP,...`，再输出时间为 0 的初始状态：

```text
MAP,60,62,64,65,67,69,71
EVT,0,00,0,39321,65535
EVT,120,01,0,39321,65535
EVT,650,00,0,39321,65535
```

字段依次为：相对开始的毫秒时间戳、七键十六进制位图、压力模式、实际音量系数、实际音高比例。
位图 `01` 为键 1，`03` 为键 1+2，`40` 为键 7。时间取去抖后状态变化时刻，包含现有防抖延迟。
按键变化按 FPGA 时钟检测；压力每 20ms 检查，仅变化时记录，长按无变化不会重复上传。
系数为 16 位整数，65535 表示该路径全比例；字段记录控制值，不是麦克风或 PCM 录音。

`REC_STOP` 先返回 `OK`，然后排空缓存、发送停止时的最终 `EVT`，最后输出 `REC_END,0`。
等待此结束标记后再导出日志或开始下一次录制。录制及尾部排空期间拒绝 `MAP`/`MAP_RESET`。
64 条 FIFO 缓冲 UART 来不及发送的变化；溢出时发送 `ERR,REC_OVERFLOW,<累计丢失条数>`，
`REC_END,<累计丢失条数>` 同时给出完整性结果。即使 FIFO 满，最终状态仍由独立槽保存。
9600bps 的持续吞吐有限，FIFO 只能缓冲突发；出现溢出不能认为记录完整。
日志可保存/复制供后续重放，手机端声音重建尚未实现。

## HUB75E 音游指引的当前范围

采用 64×64、七轨、下落音符、判定线的方向。已新增并独立验证 `rhythm_guide.v`，详见 `RHYTHM_GUIDE.md`。
当前音频试播顶层仍未接入屏幕扫描与前瞻谱面调度，不能认为下载音频就会自动产生节奏谱。
音频采样和音符谱面是两份数据；后续需要额外提供/制作带时间戳的谱面并同步启动。

## 验证命令

```powershell
& ./pcm5102_pam8403/tools/run_sim.ps1 -Tests tb_pcm_clip_player,tb_hc05_download,tb_downloadable_song,tb_performance_logger,tb_top_pcm
& ./pcm5102_pam8403/tools/run_sim.ps1 -Tests tb_pcm_clip_payload
& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' ./pcm5102_pam8403/tools/build.tcl
```

实际构建、时序与板上范围以 `VERIFICATION.md` 本次记录为准；仿真通过不能替代 DAC/功放听音验收。
