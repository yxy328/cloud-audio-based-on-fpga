from work import *
audits=json.loads((HERE/'build_audit.json').read_text(encoding='utf-8'))
release=json.loads((HERE/'release.json').read_text(encoding='utf-8'))
chosen=release['hardware_label'];d=chosen=='score_bend_alt';current=audits[chosen]
labels=['base','tremolo_v2','tremolo_shared','source_volume_v2','score_bend','score_bend_v1','score_bend_alt','ir_tuning_v1','source_expression_v1','touch_tone']
names={'base':'已验证基线','tremolo_v2':'全局震音：独立相位','tremolo_shared':'全局震音：共享相位替代',
 'source_volume_v2':'E4 两路静态音量','score_bend':'D 初稿（缺范围保护）','score_bend_v1':'D 完整范围保护',
 'score_bend_alt':'D 比较器/格式替代','ir_tuning_v1':'E2 八弦静态定弦','source_expression_v1':'E3 分源颤音开关锁存','touch_tone':'E1 触摸正弦/三角波'}
rows=[]
for label in labels:
    r=audits[label];assert len(r['metrics'])==5,(label,r['status'])
    values=[r['metrics'][key]['used'] for key in ('Logic','CLS','Register','BSRAM','DSP')]
    values=[str(int(v)) if v==int(v) else str(v) for v in values]
    t=r.get('timing');timing='未完成'
    if t and t.get('setup_raw_worst_path') and t.get('hold_raw_worst_path'):
        timing=f"{t['setup_raw_worst_path']['slack_ns']:+.3f}/{t['hold_raw_worst_path']['slack_ns']:+.3f}"
    safety=r['metrics']['CLS']['capacity']-r['metrics']['CLS']['used'];missing=max(0,35-safety)
    status='接入' if label==chosen else '对照' if label=='base' else '淘汰'
    reason='布置失败' if r['status']=='placement_failed' else '时序失败' if r['status']=='timing_failed' else f'安全垫缺 {int(missing)} CLS' if missing else '初筛非完整功能' if label=='score_bend' else status
    rows.append('| '+ ' | '.join([names[label],*values,str(int(safety)),timing,status+'；'+reason if status!=reason else status])+' |')
metrics=current['metrics'];remaining={k:v['capacity']-v['used'] for k,v in metrics.items()}
free=remaining['CLS']-35
artifact_rows='\n'.join(f"| {name} | `{value['sha256']}` |" for name,value in release['artifacts'].items())
stages=[
('体验1','已完成软件实现；待手机验收','常用演奏入口、总音量、三效果配置/实际、录放入口、紧急止音；进阶参数折叠；普通界面移除阶段/预算文案'),
('体验2','已完成软件实现；待蓝牙/听音验收','手机本地场景：保存最新设备配置、命名/改名/删除、主动应用、原子三效果设置、写后匹配；不覆盖三卡草稿'),
('验收与过渡','数字测量与准备完成；实机未测','14类操作729722帧 RTL核对；原始/RMS衰减参考、18项实机表、两分钟演示；未修改固件平滑或清尾'),
('全局震音','资源不足，未接入','独立相位34 CLS、共享相位40 CLS；分别距35安全垫缺19/25；DSP均无增量'),
('E0/E4','E0已核对；E4候选资源不足','当前两生产者队列共享参数快照；未预复制三套状态。四档两路音量放置失败；三轨音量/力度/独立LFO未实现'),
('原D','最小弯音目标已接入；待实机验收' if d else '资源不足，未接入',
 'CSV 每事件共用滑入目标；即时静态偏移、和弦各音独立目标和MIDI弯音导入仍拒绝' if d else '初稿8 CLS未满足保护；完整保护20 CLS不够安全垫；结构替代结果见资源表。CSV/导出代码保留为实验稿，普通App不暴露该能力'),
('E2','资源不足，未接入','八弦48..84静态定弦初筛45 CLS，安全垫缺30；TAKE表格保存还未完成，不能把此原型当成完整可交付功能'),
('E3','资源不足，未接入','只试独立颤音开关的逐音锁存；共享速率/深度/等待不变；27 CLS，安全垫缺12；同拍双生产者锁存测试通过'),
('E1','资源不足，未接入','只试触摸正弦/三角波；36 CLS，安全垫缺21；未完成频谱/听音，不承诺谐波编辑器'),
('B2','未实施；几何与兼容依赖未满足' if d else '未实施；原D依赖未满足','仍为七键MAP/弯音/曲谱指引，K13～16为高音条。12键映射、指引/试听和踏板需跨几何与TAKE设计；本轮无完整B2构建，不声称确定放不下')]
stage_rows='\n'.join('| '+' | '.join(row)+' |' for row in stages)
text=f'''# 演奏体验与后续扩展逐项验收（2026-10-26）

交付 App：{release['app_version']}。保留当前工作区的贴纸/背景素材与先前修改；没有安装App、烧录FPGA或写板上Flash。当前默认硬件为 `{chosen}`，其全部生产输入与冻结构建逐项匹配；候选成本不互相叠加，也不把失败候选计为收益。

## 阶段结果

| 范围 | 状态 | 说明 |
|---|---|---|
{stage_rows}

常用说明：[PERFORMANCE_QUICKSTART.md](../../PERFORMANCE_QUICKSTART.md)。[实机验收和演示](ACCEPTANCE.md)，逐项结果填 [hardware_checklist.csv](hardware_checklist.csv)。[B2几何与依赖复核](B2_REVIEW.md)。所有实机项目目前均为未测，数字验证不代表听音、手机布局或真实蓝牙通过。

## 当前共享资源账

当前用量：Logic {metrics['Logic']['used']:g}/23040、CLS {metrics['CLS']['used']:g}/11520、Register {metrics['Register']['used']:g}/23280、BSRAM {metrics['BSRAM']['used']:g}/56、DSP {metrics['DSP']['used']:g}/28。剩余 CLS {remaining['CLS']:g}，其中35保留，额外可用 **{free:g} CLS**；剩余 Logic {remaining['Logic']:g}、BSRAM {remaining['BSRAM']:g}、DSP {remaining['DSP']:g}。任何后项从此账重新准入。

以下均从同一冻结三效果基线出发，用同一 Gowin、50MHz、sharing=1、retiming=1、place2/route0/fanout23。失败/独立候选的差值不能相加。原始输入、.prj、cmd.do、device.cfg、timing_paths 和报告哈希见 [build_audit.json](build_audit.json)。`validated`只表示完整资源/布线/时序通过，还必须满足35 CLS安全垫和功能/兼容性检查。

| 构建 | Logic | CLS | Register | BSRAM | DSP | 剩余CLS | 原始 setup/hold WNS ns | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|---|
{chr(10).join(rows)}

分源音量报告的11520 CLS已满，另有84 LUT等价单元未放入，不能将50 CLS当作完成布局后的真实总成本。红外初稿曾有第8弦索引错误及51单元放置失败，修复版另行完整构建并通过46条协议回复，最后仍不满足安全垫。APDS串行复用代码已在基线中；重复对照的输入完全相同，净收益0，没有再记95 CLS历史收益。

开始时102项生产输入与三效果报告相同，但滚动码流哈希、资源/时序HTML已有漂移，已保留 `previous_default.fs` 并隔离重建；没有直接把旧报告当现状。App Manifest已到Code32而Gradle还在Code27，工作期间又出现Code34外观更新，最终版本高于这些版本且两处同步。过程文件保留，不覆盖旧交付。

## 软件和音频验证

- App完整 Java/D8/aapt2 编译、APK签名/证书、版本和源码前后哈希核对，完整核心测试；场景新增170检查覆盖配置/滑杆/TAKE区别、命名改删、原子保存/CRC损坏保护、拒绝/失配/超时/回读恢复。未运行手机界面或真实蓝牙。
- 原有总音量单调渐变、精确静音/单位增益、反向调整、帧边界通过；三效果36回复、新旧TAKE解码2075检查、528位原子快照34检查通过。旧PCM音频夹具是既有回归，不是新采集。
- 十四类控制变化729722帧对独立采样域模型零差异，最坏49拍。与相同输入但不改参数的反事实参考比较，单档合唱/延迟/混响湿声边界差值为−117/−195/+16 LSB，三湿声从0到8为−2376 LSB；这些是给定合成输入/时刻的数据，**不是已确认可闻故障**。详见 [transition_metrics.json](transition_metrics.json)。
- 复用原始原声/单混响/三效果WAV并核对哈希。RMS参考只衰减0/0.0554/0.6394 dB，不提高音量；不是LUFS或感知等响保证。详见 [listening_references.json](listening_references.json) 与 `audio/`。示例真实Fs48828.125 Hz，文件头48828 Hz，均非DAC/功放对录。
- 两套震音独立模型分别813954/755280帧通过，最坏53/52拍；独立方案204条、共享方案132条协议回复以及新旧TAKE字段检查。它们因资源门槛淘汰，**未做App控制、实板听音或完整交付验收**。
- 两路静态音量45回复、262144组符号样本/四档和16种TAKE组合通过；E3的47回复及同拍IR/手势参数捕获、后续改值隔离、等待后激活和1024拍帧测试通过；触摸音色44回复通过。它们均留在隔离目录。
- D实验：旧曲谱双bank/密集128事件、139条扩展字宽/拒绝/范围检查、52/56条协议回复、原手动七声部弯音回归通过。v1真实UART/TTP/双ADC/16声部/三效果并行最坏触摸1012、音高43、效果49拍；TAKE回放观察293帧已弯音实际步进。只跳过60ms视觉预滚，没有缩短音频帧；该拓扑仍复用已有硬件模型而非实物。
- D结构替代的范围比较器以763021组合法域参考对比，通过全部允许目标和全部上下边界；手机CSV实验稿4827检查含2401音分、显式0/空白、和弦拒绝、导出回读及128×60000ms。最终是否接入见阶段表；未接入时这些检查不算用户已获得能力。

## 产物与回退

| 产物 | SHA256 |
|---|---|
{artifact_rows}

标准入口为 `android_app/dist/FPGA-Music-Unified.apk` 与 `impl/pnr/PCM5102_UNIFIED.fs`，均经哈希核对。命名APK与报告内命名码流保留，旧命名版本不覆盖。新硬件位流来自已验证冻结目录，生产源码逐项与其一致；复制的综合/PnR文件共{release['copied_output_file_count']}项，逐项哈希见 [production_output_hashes.json](production_output_hashes.json)。如只更新App，硬件仍为新复现的原有三效果功能。详见 [release.json](release.json)。

回退文件包括本轮前的滚动APK/码流、此前命名Code27/Code34以及已验证三效果位流。`previous_default.fs`仅表示启动时的旧入口，因哈希漂移不把它另称为已验证新构建。回退需人工操作，未执行安卓降级、卸载、烧录或Flash保存。

## 保留的限制

没有复用“旧预留330 CLS”作虚拟空间；35 CLS安全余量没有挪用。未取消原D/E/B2规划，也没有因某项失败宣称整组永久不可能。仅报告本轮具体候选的实测失败；未完成的格式、几何、频谱或实机验证列为未完成。候选未通过时不删现有音源、三效果、录放、事件数或时长来挤空间。

没有硬件听音证据，未新增湿声逐采样平滑、预设跨尾或双缓冲交叉淡化；PANIC和TAKE停止/结束清尾保持原约定。后台读取不抢占草稿；更多App命令不能突破固件0..8湿声档位。
'''
(HERE/'REPORT.md').write_text(text,encoding='utf-8')
print(HERE/'REPORT.md')
