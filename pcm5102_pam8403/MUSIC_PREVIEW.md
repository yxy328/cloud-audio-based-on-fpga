# 《小星星》已同步到原工程

> 历史演示记录：以下 S1/S2 自动播放和位流编号属于早期版本。当前 `PLAY`/S1 是无声指引，App v1.3 使用 `AUDITION` 显式试听已下载曲谱，见 [当前 App 说明](android_app/README.md) 与 [验证记录](VERIFICATION.md)。本文 `sim/build/` 产物需在本地生成。

当前 `PCM5102_PAM8403.gprj` 的生产文件列表包含 `src/twinkle_sequencer.v`，
`src/top.v` 实际连接这个曲谱控制器和现有四声部 DDS/ADSR/混音/I2S。
板端和电脑试听共用同一个曲谱控制器；本次不再用仿真平台独立维护旋律表。

**下载新的 `impl/pnr/PCM5102_PAM8403.fs` 后，按一下 S1 开始，再按一下停止；S2 从头重播。无需按住。**
播放完整 42 音、48 拍的《小星星》，约 19.59 秒后自动静音。本次位流 UserCode=`0x0000655D`，具体记录见 [验证记录](VERIFICATION.md)。

[完整旋律与三声部伴奏试听](sim/build/music_preview.wav)

```text
C C G G A A G— | F F E E D D C—
G G F F E E D— | G G F F E E D—
C C G G A A G— | F F E E D D C—
```

每句最后一个音占两拍。节拍约 400ms；普通音起音约 300ms，释放间隔约 100ms。
四路包络为 2ms / 80ms / 60% / 100ms，一路高音旋律与三路低音伴奏并发合成。
相较先前 6 秒的开头试听，本次扩展为完整曲谱，并修正句尾节拍。

## 试听与硬件的对应范围

`sim/tb_music_preview.v` 直接实例化生产 `twinkle_sequencer` 和 `poly_synth`。
它逐项断言音乐计时、音量和 ADSR 参数与生产 `top.v` 的默认值相同；参数不一致会报错，不能继续生成参考音。
唯一用于加速渲染的差异是采样使能每 20 个主时钟出现一次，导出采样编号仍按生产 Fs=48,828.125Hz 解释。
每帧留有足够时钟完成 16 时钟的包络斜率计算。

完整曲谱生成 42 个旋律起音事件；渲染检查未知值、限幅、四声部音量上界和最终严格数字零。
外部 I2S 另由 `tb_top.v` 使用生产 50MHz/1024 主时钟每帧及默认参数验证，
`tb_top_song.v` 使用缩短的音乐和包络时间检查完整 42 事件经过顶层与 I2S。
网表使用和 RTL 相同的短场景逐样本比对；完整曲谱的生产节拍由控制器计数及渲染验证。
这些检查的范围和具体结果见 [验证记录](VERIFICATION.md)。

WAV 是 HDL 仿真参考，不是开发板模拟录音。导出时作 48,828.125Hz→48kHz 转换和整段固定增益归一化。
现场功放音量、DAC 模拟滤波，以及按键开始时振荡器所处相位会影响音量和波形，
但生产控制器的音符顺序、节拍、伴奏和 ADSR 参数已与参考同步。

```powershell
./tools/render_music_preview.ps1
# 可指定 Python 路径。
./tools/render_music_preview.ps1 -Python 'E:/300_IDE_Compiler/Python313/python.exe'
```

生成文件在 `sim/build/music_preview_pcm.csv`、`music_preview_render.log` 和 `music_preview.wav`。
脚本只生成电脑参考音；板端功能已由生产源码和重新编译的位流实现。
`polyphony_reference.wav` 是此前固定和弦版的历史参考，当前不再用它对照《小星星》。

## 实时合成与演奏入口

运行时四声部音频由 FPGA 逐样本生成；曲谱只存音高事件，不存歌曲 PCM，WAV 不进入 FPGA ROM。
当前预设曲谱是本次明确要求的硬件试听入口，不作为赛题的现场实时演奏入口。
接入实际演奏键盘时需替换曲谱控制层，继续复用四组门控/音高和同一个合成核心。
