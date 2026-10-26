# 固定十六键串行输入（2026-10-26）

当前统一工程 `PCM5102_UNIFIED.gprj` / `top_unified` 固定使用 TTP229 的十六键串行接口。上电即启动串行校准，不再通过 App 从八键切换。旧 OUT1～OUT8 GPIO 读取、去抖和 K8 压力切换路径已删除；全部十六个触摸声部、K1～K7 映射/弯音、压力/滑杆、音色、显示、曲谱和 TAKE 保留。本轮没有接入三效果原型。

App 使用 [v1.25-touch16 / Code26](android_app/dist/FPGA-Music-Touch16-Code26.apk)，滚动安装包为 [FPGA-Music-Unified.apk](android_app/dist/FPGA-Music-Unified.apk)。界面显示固定十六键，移除模式选择和旧 REC 日志的一键八键配置；原日志导出仍可查看历史内容，演奏录制使用手机 MIDI 或板上 TAKE。

接线沿用现有十六键方案，只使用 SCL/SDO 和电源/地，拆除 OUT1～OUT8 直连线。模块的十六键及多键焊盘仍需按模块实际配置，App 不能改变硬件焊盘。上电约 0.6 秒校准后，先松键再按；K8 是音符键，压力音量/音高通过 App 切换。默认低有效串行；高有效模块应在 App 应用相应极性，设置不跨 FPGA 断电保存。

| 命令/查询 | 当前行为 |
|---|---|
| `CTRL?` / `CTRL2?` | 模式字段恒为 `1`，其他字段及回复长度沿用原协议 |
| `TOUCH,8` | `ERR,RANGE`，不改变声音或输入状态 |
| `TOUCH,16` | 空闲且键盘就绪、延音关闭时 `OK`；其他情况仍为 `ERR,BUSY` |
| `SERIAL,0` / `SERIAL,1` | 选择低/高有效极性；即使键盘未就绪，也可在曲谱、下载、音符、录制均空闲且延音关闭时应用，以便恢复错误极性 |
| `SERIAL?` | 回读已配置极性 |
| `PRESSURE,0` / `PRESSURE,1` | 手机选择压力音量/音高用途，K8 不再切换 |

更改极性后串行读端重新校准；校准期间 `TOUCH,16` 等需要就绪的编辑命令可返回 `ERR,BUSY`。待就绪后再操作。演奏或录制期间更改极性仍返回 `ERR,BUSY`。

完整资源、时序、源码/默认码流/APK 指纹、测试范围及未做的实物验收见 [交付报告](reports/touch16_delivery_20261026/README.md)。旧版本、旧默认构建已保留在该报告目录的 `previous_default/`。
