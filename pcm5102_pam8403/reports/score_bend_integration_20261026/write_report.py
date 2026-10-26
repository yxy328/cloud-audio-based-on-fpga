from work import *

release=json.loads((HERE/'release.json').read_text(encoding='utf-8'))
audit=release['physical_audit'];metrics=audit['metrics']
verification=json.loads((HERE/'verification.json').read_text(encoding='utf-8'))
timing=audit['timing']
setup=timing['setup_raw_worst_path']['slack_ns'];hold=timing['hold_raw_worst_path']['slack_ns']
lines=['# 曲谱弯音交付（2026-10-27）','',
    '已接入当前 HC-05 优化基线，App 1.38-scorebend / Code39。默认源码、回复生成器、24 项综合/PnR 输出及默认 APK 已更新并按哈希核对。保留当前界面与素材。未安装 App、烧录 FPGA 或写板上 Flash。','',
    '## 资源与时序','',
    '| 资源 | 上一默认 | 本轮默认 | 净增量 | 剩余 |','|---|---:|---:|---:|---:|']
base=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))['baseline_audit']['metrics']
for name in ('Logic','CLS','Register','BSRAM','DSP'):
    old=base[name]['used'];new=metrics[name]['used'];free=metrics[name]['capacity']-new
    lines.append(f'| {name} | {old:g} | {new:g} | {new-old:+g} | {free:g} |')
lines += ['',f'CLS 剩余 {audit["cls_free"]:g}，保留 35 后功能预算 **{audit["cls_free"]-35:g} CLS**。50MHz，sharing=1、retiming=1、place2/route0/fan23；未布通 0，setup/hold 违例端点 0/0，原始 WNS **{setup:+.3f}/{hold:+.3f}ns**。','',
    '候选 place1 为 22445 Logic / 11432 CLS / 55 BSRAM，完整布通但 3 个 setup 端点违例，原始 WNS -0.675ns，未采用。place2 保持相同 RTL/ROM/约束和综合设置，只改变放置策略，重新独立完成构建。净增加 52 CLS 包含 RTL 和物理策略联合影响，不能把旧 D 的 20 CLS 当作本轮实际增量。','',
    '同策略 place2 基线复用先前 HC-05 reply_parallel 的完整冻结构建；与本轮开始的全部 104 项输入只有放置脚本不同，工具一致，RTL/ROM/约束逐项相同。该基线 11420 CLS、9 个 setup 违例；本轮 place2 为 11439 CLS，同策略差值 +19，仅作结构对照。部署资源账仍从已交付 place1 的 11387 计到 11439，即 +52，不混用基线。','',
    '完整证据：[候选审计](candidate_place2/audit.json)、[冻结输入](freeze.json)、[功能结果](verification.json)、[接入与输出哈希](release.json)。','',
    '## 功能与验证','',
    '- 每事件一个和弦共用弯音目标，按现有 PITCH 滑音速率靠近；保留七键映射、16 键演奏、压力/滑杆、三效果、LED 和录放。旧两列 CSV、旧下载命令与 MIDI 既有行为保留。',
    '- App 支持三列 CSV 导入、逐事件目标预览、能力/范围预检查和导出；空白沿用手动目标，0 回正。和弦各音独立目标和 MIDI 非中心弯音仍明确拒绝。',
    '- 双 bank 各 128 条、每条 1..60000ms 不变；END/PLAY 当前范围校验，失败 END 保留旧 active bank。TAKE 维持 528 位格式，保存实际应用步进。',
    f'- {verification["required_count"]} 组最终必要检查通过。11 组旧协议回归每拍比较全部 67 个既有输出；涵盖命令、竞争、三效果、曲谱、TAKE、ADSR、弯音和显示/XY。',
    '- 139 条曲谱目标/边界命令，128×60000ms 数据几何；手动弯音 1024 单调步与新增七键算术模型；新旧 TAKE 解码 2075 检查、528 位原子快照 34 检查。',
    '- 真实 UART/TTP229、双 ADC、16 声部、曲谱试听与三效果并行，触摸最坏 1012 拍、音高 43 拍、效果 49 拍；各自均在 1024 拍期限内，无溢出或削波。TAKE 回放观察到 293 帧实际弯音后步进。',
    '- 外部 I2S/串行触摸试听检查覆盖事件目标变化、预滚/PLAY 隔离、手动目标保留、STOP 恢复、重复音与休止/结束。改造后的旧试听刺激也在未改 RTL 基线上检查。顶层仅跳过视觉预滚等待，所有音频帧和音符时长保持；完整预滚时序由模块级曲谱回归覆盖。',
    f'- 旧试听场景外部 I2S 的 {verification["legacy_audio_equivalence"]["sample_count"]} 个 PCM 样本及时间戳与未改基线逐项完全一致，见 [音频对照](legacy_audio_equivalence.json)。旧七键峰值阈值在固定16未改基线上同样失败，因此以当前基线完整样本对照替代该过期阈值。',
    '- App 完整核心回归、CSV 4827 检查（2401 个整数音分、空白/0、拒绝与导出回读）、Java/D8/aapt2 编译、APK 签名和两处版本通过。与回退 APK 证书一致。','',
    '准备过程的换行合并冲突、测试语言模式、重复可选端口、旧 GPIO 刺激和补充夹具参数/命令长度诊断保留；未计为通过证据，未据此改动硬件功能。长视觉等待的诊断运行中止，改用记录明确的顶层视觉等待跳过与模块时序回归。','',
    '这是数字与软件验证，未完成手机界面、真实 HC-05 链路、实板听音和显示验收。详见 [设计与作用范围](DESIGN.md)。','',
    '## 使用与回退','',
    '1. 使用 `android_app/dist/FPGA-Music-ScoreBend-Code39.apk` 与配套新码流；本轮已更新默认入口，设备安装/烧录由用户执行。',
    '2. 在 App 曲谱页导入 [示例 CSV](score_bend_demo.csv)，校验键位并下载。设备范围不足时先扩大弯音范围，之后重新下载。',
    '3. 点击“自动演奏 · 已下载曲谱”。PLAY 仍为无声指引。可预览每条目标或“导出当前曲谱 CSV”。详见 [操作说明](../../SCORE_BEND.md)。','',
    '| 产物 | SHA256 |','|---|---|',
    f'| FPGA-Music-ScoreBend-Code39.apk | `{release["apk_sha256"]}` |',
    f'| PCM5102_UNIFIED_SCORE_BEND_20261027.fs | `{release["bitstream_sha256"]}` |',
    f'| 回退 FPGA | `{release["rollback_bitstream_sha256"]}` |',
    f'| 回退 APK | `{release["rollback_apk_sha256"]}` |','',
    '回退位于 `production_before/impl/pnr/PCM5102_UNIFIED.fs` 和 `production_before/rollback_app.apk`；旧源码在 `baseline/`，旧 App 源码与素材在 `app_before/`。未自动降级或写入设备。','']
(HERE/'README.md').write_text('\n'.join(lines),encoding='utf-8')

intro=(f'**2026-10-27 曲谱弯音已接入：[完整交付与回退](reports/score_bend_integration_20261026/README.md)。** '
       f'App Code39；Logic {metrics["Logic"]["used"]:g}、CLS {metrics["CLS"]["used"]:g}、BSRAM 55、DSP 26.5。'
       f'剩余 {audit["cls_free"]:g} CLS，保留35后可用 {audit["cls_free"]-35:g}。'
       f'50MHz 完整布通，setup/hold 违例0/0，原始 WNS {setup:+.3f}/{hold:+.3f}ns。'
       '默认入口已更新，未安装或烧录。以下旧版本记录保留。\n\n')
for filename in ('README.md','VERIFICATION.md'):
    path=PROJECT/filename
    text=path.read_text(encoding='utf-8-sig')
    assert '2026-10-27 曲谱弯音已接入' not in text
    first,rest=text.split('\n',1)
    path.write_text(first+'\n\n'+intro+rest.lstrip('\n'),encoding='utf-8')
for relative in ('HC05_KEYMAP.md','PERFORMANCE_PARAMS.md','android_app/README.md','PERFORMANCE_QUICKSTART.md'):
    path=PROJECT/relative;text=path.read_text(encoding='utf-8-sig')
    link='../SCORE_BEND.md' if relative.startswith('android_app/') else 'SCORE_BEND.md'
    first,rest=text.split('\n',1)
    path.write_text(first+'\n\n**2026-10-27：曲谱事件弯音已接入，App Code39。** '
        f'[CSV、协议、试听与录放说明]({link})。旧三参数曲谱命令保留；能力查询 `SONG_BEGIN,?` 返回 `SONGBEND,1`。\n\n'+rest.lstrip('\n'),encoding='utf-8')
print('Wrote current resource ledger and release documentation')
