# 2026-10-18：综合告警修正与验证

用户粘贴的 31 条 WARN 分为两类：7 条 EX3791、24 条 NL0002。

## 原因与修改

| 告警 | 原因 | 修改 |
| --- | --- | --- |
| EX3791，17 → 16 位 | ADSR 的误差累加、包络加减带有进位，写回 16 位上下文时隐式截断 | `touch_tdm_synth.v` 保留 17 位中间结果，显式选择 `[15:0]` |
| EX3791，51 → 24/16 位 | 共享乘法器的定点乘积移位后，写入混音累加器或仿真监视值 | 先对完整有符号乘积作算术右移，再明确选择混音/监视器需要的位数 |
| EX3791，21 → 18 位 | 音效湿声乘积右移后的宽度仍为 21 位 | `audio_effects.v` 明确取出 Q4 移位结果，并作有符号扩展后混音 |
| EX3791，14/32 → 13 位 | 总音量平滑步进使用整数参数，运算宽度大于增益寄存器 | `audio_master_volume.v` 使用明确位宽的加减中间值和寄存器取位；原有距离判断负责防止越过目标 |
| NL0002，共 24 条 | 默认 `ENABLE_DEMO_SCORE=0`，演示音频链仍实例化，综合器逐层删除无效硬件 | `top.v` 用 `generate` 按参数生成演示控制器与合成器；关闭时明确连接静音/空闲常量 |

`hc05_keymap.v` 新增 `ENABLE_DOWNLOADED_INCREMENT`，默认 1，保留独立使用该模块时的原接口行为。
顶层将它设为 `ENABLE_DEMO_SCORE`：生产模式的显式 `AUDITION` 使用 `guide_keys` 驱动现有触摸声部，
不需要旧演示链的 `downloaded_increment` 查表。启用演示曲时仍生成该查表。

完整旧日志还包含两条未粘贴的提示，本次同时修正：

- `hub75e_status.v`：十六进制字体计算中的无尺寸整数常量改为明确的 6 位运算。
- `top.v`：触摸合成器未使用的 `clipped` 输出显式接空。

演示模块的层次路径现在为 `demo_score.u_control` / `demo_score.u_synth`。
相应更新五份历史测试的引用；生产模式测试直接核对顶层的演示释音参数。
新增 `tb_top_score_config` 检查两个参数分支；I2S 监视器支持可选的 `CAPTURE_FILE`，
便于两套顶层分别保存外部引脚解码数据，默认调用仍使用原来的 `+pcm_csv`。

## 验证范围

验证期间共享工作区另有音频录制功能改动。为避免覆盖其他任务的构建文件，使用
`sim/build/warn_audit/` 下的独立工程副本：以本次开始时的已提交 FPGA 工程为基础，叠加上述告警修正。
主工作区的修正已保留；副本不包含同时进行的录制功能，也未替换主工程 `impl/` 中的产物。

### Gowin 全流程

- Gowin V1.9.11.03 Education，GW5A-LV25MG121NC1/I0，顶层 `top` 默认参数。
- 上海时间 2026-10-18 20:21:45 完成综合、布局布线、静态时序、仿真网表及位流生成。
- 完整构建日志：**0 WARN、0 ERROR**。
- 50 MHz：Setup/Hold 违反端点均为 **0**；Fmax **50.584 MHz**，最差 Setup Slack **+0.231 ns**。
- 资源：Logic **22305/23040**，Register **9544/23280**，CLS **11422/11520**，BSRAM **52/56**，DSP **20.5/28**。
- 独立位流 SHA256：`C7F1C7EABB896829FA0740DA8A89DAC230BC54E06C4421EE72256489C0334161`。

日志及产物相对于本目录的位置：

- `sim/build/warn_audit/pcm5102_pam8403/impl/build_warning_cleanup.log`
- `sim/build/warn_audit/pcm5102_pam8403/impl/pnr/PCM5102_PAM8403_tr_content.html`
- `sim/build/warn_audit/pcm5102_pam8403/impl/pnr/PCM5102_PAM8403.fs`
- `sim/build/warn_audit/pcm5102_pam8403/impl/warning_cleanup_hashes.json`

### 数值与功能

修正前后的三个音频模块并行接受相同输入，逐周期比较：

- 触摸合成：**1024 帧**，`VOLUME_SHIFT=0/4/8`，PCM、活动/削波标志、全部写回的相位与 ADSR 上下文一致。
- 覆盖 65535 样本长包络、短包络、变调、随机低七键频率及门控；其中观测到 **3856 次**第 17 位进位相关场景。
- 音效：**6 万多份样本**，覆盖正负满幅、干声、回声、合唱、湿度限幅和模式变化，输出与有效脉冲一致。
- 总音量：平滑步长 **1/63/4096/16384**，随机目标增益及正负 PCM，增益和输出一致。
- 比较日志：`sim/build/warn_baseline/width_equivalence.log`。

完成并通过的 **9 组 RTL 测试**：

1. `tb_audio_effects`：独立环形缓冲模型验证 59005 样本，含符号和饱和。
2. `tb_audio_master_volume`：静音、原增益、平滑、边界、反向变化和复位。
3. `tb_touch_tdm_synth`：高九键频谱、独立 ADSR、快照、释音、变调和帧期限。
4. `tb_hub75e_status`：外部 RGB 重建、字体、8/16 键、音量/ADC 条形显示。
5. `tb_hc05_download`：真实 UART 下载、曲谱校验、默认查表接口与录制日志行为。
6. `tb_hc05_control_races`：真实 UART 请求/完成握手和映射锁定。
7. `tb_top_live`：外部 I2S 验证默认指引静音、四/七声部、独立释音、STOP 保留手按音；3821 对立体声样本。
8. `tb_top_score_config`：默认 S1 静音、可选演示曲发声、生产试听不依赖旧查表、K1/K16 及释音。
9. `tb_top_idle`：生产默认参数，S1/S2 无触摸时静音；136 对立体声样本。

`tb_top_fsr`、`tb_top_fsr_modes`、`tb_top_song`、`tb_top_touch`、`tb_top_touch_response`
另外完成编译检查，层次引用全部绑定成功；这五项没有计入本轮完整运行的通过数量。
未重新运行全部历史回归，未烧录实板。

宿主环境运行 Icarus 完成上述验证；最初受限环境中的 Icarus 异常退出不计为测试通过。
仿真日志位于独立工程副本中的 `sim_units_warning_cleanup_host.log`、
`sim_top_warning_cleanup_host.log` 和 `sim_score_config_warning_cleanup.log`。

快速复现新增分支回归：在工程目录执行
`./tools/run_sim.ps1 -Tests tb_top_score_config`。
重新构建当前共享工程时，需对合并后的其他功能一并检查时序。

## 后续 EX3937：Gowin 窗口使用旧工程文件清单

`top.v` 实例化 `audio_record_stream`，源码文件和磁盘上的 `.gprj` 均已包含该模块，
但报错时实际生成的 `impl/gwsynthesis/PCM5102_PAM8403.prj` 未包含它。
Gowin 窗口尚未重新载入由外部工具更新的工程清单，因此出现未知模块错误。

已在原 Gowin 窗口关闭并重新打开同一主工程，文件树和综合输入清单均已出现
`src/audio_record_stream.v`。2026-10-18 20:40 完成当前主工程综合，**0 ERROR、0 WARN**，
生成了新的 `impl/gwsynthesis/PCM5102_PAM8403.vg`；本次没有重新运行布局布线或烧录。
之后若由外部工具向 `.gprj` 增加源文件，应重新打开工程再编译。
