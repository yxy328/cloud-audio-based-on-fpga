# 激励准备与中间运行记录

用于最终功能判定的 APDS 日志仅为 baseline/apds_serial 的 `*-scenarios.log`、`*-guard.log`、`*-nack.log` 及 bus.log；Flash 为 baseline-flash.log 和 flash_rotate-flash.log。functional_results.json 明确列出所用文件和比较口径。

`fixture_initial_scenario_setup.log` 是先跑原基线时发现的激励间隔问题：NACK 后太快放入下一次手势，未等待既有 quiet-poll 清理，实际只有 9 次分类而激励要求 10 次。把恢复手势从 poll180/181 移至184/185后，先验证原基线，再验证候选；未修改 DUT 的清理行为来满足断言。该初始日志不计为候选功能结果。

`exploratory_idle_run_baseline.log` 和 `interrupted_idle_run_candidate.log` 是默认 10ms 空闲等待的较长探索运行；后者中止，不能算通过。最终 guard 测试保持默认 100000 拍活动轮询与 750000 拍释放保护，只加速空闲/启动等待；采用独立的 *-guard 文件避免将部分输出当成验收证据。

生产树的当前 I2C bus 测试连接了较新 ADS1115 写扩展端口，而被冻结的旧 master 没有这些端口。仅在 fixtures 副本移除这两条无关连接；旧基线 master 的源文件哈希不变。

Flash 初次编译发现候选 rotate_header 连线引用了声明顺序之后的 crc_bits，Icarus 拒绝 elaboration。将组合连线声明移至寄存器声明之后再进行功能验证；build_audit.json 和 sources.json 中的候选哈希均对应修正后的最终实验源码，不对应未编译版本。未将编译失败或准备激励所用次数当作资源优化成绩。
