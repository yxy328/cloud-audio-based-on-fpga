"""Verify production and functional evidence, publish matching local artifacts."""
from pathlib import Path
import hashlib,importlib.util,json,re,shutil,sys
import deliver as d
here=d.HERE;p=d.PROJECT
def read(path):
    b=path.read_bytes()
    return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
inputs=json.loads((here/'production_inputs.json').read_text(encoding='utf-8'))
assert all(d.sha(d.REPO/r['Path'])==r['SHA256'] for r in inputs)
exit_info=json.loads((here/'build_exit.json').read_text(encoding='utf-8'))
assert exit_info=={'returncode':0,'inputs_unchanged':True},exit_info
baseline=json.loads((p/'reports/fx_delivery_20261025/final_production_audit.json').read_text(encoding='utf-8'))
spec=importlib.util.spec_from_file_location('audit_final',p/'tools/audit_fx_builds.py')
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
row=audit.audit(d.REPO,audit.sources(d.CANDIDATE),baseline['metrics'])
assert row['status'] in ('validated','snapshot_integrity_unverified'),row['status']
row.update(label='production_fixed16',status='validated',verified_inputs=len(inputs),
           source_manifest=str(here/'production_inputs.json'),source_manifest_sha256=d.sha(here/'production_inputs.json'),
           build_exit_code=0,snapshot_corrupt_inputs=[])
row.pop('changed_input_hashes',None);row.pop('changed_inputs_vs_baseline',None)
original=json.loads((p/'reports/fx_delivery_20261025/final_inputs.json').read_text(encoding='utf-8'))
row['changed_inputs_vs_previous_production']=[r['Path'] for r,o in zip(inputs,original) if r['SHA256']!=o['SHA256']]
files=['impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do','impl/pnr/device.cfg',
       'impl/pnr/PCM5102_UNIFIED.rpt.txt','impl/pnr/PCM5102_UNIFIED_tr_content.html','impl/pnr/PCM5102_UNIFIED.timing_paths',
       'impl/PCM5102_UNIFIED_process_config.json']
row['actual_build_file_hashes']={s:d.sha(p/s) for s in files}
gowin=Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
row['gowin_sha256']=d.sha(gowin)
assert row['gowin_sha256']==json.loads((p/'reports/fx_delivery_20261025/freeze.json').read_text(encoding='utf-8'))['gowin_sha256']
d.save('production_audit.json',row)
if len(sys.argv)>1 and sys.argv[1]=='audit':
    print(row['status'],{k:v['used'] for k,v in row['metrics'].items()},row['timing']);sys.exit(0)

logs={}
for name,expected in [('touch16_full.log',1),('polarity_recovery.log',1),('rtl_regression.log',3)]:
    s=read(here/name)
    passes=[line for line in s.splitlines() if line.startswith('PASS ')]
    assert len(passes)>=expected and 'FATAL:' not in s and 'simulation failed' not in s,(name,passes)
    logs[name]={'sha256':d.sha(here/name),'passes':passes}
full=read(here/'touch16_full.log')
keys=re.findall(r'KEY_SPECTRUM key=(\d+) amplitude=([\d.]+)',full)
assert [int(k) for k,a in keys]==list(range(1,17)),keys
logs['touch16_full.log']['spectrum_8192_samples']={k:float(a) for k,a in keys}
shutil.copy2(p/'sim/build/decoded_pcm_touch16.csv',here/'decoded_pcm_touch16.csv')
logs['touch16_full.log']['pcm_capture']={'path':'decoded_pcm_touch16.csv','sha256':d.sha(here/'decoded_pcm_touch16.csv')}
core=read(here/'app_core.log');app=read(here/'app_build.log')
assert 'PASS device controls:' in core and 'PASS TakeWorkflow:' in core and 'Exception:' not in core
assert "versionCode='26' versionName='1.25-touch16'" in app and 'Verifies' in app
for name in ('app_core.log','app_build.log'):
    logs[name]={'sha256':d.sha(here/name),'passes':[line for line in read(here/name).splitlines() if line.startswith('PASS ')]}
certs=[]
for name in ('old_apk_signature.log','new_apk_signature.log'):
    found=re.search(r'certificate SHA-256 digest: ([a-f0-9]+)',read(here/name));assert found,name
    certs.append(found[1])
assert certs[0]==certs[1]
d.save('functional_results.json',logs)
test_files=['sim/tb_top_touch16.v','sim/tb_top_touch16_recovery.v','sim/tb_hc05_extensions.v',
            'sim/tb_top_idle.v','sim/tb_top_dual_analog.v','sim/ttp229_model.v','sim/i2s_pcm_monitor.v','tools/run_sim.ps1']
d.save('test_inputs.json',{name:d.sha(p/name) for name in test_files})
d.save('resource_ledger.json',{'current':row['metrics'],'delta_vs_previous':row['delta_vs_baseline'],
    'remaining_after_minimum_known_future_reserve':{k:row['metrics'][k]['capacity']-row['metrics'][k]['used']-v
        for k,v in {'Logic':1650,'CLS':365,'BSRAM':4}.items()},
    'future_Register_DSP_reserves':'Not quantified; not assumed zero','three_effects_integrated':False})

release=p/'android_app/dist/FPGA-Music-Touch16-Code26.apk'
rolling=p/'android_app/dist/FPGA-Music-Unified.apk'
old_freeze=json.loads((here/'freeze.json').read_text(encoding='utf-8'))
assert d.sha(here/'previous_default/FPGA-Music-Unified-Code25.apk')==old_freeze['old_apk_sha256']
assert d.sha(here/'previous_default/pnr/PCM5102_UNIFIED.fs')==old_freeze['old_default_sha256']
if d.sha(rolling)!=d.sha(release):
    assert d.sha(rolling)==old_freeze['old_apk_sha256'],'Rolling APK changed outside this task'
    shutil.copy2(release,rolling)
new_side=release.with_suffix('.apk.idsig');old_side=rolling.with_suffix('.apk.idsig')
if new_side.exists():
    if old_side.exists() and not (here/'previous_default/rolling.apk.idsig').exists():shutil.copy2(old_side,here/'previous_default/rolling.apk.idsig')
    shutil.copy2(new_side,old_side)
elif old_side.exists():
    shutil.copy2(old_side,here/'previous_default/rolling.apk.idsig');old_side.unlink()
named_fs=here/'PCM5102_UNIFIED_touch16_20261026.fs'
shutil.copy2(p/'impl/pnr/PCM5102_UNIFIED.fs',named_fs)
artifacts={'default_fs':str(p/'impl/pnr/PCM5102_UNIFIED.fs'),'fs_sha256':d.sha(named_fs),
    'named_fs':str(named_fs),'apk':str(release),'rolling_apk':str(rolling),'apk_sha256':d.sha(release),
    'matching_signer_sha256':certs[0],'versionCode':26,'versionName':'1.25-touch16',
    'hardware_programmed':False,'phone_installed':False,'analog_audio_captured':False}
assert d.sha(rolling)==artifacts['apk_sha256']
d.save('artifacts.json',artifacts)
app_inputs=[]
for folder in ('android_app/app/src','android_app/core_test'):
    for f in sorted((p/folder).rglob('*')):
        if f.is_file():app_inputs.append({'path':f.relative_to(p).as_posix(),'sha256':d.sha(f)})
for name in ('android_app/app/build.gradle','android_app/build-apk.ps1','android_app/test-core.ps1'):
    app_inputs.append({'path':name,'sha256':d.sha(p/name)})
d.save('app_inputs.json',{'capture':'After successful build; application sources were unchanged since that build',
                         'files':app_inputs})
def num(v):return f'{v:g}'
gain={k:baseline['metrics'][k]['used']-v['used'] for k,v in row['metrics'].items()}
t=row['timing'];setup=t['setup_raw_worst_path']['slack_ns'];hold=t['hold_raw_worst_path']['slack_ns']
lines=['# 固定十六键生产交付（2026-10-26）','',
'已将去掉 TTP229 八键模式的方案接入生产 RTL，完成对应默认码流和 App v1.25-touch16 / Code26。保留旧默认构建与原滚动 Code25 APK，未烧录 FPGA、未安装手机、未做模拟音频对录。三效果原型未接入，既有回声/合唱仍按原实现工作。','',
'## 行为与实施','',
'- 上电固定十六键串行，删除两组旧 GPIO 读取/同步/去抖模块；十六个声部和后续混音保留。CTRL/CTRL2 模式字段恒为 1，TOUCH8 返回 ERR,RANGE；TOUCH16 保留就绪与空闲检查。K8 作为音符，压力用途由手机选择。',
'- 删除 SDC 中只指向旧 GPIO 同步器的两条 false_path，其余时钟及异步输入约束保留。',
'- 补上固定十六键后的极性恢复路径：原 SERIAL 写入也依赖键盘 ready，错误极性可导致无法更改；现在只对此命令取消 ready 要求，仍检查音符、曲谱、下载、录制和延音忙状态。其他编辑命令仍使用原 ready 门槛。',
'- App 删除模式选择、相关草稿绑定和生成 TOUCH8 的路径；删除旧 REC 日志的一键八键配置，保留历史日志查看/导出及手机 MIDI、板上 TAKE。仍回读真实设备状态，连接旧八键固件时明确提示更新。',
'- 最初尚未修正 SERIAL 恢复条件的中间构建/仿真被主动停止；日志及当时 PCM/VVP 保存在 intermediate_before_polarity_recovery，不计作通过。正式构建和以下测试全部基于修正后的源码。','',
'## 完整生产资源与时序','',
'| 资源 | 原生产 | 当前生产 | 净回收 | 剩余 |','|---|---:|---:|---:|---:|']
for k,v in row['metrics'].items():
    lines.append(f"| {k} | {num(baseline['metrics'][k]['used'])} | {num(v['used'])} | {num(gain[k])} | {num(v['capacity']-v['used'])} |")
lines += ['',f'相同 Gowin 二进制、50MHz、resource_sharing=1、retiming=1、place2/route0/maxfan23。未布通 {row["unrouted_nets"]}；setup/hold 违例端点 {t["setup_violated_endpoints"]}/{t["hold_violated_endpoints"]}，原始路径 WNS {setup:+.3f}/{hold:+.3f} ns。',
'最终净省 135 Logic、163 Register，CLS 比原生产增加 16，BSRAM/DSP 不变。本次接口变更已经完成，但没有获得 CLS 净回收，不能把它当作释放了 14 CLS 的方案。',
'当前结果包含 SERIAL 未就绪恢复修正，不能直接套用前轮仅删除八键的 197 Logic/14 CLS，或把不同组合的节省相加。尚未完成的 D/B2/E100 与安全垫仍按 1650 Logic/365 CLS/4 BSRAM 规划；本次只交付删除八键及必要恢复路径，不宣称完整三效果或后续预留已经满足。','',
'101 项生产源码/ROM/约束/工程/构建脚本在正式构建前后哈希一致；相对原生产只有 hc05_keymap.v、top.v、PCM5102_UNIFIED.sdc 三项变化。实际综合网表工程、cmd.do、device.cfg、资源报告、时序 HTML 和 timing_paths 指纹见 production_audit.json。','',
'## 验证','',
'- tb_top_touch16：真实 UART/TTP229 引脚、默认十六键、GPIO 隔离、按住和空闲时 TOUCH8 拒绝；全部十六个音高的 8192 样本 I2S 频谱，HOLD/PANIC、K16、远程压力用途、传感器重置后高有效配置、校准 BUSY 和就绪后重试。整条用例最终 PASS。频谱幅值记录在 functional_results.json，原始解码 PCM 独立保留。',
'- tb_top_touch16_recovery：传感器从上电即为高有效、FPGA 默认低有效，未就绪时通过真实 UART 接受 SERIAL1，恢复全部十六键，同时验证演奏忙时拒绝改变极性和 TOUCH8 拒绝。',
'- tb_hc05_extensions：47 个逐字节 UART 回复，覆盖未就绪恢复、音符/曲谱/录制忙保护、只读十六键状态、非法命令原子拒绝、旧音效/音量/模拟控制及 PANIC。',
'- tb_top_idle、tb_top_dual_analog：生产参数启动静默；压力与 ADS1115 滑杆同时作用及故障回退。全频谱用例 FSR 关闭、使用 500k UART、100µs 启动及短 ADSR；双模拟通道单独验证，未冒充全部传感器/Flash/回放联合实物验收。',
'- Android 完整核心测试、APK 构建、Code26 Manifest、签名验证通过，签名证书与原滚动 APK 相同。核心脚本读取的旧 RTL 录音夹具属于既有夹具，不称为本轮重新采集。手机 UI/蓝牙/模拟声音待实机验收。','',
'## 产物','',
f'- 默认码流：`impl/pnr/PCM5102_UNIFIED.fs`；独立副本：`reports/touch16_delivery_20261026/{named_fs.name}`。SHA256 `{artifacts["fs_sha256"]}`。',
f'- App：`android_app/dist/FPGA-Music-Touch16-Code26.apk`，滚动入口 `FPGA-Music-Unified.apk` 已同步。SHA256 `{artifacts["apk_sha256"]}`。',
'- 旧构建及 APK：`previous_default/`。当前操作与协议见 [TOUCH16.md](../../TOUCH16.md)。','',
'## 复现','',
'在 pcm5102_pam8403 目录执行；新实验请使用新报告路径，保留本轮证据。','',
'```powershell',
"& 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe' tools/build_unified.tcl",
'./tools/run_sim.ps1 -Tests tb_top_touch16',
'./tools/run_sim.ps1 -Tests tb_top_touch16_recovery,tb_hc05_extensions,tb_top_idle,tb_top_dual_analog',
'./android_app/test-core.ps1',
"./android_app/build-apk.ps1 -OutputApk 'dist/FPGA-Music-Touch16-Code26.apk'",
'```','',
'旧八键专用 GPIO/顶层回归和 sim/reference 冻结模型仍保留历史用途；本轮更新实际十六键入口及协议扩展回归，没有把旧参考同步改成新行为。','']
(here/'README.md').write_text('\n'.join(lines),encoding='utf-8')
verification=p/'VERIFICATION.md';data=verification.read_bytes()
marker='2026-10-26：固定十六键与 App Code26'
if marker.encode('utf-8') not in data:
    head,sep,tail=data.partition(b'\n')
    note=f'''\n## {marker}

生产删除 TTP229 八键 GPIO 输入，固定串行十六键；保留全部十六声部及现有效果。SERIAL 写入在读端未就绪但其他条件空闲时可用于极性恢复，其余忙保护保留。App 删除八键入口和旧日志一键配置，更新 v1.25-touch16 / Code26。

完整 PnR：Logic {num(row['metrics']['Logic']['used'])}、CLS {num(row['metrics']['CLS']['used'])}、Register {num(row['metrics']['Register']['used'])}、BSRAM {num(row['metrics']['BSRAM']['used'])}、DSP {num(row['metrics']['DSP']['used'])}；place2/route0/maxfan23，未布通0、setup/hold违例0/0，WNS {setup:+.3f}/{hold:+.3f} ns。101项输入构建前后不变。默认码流 SHA256 `{artifacts['fs_sha256']}`。

完整8192样本十六音高/控制/极性重配置测试、从上电极性不匹配恢复、47条UART扩展回复、静默、双模拟回归均通过。App核心测试、APK构建、Code26版本和签名验证通过，与原APK证书相同；滚动APK SHA256 `{artifacts['apk_sha256']}`。旧可用构建与实际滚动APK保留。

本轮未烧录、未安装手机或做模拟对录；未接入三效果原型。完整资源、快速参数/覆盖边界、产物和复现见 [交付报告](reports/touch16_delivery_20261026/README.md)；使用说明见 [固定十六键](TOUCH16.md)。

'''.encode('utf-8')
    verification.write_bytes(head+sep+note+tail)
evidence=['README.md','production_audit.json','production_inputs.json','functional_results.json','artifacts.json','app_inputs.json','freeze.json','test_inputs.json','resource_ledger.json','decoded_pcm_touch16.csv']
d.save('evidence_hashes.json',{name:d.sha(here/name) for name in evidence})
print('Final production validated; APK/bitstream published; report complete',gain,artifacts['fs_sha256'])
