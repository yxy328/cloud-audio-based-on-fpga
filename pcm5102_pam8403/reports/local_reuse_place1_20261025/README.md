# 冻结资源候选 place 1 重试，2026-10-25

**apds_serial_place1 在 place1 下完整布线且时序通过；相对同策略基线净少 95 CLS、179 Logic。500 CLS 目标尚未达到，未接入生产。**

| 构建 | Logic | CLS | Register | BSRAM | DSP | 未布线 | setup/hold WNS ns | 状态 |
|---|---:|---:|---:|---:|---:|---:|---|---|
| engine_share_base_20261024 | 21603 | 11326 | 10461 | 47 | 26.5 | 0 | +0.083/+0.152 | validated |
| baseline_place1 | 21603 | 11310 | 10461 | 47 | 26.5 | 0 | +0.010/+0.156 | validated |
| apds_serial_place1 | 21424 | 11215 | 10466 | 47 | 26.5 | 0 | +0.161/+0.197 | validated |
| flash_rotate_place1 | 21666 | 11234 | 10467 | 47 | 26.5 | 233 | 不可验收 | routing_failed |

- `baseline_place1`：相对本轮 place1 基线 Logic +0、CLS +0、Register +0、BSRAM +0、DSP +0；相对相同 RTL 的 place0 Logic +0、CLS -16、Register +0、BSRAM +0、DSP +0。
- `apds_serial_place1`：相对本轮 place1 基线 Logic -179、CLS -95、Register +5、BSRAM +0、DSP +0；相对相同 RTL 的 place0 Logic +0、CLS -49、Register +0、BSRAM +0、DSP +0。
- `flash_rotate_place1`：相对本轮 place1 基线 Logic +63、CLS -76、Register +6、BSRAM +0、DSP +0；相对相同 RTL 的 place0 Logic +0、CLS -8、Register +0、BSRAM +0、DSP +0。

本轮按用户要求将 place_option 改为 1，保留 route_option=0、route_maxfan=23、global_freq=50、resource_sharing=1、retiming=1。器件与工具沿用 GW5A-LV25MG121NC1/I0、Gowin V1.9.11.03 Education。三组各自重新校验原冻结的 98 项输入，源文件未改，APDS 与 Flash 候选互不叠加。baseline_place1 是原 engine_share_base_20261024 的同条件对照。

## 流程与比较边界

初始复制原综合网表并调用 run pnr；Gowin 在新目录自动补跑综合。因此本报告按“相同冻结源码、相同综合参数、place 1 重建”记录，不能称为只消费了旧综合网表。加密 .vg 的输出哈希与层级资源 XML 对比均保留在 build_audit.json。无法通过去除明文注释证明加密网表内部逐字节等价；资源 XML 相同也不能替代形式等价。实际 .prj、cmd.do、device.cfg 均与相同 RTL 的 place0 构建对比，除路径与已改变的 place_option 外不应存在其他配置差异。

本轮只改物理实现设置；功能证据沿用 [上一轮功能记录](../local_reuse_20261025/functional_results.json) 与 [位宽、周期预算及边界](../local_reuse_20261025/design_notes.md)。未将既有失败候选的局部综合节省计为交付收益。APDS 最大新增 768 拍（15.36µs），Flash 每次元数据处理新增 5 拍（100ns）；这些行为变化没有因 place 1 而消失。

## 源文件完整 SHA256

| 构建 | 与 place1 基线不同的源文件 | 基线 SHA256 | 候选 SHA256 |
|---|---|---|---|
| apds_serial_place1 | pcm5102_pam8403/src/apds9960_ctrl.v | `BC1F2F0F211D6330F8B443CF5E97C546E60A11CF198D82975E1878E8DAB808F8` | `4AAA3F1F0E20BFFFB35B49567427ED0054B972D9167F98C5337A3E69FDC77492` |
| flash_rotate_place1 | pcm5102_pam8403/src/take_nor_store.v | `EA40B6DDAD00421DDD759C9C2A8F89BBA754183521201143215652B0ADB460C9` | `9594517C7A864D618367C3728BD6BAA4339A8D9FBEDD24A326A38DB56405B965` |

每个 sources.json 保存全部 98 项源输入；freeze.json 保存起始网表、脚本和工具哈希。PnR 最终实际消费网表的哈希及综合是否自动重跑单列在 build_audit.json。候选位流如有产生仅存于实验目录，其 SHA256 和时序违例端点同时记录；没有覆盖交付位流、发布 APK、烧录或接入生产。

状态必须分开理解：validated 仅表示此冻结构建资源报告、完整布线和 setup/hold 检查通过；是否净回收 500 CLS 由 meets_500_cls_target_vs_place1_baseline 标识；必要集成回归与生产接入不因布线通过而自动完成。当前生产接入数为 0。

APDS 相对原已验证 place0 基线 CLS 少 111，其中基线自身改为 place1 已少 16；同 place1 条件的 RTL 净下降是 95，不能将 111 全部算为 RTL 优化收益。第一阶段 500 CLS 目标尚未达到，本轮按用户要求只验证 place1 的布局布线；未追加整套长回归、未把此前功能初筛表述为生产接入验收。

本次实际调用各冻结目录的 `pcm5102_pam8403/tools/pnr_only.tcl`（place1/route0/fanout23）。原 build_unified.tcl 保留为原始哈希输入，其中 place0 不用于本次位流；后续重现请使用 pnr_only.tcl，并在新输出目录重建，避免覆盖现有证据。执行过程详见 [execution_notes.md](execution_notes.md)。

[机器可读审计](build_audit.json) · [输入冻结](freeze.json) · [生产树并发漂移](production_after_check.json)
