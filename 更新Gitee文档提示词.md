# 更新并整理 Gitee 文档 · 自动化提示词

> 用途：作为 Qoder 自动化（定时任务）的执行提示词，定期整理本仓库文档并同步到 Gitee。
> 对应仓库：[cloud-audio-based-on-fpga](https://gitee.com/yxy0818/cloud-audio-based-on-fpga)

---

工作目录：`E:\130_FPGA_Verilog\TP-25K\pmod_hub75e_TTP229`（Gitee 仓库 cloud-audio-based-on-fpga 的本地克隆，远程 `origin = https://gitee.com/yxy0818/cloud-audio-based-on-fpga.git`，分支 `main`）。

任务：检查并整理本仓库的文档与未提交改动，必要时提交并推送到 Gitee。

## 步骤

1. `git status` / `git diff --stat` 查看未提交改动；`git log origin/main..HEAD` 查看未推送提交。
2. 若有实质改动（RTL 源码、Android App、仿真、工具、文档），先筛选提交范围：
   - **不提交**：`ALL_IN*.zip`、根目录大体积备份 zip、`fpga-musical-magic-box-master`（及其 zip）、`pcm5102_pam8403/dsh-acl-recovery`、`deliveries/` 下与同名目录重复的 zip、`impl/` 构建输出。这些大多已被 `.gitignore` 覆盖，遇到新增同类文件时优先补 `.gitignore` 规则而不是删除文件。
   - 提交其余源码与文档。
3. 检查并同步文档（改动涉及功能/版本时必须更新）：
   - 根 `README.md`：「当前功能」日期、功能列表、当前 App 版本号（以 `pcm5102_pam8403/android_app/app/build.gradle` 的 versionName/versionCode 为准）。
   - `docs/CHANGELOG.md`：为新 App 版本 / FPGA 构建补条目，含日期（上海时间）、版本名/Code、功能要点、升级注意事项、位流 UserCode（如有记录）。
   - `docs/README.md`（文档索引）与 `docs/QUICK_START.md`：新增文档要登记索引，快速上手与现状保持一致。
   - `pcm5102_pam8403/VERIFICATION.md`：构建与验证范围以其实际记录为准，不在 README 中编造验证结论。
4. 提交信息风格：英文一行主题（祈使句、概括改动，参考 `git log` 最近提交），需要时附 3~6 行要点列表。用 HEREDOC 传多行信息。
5. `git push origin main`，随后 `git status -sb` 确认与远程同步。
6. 若无实质改动或仅有本地杂物：不做任何提交，只汇报状态。

## 汇报格式

- 有提交：提交哈希、文件数/行数、文档更新点、推送结果。
- 无提交：一句话说明仓库已是最新。

## 边界

- 只推送 `main` 到 `origin`，不新建分支、不强推、不改 git 配置。
- 不删除本地文件；拿不准是否该提交的文件，保留为未跟踪并在汇报中列出。
- 推送失败（网络/认证）时如实汇报错误，不重试超过一次、不改远程地址。
