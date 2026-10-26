from pathlib import Path
import hashlib,importlib.util,json,re,shutil,sys
H=Path(__file__).resolve().parent;P=H.parent.parent;R=P.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):
    b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
inputs=json.loads((H/'production_inputs.json').read_text(encoding='utf-8'))
assert all(sha(R/r['Path'])==r['SHA256'] for r in inputs)
exitinfo=json.loads((H/'production_exit.json').read_text())
assert exitinfo=={'returncode':0,'inputs_unchanged':True}
spec=importlib.util.spec_from_file_location('audit_fx',P/'tools/audit_fx_builds.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
baseline=json.loads((P/'reports/touch16_delivery_20261026/production_audit.json').read_text(encoding='utf-8'))
row=audit.audit(R,audit.sources(H/'base'),baseline['metrics'])
assert row['status']=='snapshot_integrity_unverified',row['status']
assert row['unrouted_nets']==0 and not row['errors']
for kind in ('setup','hold'):
    assert row['timing'][kind+'_violated_endpoints']==0
    assert row['timing'][kind+'_raw_worst_path']['slack_ns']>=0
    assert not row['timing'][kind+'_raw_violating_paths']
assert row['metrics']['CLS']['capacity']-row['metrics']['CLS']['used']>=35
assert all(v['used']<=v['capacity'] for v in row['metrics'].values())
assert (P/'impl/pnr/PCM5102_UNIFIED.fs').stat().st_mtime>(H/'integration.json').stat().st_mtime
row.update(label='production_fx3',status='validated',verified_inputs=len(inputs),source_manifest=str(H/'production_inputs.json'),source_manifest_sha256=sha(H/'production_inputs.json'),build_exit_code=0,snapshot_corrupt_inputs=[])
row.pop('changed_input_hashes',None);row.pop('changed_inputs_vs_baseline',None)
old={r['Path']:r['SHA256'] for r in json.loads((P/'reports/touch16_delivery_20261026/production_inputs.json').read_text(encoding='utf-8'))}
row['changed_inputs_vs_previous_production']=[r['Path'] for r in inputs if old.get(r['Path'])!=r['SHA256']]
row['actual_build_file_hashes']={n:sha(P/n) for n in ['impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do','impl/pnr/device.cfg','impl/pnr/PCM5102_UNIFIED.rpt.txt','impl/pnr/PCM5102_UNIFIED_tr_content.html','impl/pnr/PCM5102_UNIFIED.timing_paths','impl/PCM5102_UNIFIED_process_config.json']}
row['gowin_sha256']=sha(Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe'))
assert row['gowin_sha256']==baseline['gowin_sha256']
save(H/'production_audit.json',row)
if '--audit' in sys.argv:
    print('Production validated:',{k:v['used'] for k,v in row['metrics'].items()},'WNS:',[row['timing'][k+'_raw_worst_path']['slack_ns'] for k in ('setup','hold')]);sys.exit(0)
logs={}
for name,n in [('functional/full.log',1),('protocol_take.log',4),('take528_final.log',1),('top_integration.log',2),('production_regression.log',7),('reset.log',1),('audio_examples.log',1),('app_core_production.log',15),('app_rtl_fixtures.log',1)]:
    text=read(H/name);passes=[l for l in text.splitlines() if l.startswith('PASS')]
    assert len(passes)>=n and 'FATAL:' not in text and 'simulation failed' not in text,(name,passes)
    logs[name]={'SHA256':sha(H/name),'passes':passes}
top=read(H/'top_integration.log')
assert 'overflow_frames=0 clipped_cycles=0' in top and 'stored wet overrides changed live slider' in top
assert 'PASS FX3 replay old/new' in read(H/'chain/pcm5102_pam8403/sim/build/tb_fx3_replay_decode.log')
app=json.loads((H/'apk_release.json').read_text());assert sha(P/'android_app/dist/FPGA-Music-Unified.apk')==app['sha256']
assert all(sha(P/'android_app'/r['Path'])==r['SHA256'] for r in json.loads((H/'app_sources.json').read_text(encoding='utf-8')))
save(H/'functional_results.json',logs)
named=H/'PCM5102_UNIFIED_FX3_20261026.fs'
if not named.exists():shutil.copy2(P/'impl/pnr/PCM5102_UNIFIED.fs',named)
assert sha(named)==sha(P/'impl/pnr/PCM5102_UNIFIED.fs')
save(H/'artifacts.json',{'fs_sha256':sha(named),'apk':app,'burned':False,'phone_installed':False,'analog_capture':False})
tests=[P/'sim'/n for n in json.loads((H/'integration.json').read_text(encoding='utf-8'))['new_tests']]+[P/'sim/tb_fx3_reset.v',H/'fx_reference.py',H/'analyze_audio.py',H/'make_audio_examples.py']
save(H/'test_inputs.json',[{'Path':str(p.relative_to(R)),'SHA256':sha(p)} for p in tests])
audio=json.loads((H/'audio_metrics.json').read_text());music=json.loads((H/'audio_examples/manifest.json').read_text())
t=row['timing'];setup=t['setup_raw_worst_path']['slack_ns'];hold=t['hold_raw_worst_path']['slack_ns']
num=lambda x:f'{x:g}'
lines=['# 三效果优先版交付与验收（2026-10-26）','',
'已接入正式工程并重新构建默认码流，App 为 1.26-fx3 / Code27。固定 16 键与既有功能保留，三块可独立控制、同时工作。用户本轮优先混响和三效果：暂缓未实现的 D/B2/E 的 1650 Logic /330 CLS /4 BSRAM 预留，保留 35 CLS 安全垫；不宣称这些后续扩展已经实现。','',
'## 完整工程资源与时序','',
'| 资源 | 固定16键基线 | 三效果正式构建 | 增量 | 剩余 |','|---|---:|---:|---:|---:|']
for k,v in row['metrics'].items():lines.append(f"| {k} | {num(baseline['metrics'][k]['used'])} | {num(v['used'])} | {num(row['delta_vs_baseline'][k])} | {num(v['capacity']-v['used'])} |")
lines += ['',f'同一 Gowin 二进制，50MHz、resource_sharing=1、retiming=1、place2/route0/maxfan23；未布通0，setup/hold端点违例0/0，原始路径 WNS {setup:+.3f}/{hold:+.3f} ns。CLS剩余中35留作安全垫，其余可用余量为 {num(row["metrics"]["CLS"]["capacity"]-row["metrics"]["CLS"]["used"]-35)}。建立时间余量很紧，后续任何 RTL 改动均须重新完整布线核验。',
f'{len(inputs)}项生产源码/ROM/约束/工程/构建脚本在构建前后哈希一致，实际 prj、cmd.do、device.cfg、资源、时序HTML及原始timing_paths哈希见 production_audit.json；不能只看一张正余量摘要。候选完整构建结果见 chain_audit.json。','',
'## 音频实现与测量','',
'固定链路：现有混音 → CHORUS → DELAY → REVERB → 总音量 → I²S。独立2048/4096/4096采样历史，插值/反馈/湿声共用一个乘法器；完整工程DSP不增加。相关数学、重置和协议见 [FX3.md](../../FX3.md) 及 DESIGN.md。',
'独立采样域队列模型（无RTL FSM或地址调度）与RTL逐样本对比 1,555,536 帧零差异，覆盖全部8掩码、四档正负脉冲、合唱调制、动态设置/旁路/湿声钳位、复位、满幅正负输入，最坏49拍。满幅输入允许饱和，普通拨弦示例无削波。',
'四档混响首个湿声均为25.31328ms。下表针对去掉直接干声的整网湿声能量衰减，T20为-5至-25dB斜率外推的RT60；量化使尾部最终归零，不能把外推值等同直接到-60dB或最后非零时间。','',
'| 预设 | 反馈 | 最后非零(ms) | 直接EDC -60dB(ms) | T20外推RT60(ms) |','|---|---:|---:|---:|---:|']
for v in audio['reverb']:lines.append(f"| {v['preset']} | {v['feedback']} | {v['last_nonzero_ms']:.3f} | {v['direct_EDC_minus60_ms']:.3f} | {v['T20_extrapolated_RT60_ms']:.3f} |")
lines += ['', '四档正负脉冲严格反对称，末10000帧均为零。高反馈预设以输入平均后1/8和四路平均留出余量，因此单样本脉冲湿声峰值较小；不以数字稳定性代替听音质量验收。',
'延迟首湿声实测83.88608/167.79264/335.60576/503.41888ms，切档启动相位额外0/1/3/5帧，不能把后三档首脉冲时间写成无偏差的名义值。长档低通会降低高频湿声，干声保持全采样率。',
'440Hz合唱测试相对解析连续分数延迟，插值误差RMS约1.722LSB，原整数跳变参考约137.920LSB，误差降低38.073dB；此值不是THD或听感评分。',
'同一合成拨弦和弦的原声、单混响、三效果示例再经RTL逐样本验证659181帧，三段均无削波。WAV头采样率48828Hz（实际48828.125Hz），不是DAC/功放实物对录。见 audio_examples/，向量、原始PCM、SHA256均保留。','',
'## 整机与兼容验证','',
'- 真实UART/TTP229引脚、ADS1115总线模型和片内ADC行为输入：16触摸声部、四路滑变弯音、曲谱、三效果同帧。触摸最坏1012拍，弯音43拍，效果49拍，传感器合成535拍；并行硬件占用不相加作为期限。测试含150个压力帧/4次256除法拍触发，零超时、零削波。50MHz/1024帧保持真实，缩短触摸扫描/启动、ADC轮询及ADSR；只跳过曲谱视觉预滚，短压力测试未冒充最长历史填满测试。',
'- 同一顶层经UART录制两套不同掩码/设置，滑杆覆盖湿声；停止后修改实时配置并把滑杆归零，回放恢复录制的配置及实际湿声，两套均被观察。TAKE结束检查kill被下一时钟采样后历史失效，随后检查输出/尾音为零；正常恢复接收零输入后历史计数会继续增加，不要求一直为零。单独复位测试还覆盖填满历史后在混响处理中复位、2500帧零输出及过密输入的overrun置位/复位。',
'- 全528位、WORDS33、DEPTH1024原子快照34检查通过；使用加速毫秒计时和存储模型。旧4字原子用例5检查、通用TAKE25检查、NOR行为模型114检查亦通过；均非实物Flash烧写。新旧TAKE解码2075检查，既有音乐字段未移位。旧录制未保存延迟档，沿用当前档，不能恢复不存在的数据。',
'- 三效果协议36条逐字节回复，8掩码、原子越界拒绝、旧EFFECT0/1/2和EFFECT2、配置/实际差异；通用扩展47回复、生产启动静默、双模拟输入及故障回退、ADS1115/I2C/APDS回归通过。',
'- App完整Java编译、核心测试、真实RTL回复交叉解析5498检查、分片EFFECT3与异步K事件交错通过。读取保留草稿，卡片仅更新本块；采用设备配置需用户明确点击。旧固件ERR,CMD时三效果不可用但保留其他控制。核心脚本另外读到的旧音频录制夹具属于历史回归，并非本轮新采集。',
'- 固定16键/极性恢复与原音源的既有8192样本验收保留。本轮未重新声称全部旧8键顶层或旧逐样本效果参考仍适用，历史参考文件不修改成新算法。','',
'## 产物与剩余实机验收','',
f'- 默认码流：`impl/pnr/PCM5102_UNIFIED.fs`，本目录独立副本 `{named.name}`；SHA256 `{sha(named)}`。',
f'- APK：`android_app/dist/FPGA-Music-FX3-Code27.apk`，滚动入口 `FPGA-Music-Unified.apk` 相同；SHA256 `{app["sha256"]}`。证书与Code26相同，原命名Code26和本目录previous_Code26.apk保留。',
'- 冻结的旧默认构建位于 base/pcm5102_pam8403/impl/，上轮交付报告与产物不覆盖。',
'- 尚未烧录FPGA、安装手机、做真实蓝牙/界面验收、DAC及功放模拟录音或听音。数字证据证明算法/接口/资源/期限，实物效果及混响听感仍需板上确认。','',
'## 中间失败与复现','',
'回复长度先误写26，实际27；当时部分构建停止并保存在chain_partial_query_length。528位原子测试最初错误用DEPTH128，容量保护提前截满，改用生产1024后通过。复位监测先误在同步复位尚未被时钟采样时断言，修正到下一时钟后通过。压力测试先以ANALOG0的available=0误判ADC缺失，开启实际滑杆用途后验证；慢触摸轮询和过长录制的中途运行只保留诊断，不计整条通过。结束时不能要求cf/df在继续接收零输入后永为零，最终用同步复位采样后的边沿检查失效并检查尾音。WAV导出最初把无表头CSV首行当表头，修正导出并复核全部659181行；RTL比较本身此前已通过。这些诊断文件不作为最终PASS证据。',
'```powershell',
"& 'E:/300_IDE_Compiler/Python313/python.exe' reports/fx_priority_20261026/fx_reference.py --full",
'# vectors和outputs用绝对路径传给tb_audio_fx_chain的+vectors与+outputs参数',
'./tools/run_sim.ps1 -Tests tb_fx_protocol,tb_fx3_replay_decode,tb_fx3_frame_take,tb_fx_take_atomic_528',
'./android_app/test-core.ps1',
"./android_app/build-apk.ps1 -OutputApk 'dist/FPGA-Music-FX3-Code27.apk'",
"& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build_unified.tcl",
'```','新实验使用新报告路径，保留本轮冻结源码、失败诊断、原始PCM及验收哈希。','']
(H/'REPORT.md').write_text('\n'.join(lines),encoding='utf-8')
save(H/'evidence_hashes.json',{str(p.relative_to(H)):sha(p) for p in [H/'REPORT.md',H/'production_audit.json',H/'production_inputs.json',H/'functional_results.json',H/'artifacts.json',H/'app_sources.json',H/'test_inputs.json',H/'audio_metrics.json',H/'audio_examples/manifest.json']})
print('Validated and released FX3 production fs + Code27 + report; resource free:',{k:v['capacity']-v['used'] for k,v in row['metrics'].items()})
