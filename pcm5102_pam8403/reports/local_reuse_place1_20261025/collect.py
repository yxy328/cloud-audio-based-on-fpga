from pathlib import Path
import hashlib,json,re,importlib.util,xml.etree.ElementTree as ET
H=Path(__file__).resolve().parent
P=H.parents[1]; ROOT=P.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def dump(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
spec=importlib.util.spec_from_file_location('audit_helpers',H/'audit_helpers.py')
A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A)
freeze=json.loads((H/'freeze.json').read_text(encoding='utf-8'))
original=P/'sim/build/unified/engine_share_base_20261024'
orig_sources=A.sources(original);assert not orig_sources['corrupt']
orig_audit=A.audit(original,orig_sources,{})
base_sources=A.sources(H/'baseline_place1');assert not base_sources['corrupt']
base=A.audit(H/'baseline_place1',base_sources,orig_audit['metrics'])
builds=[]
for name,f in freeze['builds'].items():
    dst=H/name;src=Path(f['origin'])
    si=A.sources(dst);assert not si['corrupt']
    assert si['entries']==A.sources(src)['entries'],name
    record=A.audit(dst,base_sources,base['metrics'])
    record['delta_vs_place0_same_rtl']={}
    prior=A.audit(src,A.sources(src),{})
    for k,v in record['metrics'].items():
        if k in prior['metrics']:record['delta_vs_place0_same_rtl'][k]=v['used']-prior['metrics'][k]['used']
    record['delta_vs_verified_place0_baseline']={k:v['used']-orig_audit['metrics'][k]['used'] for k,v in record['metrics'].items()}
    record['production_integrated']=False
    record['configuration_checks']={}
    for rel in ['impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do','impl/pnr/device.cfg']:
        x=src/'pcm5102_pam8403'/rel;y=dst/'pcm5102_pam8403'/rel
        if not x.exists() or not y.exists():continue
        def norm(p,root):
            text=A.read_text(p).replace('\\','/').replace(str(root).replace('\\','/'),'<snapshot>')
            return re.sub(r'-place_option [01]\b','-place_option <tested>',text).strip()
        same=norm(x,src)==norm(y,dst)
        record['configuration_checks'][rel]={'matches_except_paths_and_tested_place_option':same,'prior_sha256':sha(x),'new_sha256':sha(y)}
        assert same,(name,rel)
    sx=src/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml'
    sy=dst/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml'
    vx=src/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED.vg'
    vy=dst/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED.vg'
    same_xml=ET.tostring(ET.parse(sx).getroot())==ET.tostring(ET.parse(sy).getroot())
    record['synthesis']={'auto_reran':'GowinSynthesis start' in A.read_text(dst/'pnr.log'),
      'prior_netlist_sha256':sha(vx),'new_netlist_sha256':sha(vy),
      'same_netlist_bytes':sha(vx)==sha(vy),'same_hierarchical_resource_xml':same_xml,
      'note':'The .vg is encrypted. Identical source and synthesis options plus equal resource XML do not prove byte-identical or formally equivalent netlists.'}
    record['meets_500_cls_target_vs_place1_baseline']=record['status']=='validated' and base['status']=='validated' and record['delta_vs_baseline'].get('CLS',0)<=-500
    builds.append(record)
drift=[]
for row in json.loads((H/'production_before.json').read_text(encoding='utf-8')):
    p=ROOT/row['Path']; after=sha(p) if p.exists() else None
    if after!=row['SHA256']:drift.append({'Path':row['Path'],'before':row['SHA256'],'after':after})
dump(H/'production_after_check.json',{'changed_since_start':drift,'writes_by_this_experiment':'Only this report directory.'})
dump(H/'build_audit.json',{'baseline_place0':orig_audit,'baseline_place1_status':base['status'],'builds':builds,'production_drift':drift})
def wns(b):
    t=b['timing']
    if b['status']=='routing_failed':return '不可验收'
    if not t or not t.get('setup_worst_path') or not t.get('hold_worst_path'):return '未提供'
    return f"{t['setup_worst_path']['slack_ns']:+.3f}/{t['hold_worst_path']['slack_ns']:+.3f}"
table='| 构建 | Logic | CLS | Register | BSRAM | DSP | 未布线 | setup/hold WNS ns | 状态 |\n|---|---:|---:|---:|---:|---:|---:|---|---|\n'
for b in [orig_audit]+builds:
    vals=[str(b['metrics'].get(k,{}).get('used','—')).removesuffix('.0') for k in A.METRICS]
    table+='| '+' | '.join([b['label']]+vals+[str(b['unrouted_nets']),wns(b),b['status']])+' |\n'
incomplete=any(b['status']=='incomplete' for b in builds)
valid=[b for b in builds[1:] if b['status']=='validated']
if incomplete:lead='place 1 重试仍在运行；未完成构建不可据此验收。'
elif valid:
    best=min(valid,key=lambda b:b['metrics']['CLS']['used'])
    reduction=-best['delta_vs_baseline']['CLS']
    logic=-best['delta_vs_baseline']['Logic']
    lead=f"{best['label']} 在 place1 下完整布线且时序通过；相对同策略基线净少 {reduction:g} CLS、{logic:g} Logic。500 CLS 目标{'已达到' if reduction>=500 else '尚未达到'}，未接入生产。"
else:lead='place 1 重试没有产生布线且时序通过的新增候选；失败构建的 CLS 下降不计交付收益。'
hashes=''
for b in builds:
    for filename,values in b['changed_input_hashes'].items():hashes+=f"| {b['label']} | {filename} | `{values['baseline']}` | `{values['candidate']}` |\n"
deltas=''
for b in builds:
    d=b['delta_vs_baseline'];dp=b['delta_vs_place0_same_rtl']
    deltas+=f"- `{b['label']}`：相对本轮 place1 基线 " + ('、'.join(f'{k} {v:+g}' for k,v in d.items()) or '尚无完整数据')
    deltas+='；相对相同 RTL 的 place0 '+'、'.join(f'{k} {v:+g}' for k,v in dp.items())+'。\n'
text=f'''# 冻结资源候选 place 1 重试，2026-10-25

**{lead}**

{table}
{deltas}
本轮按用户要求将 place_option 改为 1，保留 route_option=0、route_maxfan=23、global_freq=50、resource_sharing=1、retiming=1。器件与工具沿用 GW5A-LV25MG121NC1/I0、Gowin V1.9.11.03 Education。三组各自重新校验原冻结的 98 项输入，源文件未改，APDS 与 Flash 候选互不叠加。baseline_place1 是原 engine_share_base_20261024 的同条件对照。

## 流程与比较边界

初始复制原综合网表并调用 run pnr；Gowin 在新目录自动补跑综合。因此本报告按“相同冻结源码、相同综合参数、place 1 重建”记录，不能称为只消费了旧综合网表。加密 .vg 的输出哈希与层级资源 XML 对比均保留在 build_audit.json。无法通过去除明文注释证明加密网表内部逐字节等价；资源 XML 相同也不能替代形式等价。实际 .prj、cmd.do、device.cfg 均与相同 RTL 的 place0 构建对比，除路径与已改变的 place_option 外不应存在其他配置差异。

本轮只改物理实现设置；功能证据沿用 [上一轮功能记录](../local_reuse_20261025/functional_results.json) 与 [位宽、周期预算及边界](../local_reuse_20261025/design_notes.md)。未将既有失败候选的局部综合节省计为交付收益。APDS 最大新增 768 拍（15.36µs），Flash 每次元数据处理新增 5 拍（100ns）；这些行为变化没有因 place 1 而消失。

## 源文件完整 SHA256

| 构建 | 与 place1 基线不同的源文件 | 基线 SHA256 | 候选 SHA256 |
|---|---|---|---|
{hashes}
每个 sources.json 保存全部 98 项源输入；freeze.json 保存起始网表、脚本和工具哈希。PnR 最终实际消费网表的哈希及综合是否自动重跑单列在 build_audit.json。候选位流如有产生仅存于实验目录，其 SHA256 和时序违例端点同时记录；没有覆盖交付位流、发布 APK、烧录或接入生产。

状态必须分开理解：validated 仅表示此冻结构建资源报告、完整布线和 setup/hold 检查通过；是否净回收 500 CLS 由 meets_500_cls_target_vs_place1_baseline 标识；必要集成回归与生产接入不因布线通过而自动完成。当前生产接入数为 0。

APDS 相对原已验证 place0 基线 CLS 少 111，其中基线自身改为 place1 已少 16；同 place1 条件的 RTL 净下降是 95，不能将 111 全部算为 RTL 优化收益。第一阶段 500 CLS 目标尚未达到，本轮按用户要求只验证 place1 的布局布线；未追加整套长回归、未把此前功能初筛表述为生产接入验收。

本次实际调用各冻结目录的 `pcm5102_pam8403/tools/pnr_only.tcl`（place1/route0/fanout23）。原 build_unified.tcl 保留为原始哈希输入，其中 place0 不用于本次位流；后续重现请使用 pnr_only.tcl，并在新输出目录重建，避免覆盖现有证据。执行过程详见 [execution_notes.md](execution_notes.md)。

[机器可读审计](build_audit.json) · [输入冻结](freeze.json) · [生产树并发漂移](production_after_check.json)
'''
(H/'README.md').write_text(text,encoding='utf-8')
(H/'build_audit.md').write_text(lead+'\n\n'+table+'\n'+deltas,encoding='utf-8')
for b in builds:print(b['label'],b['status'],{k:v['used'] for k,v in b['metrics'].items()},'unrouted',b['unrouted_nets'],'WNS',wns(b),'same resource XML',b['synthesis']['same_hierarchical_resource_xml'])
manifest={str(p.relative_to(H)).replace('\\','/'):sha(p) for p in H.rglob('*') if p.is_file() and p.name!='evidence_hashes.json' and '__pycache__' not in p.parts and p.suffix in ['.json','.md','.py','.tcl'] and 'impl' not in p.parts}
dump(H/'evidence_hashes.json',manifest)
