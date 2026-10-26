"""Write the conditional resource assessment from completed build evidence."""
from pathlib import Path
import hashlib,json,re
import experiment as exp

here=Path(__file__).resolve().parent
exp.audit()
rows=json.loads((here/'build_audit.json').read_text(encoding='utf-8'))
by={r['label']:r for r in rows}
by['fixed16_clean']=by['fixed16_clean_sdc']
by['fx_fixed16']=by['fx_fixed16_sdc']
assert all(by[n]['status']=='validated' for n in ('fixed16_clean','fx_fixed16')),[(r['label'],r['status']) for r in rows]
reserve={'Logic':1650,'CLS':365,'BSRAM':4}
ledger={}
for name in ('base','fixed16_clean','fx_fixed16'):
    r=by[name]
    ledger[name]={k:{**v,'physical_free':v['capacity']-v['used'],
                    'future_reserve':reserve.get(k),
                    'free_after_known_reserve':v['capacity']-v['used']-reserve[k] if k in reserve else None}
                  for k,v in r['metrics'].items()}
    ledger[name]['implementation_label']=r['label']
prior=json.loads((exp.PRIOR/'build_audit.json').read_text(encoding='utf-8'))
if isinstance(prior,dict):prior=prior.get('builds',prior.get('results',[]))
prior_fx=next(r for r in prior if r['label']=='fx_apds')
delta_vs_prior_fx={k:by['fx_fixed16']['metrics'][k]['used']-v['used'] for k,v in prior_fx['metrics'].items()}
ledger['fixed16_fx_delta_vs_prior_fx_apds']=delta_vs_prior_fx
ledger['reserves']={'D':{'Logic':150,'CLS':30},'B2':{'Logic':900,'CLS':200,'BSRAM':2},
                    'E100':{'Logic':600,'CLS':100,'BSRAM':2},'CLS_safety':35,
                    'Register_DSP':'Not quantified for future features; no zero-reserve claim'}
exp.write_json(here/'resource_ledger.json',ledger)

checks=[]
for label,test,logname in [('fixed16_clean','tb_top_fixed16_controls_ready','fixed16_ready_functional.log'),
                           ('fx_fixed16','tb_fx_fixed16_frame_clean','fx_fixed16_clean_functional.log')]:
    p=here/label/'pcm5102_pam8403'
    log=here/logname
    data=log.read_text(encoding='utf-16' if log.read_bytes().startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
    assert 'PASS ' in data and 'FATAL' not in data and 'simulation failed' not in data,log
    origin={r['Path']:r['SHA256'] for r in exp.manifest(here/label)}
    final_inputs={r['Path']:r['SHA256'] for r in exp.manifest(here/(label+'_sdc'))}
    rtl=[k for k in origin if k.startswith(('pcm5102_pam8403/src/','pmod_hub75e/src/')) and not k.endswith('.sdc')]
    assert all(origin[k]==final_inputs[k] for k in rtl)
    checks.append({'label':label,'matching_final_pnr_label':label+'_sdc','all_rtl_rom_hashes_identical_to_final_pnr':True,
                   'test':test,'log':logname,'log_sha256':exp.sha(log),
                   'test_source_sha256':exp.sha(p/f'sim/{test}.v'),
                   'pass_lines':[s for s in data.splitlines() if 'PASS ' in s or 'FRAME_' in s]})
exp.write_json(here/'functional_results.json',{'passing_tests':checks,
    'partial_failed_integration':json.loads((here/'polarity_test_diagnosis.json').read_text(encoding='utf-8'))})

# Verify only the assessment folders changed: production's frozen 101 inputs,
# previous output artefacts and the rolling APK must still match.
current=json.loads((exp.PRIOR/'final_inputs.json').read_text(encoding='utf-8'))
changed=[r['Path'] for r in current if exp.sha(exp.REPO/r['Path'])!=r['SHA256']]
assert not changed,changed
final=json.loads((exp.PRIOR/'final_production_audit.json').read_text(encoding='utf-8'))
assert all(exp.sha(exp.PROJECT/k)==v for k,v in final['actual_build_file_hashes'].items())
assert exp.sha(exp.PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==final['bitstream_sha256']
apk=exp.PROJECT/'android_app/dist/FPGA-Music-Unified.apk'
assert exp.sha(apk)=='40B92B8201DA38F29140129346E8F02579B532AF443C1BCAA8060B847A015AB6'
exp.write_json(here/'production_unchanged.json',{'verified_production_inputs':len(current),
    'changed':changed,'all_prior_actual_build_artifact_hashes_match':True,
    'production_fs_sha256':final['bitstream_sha256'],'rolling_apk_sha256':exp.sha(apk),
    'app_modified':False,'hardware_programmed':False})

def num(v):return f'{v:g}'
def used(r):return ' / '.join(num(r['metrics'][k]['used']) for k in exp.METRICS) if hasattr(exp,'METRICS') else ' / '.join(num(r['metrics'][k]['used']) for k in ('Logic','CLS','Register','BSRAM','DSP'))
clean=by['fixed16_clean'];fx=by['fx_fixed16'];base=by['base']
savings={k:base['metrics'][k]['used']-clean['metrics'][k]['used'] for k in base['metrics']}
deficits={k:max(0,-ledger['fx_fixed16'][k]['free_after_known_reserve']) for k in reserve}
lines=[
'# 去掉 TTP229 八键模式是否足够支持混响', '',
'评估日期：2026-10-26。范围是用户提出的条件方案：固定十六键串行输入，保留十六声部及其他现有功能。本轮只修改隔离候选，未删除生产八键模式、未改 App、未烧录。','',
f"彻底移除八键读取模块后，整机净释放 {num(savings['Logic'])} Logic、{num(savings['CLS'])} CLS、{num(savings['Register'])} Register，BSRAM 与 DSP 均无回收。",'',
f"再接入上一轮同一份三效果最小原型，保留 D/B2/E100 和安全垫后，仍缺 {num(deficits['Logic'])} Logic、{num(deficits['CLS'])} CLS、{num(deficits['BSRAM'])} BSRAM。因此这项取舍有收益，但不足以兑现原定完整三效果及后续预留。",'',
'## 同条件整机结果','',
'资源顺序：Logic / CLS / Register / BSRAM / DSP。相同 Gowin 二进制、冻结过程配置、50 MHz、resource_sharing=1、retiming=1、place2/route0/maxfan23。生产基线的 101 项输入及实际构建输出哈希均与上轮一致，复用该完整生产构建；不是新跑基线。','',
'| 候选 | 五项已用资源 | Setup / hold WNS ns | 未布通 | 状态 |',
'|---|---|---|---:|---|']
for r in [by['base'],by['fixed16'],by['fixed16_clean_sdc'],by['fx_fixed16_sdc']]:
    t=r['timing'] or {}
    w=' / '.join(num(t[k+'_raw_worst_path']['slack_ns']) if t.get(k+'_raw_worst_path') else '?' for k in ('setup','hold'))
    lines.append(f"| {r['label']} | {used(r)} | {w} | {r['unrouted_nets']} | {r['status']} |")
lines += ['',
'`fixed16` 只把模式固定为常量，是诊断构建；综合仍保留两组带 syn_preserve 的同步器，共 32 个寄存器。`fixed16_clean_sdc` 还显式删除两个旧 GPIO 读取实例，并把废弃输出接常量，才是完整去掉八键的候选。`fx_fixed16_sdc` 在同样删除的基础上接入原三效果原型。', '',
'初次彻底删除实例的 fixed16_clean / fx_fixed16 完成综合后，PnR 因 SDC 第 6、7 行仍引用旧同步器而报 TA2003。原失败目录未覆盖；新 *_sdc 目录只删除这两条已无对象的 false_path，所有其他时钟、异步串行输入及 ADC 约束保留。复用原目录经哈希验证的相同综合网表，执行完整 run pnr，没有重跑综合或改变策略。原综合 .prj 保留原候选路径；新实际 cmd.do 指向新目录综合网表和 SDC。出处、原网表/工程指纹及唯一输入变化见 constraint_repair.json / synthesis_reuse.json。', '',
'不能把两个独立实验的节省相加。下表直接使用组合候选实际用量：', '',
'| 资源 | 组合候选已用 | 硬件剩余 | 既定预留 | 预留后剩余，负数为缺口 |',
'|---|---:|---:|---:|---:|']
for k in ('Logic','CLS','BSRAM'):
    v=ledger['fx_fixed16'][k]
    lines.append('| '+' | '.join([k]+[num(v[j]) for j in ('used','physical_free','future_reserve','free_after_known_reserve')])+' |')
lines += ['',
'预留按前轮核实的 D=150 Logic/30 CLS，B2=900/200/2 BSRAM，E100=600/100/2 BSRAM，另留 35 CLS；C/B1 不重复预留。若恢复完整 E 的 280 CLS 口径，缺口再增加 180 CLS。未来 Register/DSP 尚未单独量化，不能把它们的预留写成零。', '',
'## 为什么删八键不能释放一半音源', '',
'八键模式是七个音符键加 K8 压力模式切换，走 OUT1..OUT8 的两组 GPIO 读取/同步/去抖；十六键走 SCL/SDO 串行读取。两者共用同一个十六声部触摸合成器和后续混音。删除的是输入与切换逻辑，不会删除八个振荡器或释放音频 RAM。固定十六键后，串行 K8 继续作为音符，压力模式保留远程控制。', '',
'## 功能验证与边界', '',
'- 完整固定十六键用例执行至约 197.998 ms，在切换传感器极性时模型报 More than 16 clocks；整条用例失败，未记为通过。其顺序流程已完成上电十六键、十六个音高的 8192 样本 I2S 频谱检查、GPIO 隔离、按住/空闲时 TOUCH8 均 ERR,RANGE、HOLD/PANIC、K16 和 PRESSURE；抵达后续 SERIAL1 段前无其他 fatal。原源码、失败日志及诊断均保留。',
'- 第一条跟进测试将模型复位期间的重配置处理正确后，又因在读端恢复 ready 前发送 TOUCH16 却期待 OK 而失败；实际回复 ERR,BUSY 符合现有协议。最终 tb_top_fixed16_controls_ready 明确检查恢复期间 ERR,BUSY、等待 ready 后重试 OK，并重跑真实 UART/TTP 引脚的全部控制断言及十六声部 gate、高有效极性和 0x8100 和弦。此用例通过；不重复前述频谱等待，也没有证明任意包中途翻转实际传感器极性都能正常恢复。',
'- 完整用例的原始 PCM CSV 被跟进测试的通用输出名覆盖，未独立保留；原测试源码、编译 VVP、失败日志及前置顺序断言证据保留。新的跟进用例已使用独立 PCM 文件名，频谱段可通过原完整用例重新复现，不把遗失的原始 CSV 当作现存证据。',
'- 同帧组合测试使用本轮彻底删除 GPIO 后的 RTL。详细帧数、各引擎最大完成拍及 overrun 检查见 functional_results.json。50 MHz/1024 拍，UART 500k、启动 100 µs、短 ADSR、60 ms 前视并跳过一次视觉预滚；FSR 关闭，未联合滑杆或回放，属于定向原型验证。',
'- 两项正式通过的仿真在原候选目录执行；与最终 *_sdc 候选的全部 RTL/ROM 哈希一致。SDC 修正只用于 PnR，不参与 RTL 仿真。常量诊断的冗余集成仿真被主动停止，未算作通过；早期组合帧测试也只作诊断，正式数据采用彻底删除 GPIO 后重编译的测试。',
'- audio_fx_minproto.v 与前轮 fx_apds 完全一致；前轮 259200 帧逐样本模型是历史证据，没有冒充为本轮新执行。原型仍用临时探针控制，共用 wet，尚无最终独立参数/兼容协议/TAKE/App 三卡和实物音频验收，也未解决尾音量化偏置、测完整网络 RT60。资源表是最小原型，不是最终实现上限。',
'- 全部通过项同时核验完整 PnR、setup/hold 违例端点、原始 timing_paths WNS、实际构建输入清单和输出文件指纹。资源数不是单模块估算。', '',
'## 对条件方案的结论', '',
'固定十六键可以作为继续回收资源的一项，但三效果原型原本就能装入器件；尚未满足的是既定后续预留和最终产品接入。删除八键没有改变 BSRAM 用量，不能单靠它解决存储缺口。', '',
'若坚持三块同时开，还需继续回收逻辑及至少一块 BSRAM。一个有具体依据、但尚未验证的存储实验是：合唱历史按最大延迟 1151 保留 1152 采样，延迟保留 4096，混响只保留实际六线总长 3286，合计 8534；容量上小于 9×1024=9216。目前 2048+4096+4096 映射为 10 块，因而存在尝试回收 1 块的容量空间。需要验证非二次幂循环地址、各自独立写流、bank 分配、同步 RAM 推断、等价音频及新增选择逻辑的整机成本；不能把容量算术当成实际回收。', '',
'若优先实现混响，也可另立明确方案评估“把旧效果器改为合唱/延迟/混响三选一，共用效果存储”或“先只交付混响”。这两项都改变原三块可同时开启的范围，本轮没有实施，也没有把它们当成已验证可交付结果。', '',
'本轮未修改生产 RTL、App 和默认码流。若最终采用固定十六键，还需同步移除 App 的八键入口并处理旧 TOUCH8 请求，包括现有日志配置流程；连接后的状态回读也须联调，不能只改硬件后把协议错误留给用户。', '',
'## 证据和复现', '',
'- `build_audit.json`：五项资源、差值、WNS、端点、原始路径、输入变化、实际构建参数及输出哈希。',
'- `resource_ledger.json`、`functional_results.json`、`production_unchanged.json`：预留账、测试和生产未变核验。',
'- `freeze.json`、各候选 `sources.json`：冻结输入与 Gowin 指纹。`starting_status.txt` / `starting_diff.patch` 保留用户原有修改。',
'- `gpio_removal.json`：常量诊断与彻底删除的差别。候选源码、日志、PnR 及码流都留在各自目录，不能替换默认码流。', '',
'```powershell',
"$py = 'E:/300_IDE_Compiler/Python313/python.exe'",
'& $py reports/touch16_reverb_20261026/experiment.py audit',
'# 原构建命令，必须在对应候选的 pcm5102_pam8403 目录执行；重新实验应使用新目录保留证据：',
'# gw_sh.exe tools/build_unified.tcl',
'# 两个最终 *_sdc 目录已完成原始综合，修正 SDC 后执行：gw_sh.exe tools/pnr_only.tcl',
'# fixed16_clean: ./tools/run_sim.ps1 -Tests tb_top_fixed16_controls_ready',
'# fx_fixed16:    ./tools/run_sim.ps1 -Tests tb_fx_fixed16_frame_clean',
'```','']
(here/'README.md').write_text('\n'.join(lines),encoding='utf-8')
evidence=['README.md','build_audit.json','resource_ledger.json','functional_results.json','production_unchanged.json',
          'constraint_repair.json','freeze.json','gpio_removal.json','diagnostic_runs.json','polarity_test_diagnosis.json']
exp.write_json(here/'evidence_hashes.json',{k:exp.sha(here/k) for k in evidence})
print('Report and independent production-integrity checks complete')
