# 仓库维护

[首页](../README.md) · [文档索引](README.md)

远程仓库：[cloud-audio-based-on-fpga](https://gitee.com/yxy0818/cloud-audio-based-on-fpga)，日常同步分支为 `main`。

## 更新流程

工作区干净时，开始修改前拉取远程更新：

```powershell
git status
git pull --ff-only
```

完成修改和相应验证后，在仓库根目录提交、推送：

```powershell
git diff --stat
git add --all
git diff --cached --stat
git commit -m "说明本次修改"
git push origin main
git status --short --branch
```

`git add --all` 同时保存新增、修改和删除。推送被拒绝时先检查远程新增提交并合并，保留双方历史。其他设备需要独立配置 Git 提交姓名、邮箱和 Gitee 登录。

## 保存范围与目录约定

- 主工程开发集中在 `pcm5102_pam8403/`；共享触摸模块保留在 `pmod_hub75e/src/`，避免破坏工程相对路径。
- 保存 RTL、ROM 初始化数据、CST/SDC、Gowin 工程/IP配置、流程配置 JSON、仿真源文件、脚本和文档。
- 安卓源码、核心测试和 `android_app/dist/` 安装包入库；当前安装入口是统一版 `FPGA-Music-Unified.apk`，带旧版本号的包是历史产物。
- `impl/` 编译输出、`sim/build/` 日志/波形、SDK、密钥、工具安装包、重复 ZIP 和本机权限恢复文件由 `.gitignore` 排除。
- `deliveries/` 交付包内的位流、APK、说明和报告随源码入库，与同名目录重复的 `.zip` 快照不入库；合并前的工程入口与专用脚本原样归档在 `pcm5102_pam8403/archive/`。
- `fpga-musical-magic-box-master/` 及 `xqr/fpga-musical-magic-box-master/` 是本机外部参考副本，当前主工程已把所需 RTL 放入自身 `src/`；这些参考副本不作为构建依赖，也不随本仓库上传。迁移关系见 [迁移说明](../pcm5102_pam8403/REFERENCE_MIGRATION.md)。
- `ALL_IN/`、`pcm5102_dds_step1/` 和 `debug/` 保留历史快照。整理文档时不移动既有工程，历史接线与操作按对应版本理解。

## 文档维护

首页概述当前功能与入口；详细操作写在主工程功能文档中。新增功能文档时同步更新 [文档索引](README.md)。

`VERIFICATION.md` 顶部记录最新版本：日期、测试范围、构建工具、时序、资源、位流 UserCode/SHA256、App版本及SHA256。分别写清RTL仿真、布局布线、网表仿真和实板结果；未执行的项目保持未验证，不用历史通过结果替代。

默认参数和协议变动要同步到主工程 README、对应功能页和 App 操作说明。历史文档在开头标明适用版本，避免将旧位流和操作当作当前用法。新增导航采用仓库相对链接，生成日志用路径标记并注明需本地生成。
