# 合并前的历史工程模板

当前主目录唯一的工程入口为 [PCM5102_UNIFIED.gprj](../../PCM5102_UNIFIED.gprj)，顶层 `top_unified`；默认构建命令为 `gw_sh tools/build.tcl`，输出 `impl/pnr/PCM5102_UNIFIED.fs`。

以下三个旧入口保留为原始模板，增加 `.archived` 后缀，避免被误当作当前工程打开：

| 模板 | 原用途 |
| --- | --- |
| `PCM5102_PAM8403.gprj.archived` | 正常演奏、曲谱和 LED 控制 |
| `PCM5102_EVENT_TAKE.gprj.archived` | 独立事件录制、板上重放 |
| `PCM5102_AUDIO_TAKE.gprj.archived` | 独立 PCM 录音、HC-05 回传 |

旧版专用构建、资源检查及打包脚本归档在 `tools/`，原工程配置归档在 `impl/`。这些文件保留原内容与原相对路径，仅作历史参考；不要在本归档目录直接运行。

如需研究旧目标，请在单独的仓库副本中恢复：将三个模板复制到该副本的 `pcm5102_pam8403/` 并去掉 `.archived` 后缀，将本目录 `tools/`、`impl/` 的对应文件恢复到副本同名目录。当前 `src/` 已继续修改，恢复模板不等于恢复已验证的旧版本；需要复现旧位流时，应使用旧交付包中匹配的完整源码快照。

已交付的源码快照、位流和压缩包保持原内容。统一版的构建、资源及时序结果见 [RAM_GEOMETRY_VERIFICATION.md](../../RAM_GEOMETRY_VERIFICATION.md)，录制操作见 [UNIFIED_RECORDING.md](../../android_app/UNIFIED_RECORDING.md)。
