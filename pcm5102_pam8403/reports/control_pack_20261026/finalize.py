"""Document the final admitted build, or explicitly retain the restored baseline."""
from work import *
import stat
freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
integrated=(HERE/'integration.json').exists()
record=json.loads((HERE/'integration.json').read_text(encoding='utf-8')) if integrated else None
if integrated:
    selected=json.loads((HERE/record['selected']/'audit.json').read_text(encoding='utf-8'))
    assert selected['status']=='validated' and record['net_cls_recovered']>0
    expected=record['production_inputs'];expected_fs=record['production_bitstream_sha256']
    assert all(sha(REPO/r['path'])==r['SHA256'] for r in record['outputs'])
    metrics=selected['metrics'];saving=record['net_cls_recovered']
else:
    selected=None;expected=freeze['production_inputs'];expected_fs=freeze['baseline_fs_sha256']
    metrics=freeze['baseline_audit']['metrics'];saving=0
assert all(sha(REPO/r['Path'])==r['SHA256'] for r in expected)
assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==expected_fs

# The current serial16 test has passed on unchanged baseline and candidates.
# Keep all original behavioral assertions when fixing the legacy GPIO fixture.
backup=HERE/'documentation_before';backup.mkdir(exist_ok=True)
fixture=PROJECT/'sim/tb_top_runtime_adsr.v'
fixture_source=HERE/'adsr_reset'/PROJECT.name/'sim/tb_top_runtime_adsr_serial_current.v'
fixture_text=fixture_source.read_text(encoding='utf-8').replace(
    'module tb_top_runtime_adsr_serial_current;', 'module tb_top_runtime_adsr;')
if not integrated:
    assert sha(fixture)==sha(HERE/'baseline'/PROJECT.name/'sim/tb_top_runtime_adsr.v')
    shutil.copy2(fixture,backup/'tb_top_runtime_adsr.v')
    fixture.write_text(fixture_text,encoding='utf-8',newline='\n')

margin=metrics['CLS']['capacity']-metrics['CLS']['used']
if integrated:
    timing=selected['timing']
    summary=(f"第三步净回收 {saving:g} CLS（11387→{metrics['CLS']['used']:g}），"
             f"当前 Logic {metrics['Logic']['used']:g}、BSRAM {metrics['BSRAM']['used']:g}、DSP {metrics['DSP']['used']:g}。"
             f"50MHz 未布通/时序违例均0，原始 setup/hold slack "
             f"{timing['setup_raw_worst_path']['slack_ns']:+.3f}/{timing['hold_raw_worst_path']['slack_ns']:+.3f} ns。"
             f"剩余 {margin:g} CLS，保留35后预算 {margin-35:g}。默认位流已更新。")
else:
    summary=("第三步已完成多组结构与物理实现对照，尚未找到满足净减CLS与时序要求的候选，均未接入。"
             "当前默认保持第一轮 HC-05 版本：Logic 22447、CLS 11387、BSRAM 53、DSP 26.5；"
             "剩余133 CLS，保留35后预算98。第三步新增收益为0。")
intro=("**2026-10-26 CLS 优先复核：[第三步实测、失败记录与回退](reports/control_pack_20261026/README.md)。** "
       "第二步增加77 CLS的显示方案已撤回，实验与命名位流保留。"+summary+
       "未烧录。以下资源和位流指纹为历史记录。\n\n")
readme=PROJECT/'README.md'
original=readme.read_text(encoding='utf-8')
assert 'reports/control_pack_20261026/README.md' not in original
shutil.copy2(readme,backup/'README.md')
first,rest=original.split('\n',1)
readme.write_text(first+'\n\n'+intro+rest.lstrip('\n'),encoding='utf-8')
verification=PROJECT/'VERIFICATION.md'
shutil.copy2(verification,backup/'VERIFICATION.md')
verification.write_text('# 2026-10-26 CLS 优先纠正与第三步\n\n'+intro+
    '原顶层 ADSR 回归仍以 GPIO 注入触摸，在当前固定串行16键工程下超时。已只将刺激改为 TTP229 串行模型，'
    '保留原包络、I2S 静音和扫描断言；未修改基线与候选均通过。此测试夹具修复不计资源收益。\n\n'+
    verification.read_text(encoding='utf-8'),encoding='utf-8')

# Compile the canonical public fixture after restoring its original module name.
rtl=list((PROJECT/'src').glob('*.v'))+[REPO/'pmod_hub75e/src/ttp229_gpio_input.v']
rtl += list((PROJECT/'sim').glob('*model*.v'))+[PROJECT/'sim/i2s_pcm_monitor.v']
with (HERE/'canonical_fixture_compile.log').open('w',encoding='utf-8') as log:
    p=subprocess.run([str(IVERILOG),'-g2001','-s','tb_top_runtime_adsr','-o',str(HERE/'canonical_fixture.vvp'),
                      str(fixture),*map(str,rtl)],cwd=PROJECT,stdout=log,stderr=log)
assert p.returncode==0,'Public fixture compilation failed'

# Keep the withdrawal explicit even after later builds replace the rollback target.
withdrawn=DISPLAY/'withdrawn.json'
payload=json.loads(withdrawn.read_text(encoding='utf-8'))
payload['rollback_target']='11387 CLS / 53 BSRAM, first HC-05 baseline'
payload['current_production_report']='../control_pack_20261026/README.md'
payload.pop('current_production',None);save(withdrawn,payload)
docs=[PROJECT/'README.md',PROJECT/'VERIFICATION.md',HERE/'README.md',HERE/'DESIGN.md']
checks={'selected':record['selected'] if integrated else None,'net_cls_recovered':saving,
        'production_input_count':len(expected),'production_inputs_match':all(sha(REPO/r['Path'])==r['SHA256'] for r in expected),
        'default_bitstream_sha256':sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs'),
        'default_bitstream_matches':sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==expected_fs,
        'tools_match':sha(GOWIN)==freeze['gowin_sha256'],'display_experiment_withdrawn':True,
        'canonical_test_fixture_sha256':sha(fixture),'canonical_test_compiles':True,
        'documentation_hashes':{str(p.relative_to(REPO)):sha(p) for p in docs},
        'all_selected_outputs_match':all(sha(REPO/r['path'])==r['SHA256'] for r in record['outputs']) if integrated else None,
        'burned_fpga':False}
assert checks['production_inputs_match'] and checks['default_bitstream_matches'] and checks['tools_match']
save(HERE/'final_check.json',checks)
print(json.dumps(checks,ensure_ascii=False,indent=2))
