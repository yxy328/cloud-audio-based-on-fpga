# TP-25K FPGA 工程仓库

保存当前 FPGA / Verilog 工程的源码、引脚和时序约束、工程配置、仿真脚本及验证记录，便于版本回退和多设备协作。

## 工程目录

| 目录 | 内容 |
| --- | --- |
| `pmod_hub75e/` | HUB75E 点阵屏与 TTP229 触摸控制工程 |
| `ttp229_gpio/` | TTP229 输入与模式选择工程 |
| `ttp229_serial16/` | 新增固定 16 键串口最小验证工程，接线见 [说明](ttp229_serial16/README.md) |
| `hc05_uart_echo/` | HC-05 与安卓手机的独立 UART 回显测试，接线见 [说明](hc05_uart_echo/README.md) |
| `pcm5102_pam8403/` | 当前主工程：七键/压力、八路红外、32复音手势音源、蓝牙App、64×64指引 |
| `pcm5102_dds_step1/` | 第一步历史验证快照，只有单声部变调；当前四声部开发不使用此工程 |
| `1-2-4-按键控制LED程序/` | STM32 按键控制 LED 参考工程 |

使用显示与触摸双模式功能，请打开 `pmod_hub75e/HUB75E.gprj`。接线和模式说明见 [MODE_SELECTION.md](MODE_SELECTION.md)，其他工程参见各目录的 README 和 VERIFICATION 文档。

完整引脚、功能、赛题基础/拓展要求状态及现场评分验证见
[主工程验收表](pcm5102_pam8403/PIN_FUNCTION_REQUIREMENTS.md)。

## 当前音频入口

- Gowin 工程：[pcm5102_pam8403/PCM5102_PAM8403.gprj](pcm5102_pam8403/PCM5102_PAM8403.gprj)。
- 顶层源码：`pcm5102_pam8403/src/top.v`，七个独立触摸声部、K8 压力模式、八路红外、32复音TDM、物理弦吉他和64×64曲谱指引。
- 触摸输入共用 `pmod_hub75e/src/ttp229_gpio_input.v`；主工程文件列表和仿真工具直接引用同一份代码。
- 下载位流：`pcm5102_pam8403/impl/pnr/PCM5102_PAM8403.fs`；当前红外/TDM融合版结果见音频工程 `VERIFICATION.md`。
- 操作和接线：[当前音频说明](pcm5102_pam8403/README.md)：K1～K7 默认弹奏 C4～B4，K8 切换压力模式，S1 开始/停止曲谱指引；S2短按在XY页选参考曲线/混音，在其他页重启曲谱，长按约1秒轮换[曲谱、波形、李萨如和实时FFT频谱](pcm5102_pam8403/AUDIO_VISUAL.md)。默认不自动播放曲谱声音，OUT1 接 K4/J3 第 5 脚。
- 手机改键：[HC-05 命令、接线与新增文件清单](pcm5102_pam8403/HC05_KEYMAP.md)。下载同一音频工程，发送 `MAP,1,67` 并追加换行即可将第 1 键设为 G4。
- 直连模式 SCL 不能悬空；用户已实测 SCL 接 GND 后消除误响，保持此接法时不连接 F6，SDO 不接。
- `0x00002064` 的固定和弦操作保留为 [第三步历史说明](pcm5102_pam8403/STEP3.md)。

若 Gowin 已打开旧工程，请关闭并重新打开上面的同一个主工程，让新增模块进入文件列表。
Programmer 的 File name 也需要指向上面的主工程位流；打开源码或编译另一个工程不会自动修改其下载路径。
`pcm5102_dds_step1/`、音频目录中的 `debug/` 和压缩包是历史快照，不随主工程后续修改自动同步。

## 保存范围

- 保存源码、ROM 初始化数据（如 `src/*.hex`）、Gowin 工程和 IP 配置、约束、测试、工具及文档。
- 编译目录、仿真缓存、日志和用户界面设置由 `.gitignore` 排除，仍保留在本机。
- 现有子工程的 `.gitignore` 继续生效。部分子工程保留 `impl/` 中的流程配置 JSON。
- Git 不会自动保存修改；需要提交。远程备份还需要推送。
- 不要提交密码、API Key 或其他凭据。

## 每次保存修改

在本目录终端执行，先检查变更，再保存版本：

```powershell
git status
git diff
git add .
git diff --cached --stat
git commit -m "说明本次修改"
```

接好远程仓库后，再执行 `git push` 将版本上传。

## 连接远程仓库

远程仓库需要在所选平台创建并完成账号认证。创建空仓库时不要额外生成 README，以便推送本地已有版本。

将下方 `REMOTE_URL` 替换为实际仓库地址；首次提交完成后执行：

```powershell
git remote add origin REMOTE_URL
git push -u origin main
```

首次上传之前，本地仓库不属于异地备份。项目源文件可在各设备重新编译，编译器和硬件工具需要分别安装；脚本中的本机工具路径也可能需要调整。

## 在另一台设备使用

```powershell
git clone REMOTE_URL
cd pmod_hub75e_TTP229
```

每次开始修改前，在工作区干净时执行 `git pull --ff-only`；完成修改后提交并推送。若还有未提交修改，先提交，或使用 `git stash` 暂存后再拉取。

多人同时开发时，在各自分支工作：

```powershell
git switch -c feature/your-change
# 修改、检查，然后提交
git add .
git commit -m "说明本次修改"
git push -u origin feature/your-change
```

推送后在远程平台创建合并请求，检查通过后合并到 `main`。每台设备应分别配置自己的 Git 提交名字、邮箱和远程认证。
