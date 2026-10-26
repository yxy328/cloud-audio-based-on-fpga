"""Reject any candidate without a real, functionally validated CLS decrease."""
from work import *
import stat

def check_log(path):
    text=path.read_text(encoding='utf-8-sig',errors='replace') if path.exists() else ''
    return {'path':str(path.relative_to(HERE)),'SHA256':sha(path) if path.exists() else None,
            'pass_lines':re.findall(r'^PASS[^\r\n]*',text,re.M),
            'passed':bool(re.search(r'^PASS',text,re.M)) and not re.search(r'FATAL|error:',text)}

def verify(label,require_integration=False):
    root=HERE/label;project=root/PROJECT.name
    test_root=root
    if (root/'functional_reference.json').exists():
        reference=json.loads((root/'functional_reference.json').read_text(encoding='utf-8'))
        test_root=HERE/reference['parent']
        mine={r['Path']:r['SHA256'] for r in manifest(root)}
        parent={r['Path']:r['SHA256'] for r in manifest(test_root)}
        assert [p for p in mine if mine[p]!=parent[p]]==['pcm5102_pam8403/tools/build_unified.tcl']
        project=test_root/PROJECT.name
    if label.startswith('adsr'):
        tests=[check_log(test_root/'tests/tb_adsr_staging_equivalence.log')]
        names=['tb_runtime_adsr','tb_hc05_adsr','tb_top_runtime_adsr_serial_current']
    elif label.startswith('parser'):
        tests=[]
        if 'index' in label:tests.append(check_log(test_root/'tests/tb_reply_index_stress.log'))
        names=[r['test'] for r in json.loads((test_root/'differential_tests.json').read_text(encoding='utf-8'))
               if r['outputs_per_instance']==67]+['tb_performance_params','tb_top_runtime_adsr_serial_current']
    else:
        tests=[check_log(root/'map_decode.log')]
        names=[r['test'] for r in json.loads((root/'differential_tests.json').read_text(encoding='utf-8'))]+['tb_performance_params']
    if require_integration:names+=['tb_fx3_frame_take']
    tests += [check_log(project/'sim/build'/(name+'.log')) for name in names]
    if label.startswith(('adsr','parser')):
        tests.append(check_log(HERE/'baseline'/PROJECT.name/'sim/build/tb_top_runtime_adsr_serial_current.log'))
    save(root/'verification.json',{'all_passed':all(t['passed'] for t in tests),'checks':tests,
         'production_source_hashes':manifest(root),'includes_integration':require_integration})
    print(label,'checks',sum(t['passed'] for t in tests),'/',len(tests),flush=True)
    return tests

def integrate(label):
    root=HERE/label;project=root/PROJECT.name
    audit(label)
    result=json.loads((root/'audit.json').read_text(encoding='utf-8'))
    freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
    assert result['status']=='validated'
    assert result['metrics']['CLS']['used']<freeze['baseline_audit']['metrics']['CLS']['used'], 'No measured CLS saving'
    assert result['metrics']['CLS']['capacity']-result['metrics']['CLS']['used']>=35
    assert result['unrouted_nets']==0
    for kind in ('setup','hold'):
        assert result['timing'][kind+'_raw_worst_path'] is not None
        assert result['timing'][kind+'_raw_worst_path']['slack_ns']>=0
    tests=verify(label,True);assert all(t['passed'] for t in tests)
    assert manifest(root)==json.loads((root/'sources.json').read_text(encoding='utf-8'))
    assert json.loads((root/'exit.json').read_text(encoding='utf-8'))=={'returncode':0,'inputs_unchanged':True}
    assert sha(GOWIN)==freeze['gowin_sha256']
    assert all(sha(REPO/r['Path'])==r['SHA256'] for r in freeze['production_inputs']), 'Production drift'
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==freeze['baseline_fs_sha256']
    changed=result['changed_inputs_vs_baseline']
    expected=['pcm5102_pam8403/src/adsr_config.v'] if label.startswith('adsr') else (
        ['pcm5102_pam8403/src/hc05_keymap.v'] if label.startswith('parser') else ['pcm5102_pam8403/src/downloadable_song.v'])
    if (root/'functional_reference.json').exists():expected.append('pcm5102_pam8403/tools/build_unified.tcl')
    assert changed==expected,changed
    if label.startswith(('adsr','parser')):
        assert sha(PROJECT/'sim/tb_top_runtime_adsr.v')==sha(HERE/'baseline'/PROJECT.name/'sim/tb_top_runtime_adsr.v'), 'Production test fixture drift'
    backup=HERE/'production_before';assert not backup.exists()
    backup.mkdir()
    changes=[(root/p,REPO/p) for p in changed]
    for folder in ('gwsynthesis','pnr'):
        for p in sorted((project/'impl'/folder).glob('PCM5102_UNIFIED*')):
            if p.is_file():changes.append((p,PROJECT/'impl'/folder/p.name))
    changes += [(project/'impl/pnr'/p,PROJECT/'impl/pnr'/p) for p in ('cmd.do','device.cfg')]
    for src,dst in changes:
        saved=backup/dst.relative_to(REPO);saved.parent.mkdir(parents=True,exist_ok=True)
        if dst.exists():shutil.copy2(dst,saved)
    for src,dst in changes:
        if dst.exists():dst.chmod(dst.stat().st_mode|stat.S_IWRITE)
        shutil.copy2(src,dst);assert sha(src)==sha(dst)
    named=HERE/'PCM5102_UNIFIED_CONTROL_PACK_20261026.fs'
    shutil.copy2(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs',named)
    fixture_hash=None
    if label.startswith(('adsr','parser')):
        fixture=PROJECT/'sim/tb_top_runtime_adsr.v'
        shutil.copy2(fixture,backup/'tb_top_runtime_adsr.v')
        fixture_source=(HERE/'adsr_reset'/PROJECT.name/'sim/tb_top_runtime_adsr_serial_current.v')
        fixture.write_text(fixture_source.read_text(encoding='utf-8').replace(
            'module tb_top_runtime_adsr_serial_current;', 'module tb_top_runtime_adsr;'),encoding='utf-8',newline='\n')
        fixture_hash=sha(fixture)
    inputs=[{'Path':r['Path'],'SHA256':sha(REPO/r['Path'])} for r in freeze['production_inputs']]
    assert {r['Path']:r['SHA256'] for r in inputs}=={r['Path']:r['SHA256'] for r in manifest(root) if not r['Path'].startswith('build_inputs/')}
    save(HERE/'integration.json',{'selected':label,'production_changes':changed,'production_inputs':inputs,
        'production_bitstream_sha256':sha(named),'rollback_bitstream_sha256':freeze['baseline_fs_sha256'],
        'outputs':[{'path':str(dst.relative_to(REPO)),'SHA256':sha(dst)} for _,dst in changes],
        'net_cls_recovered':-result['delta_vs_baseline']['CLS'],'functional_checks':len(tests),
        'test_fixture_sha256':fixture_hash,
        'burned_fpga':False,'wrote_board_flash':False})
    print('Integrated',label,'net CLS saving',-result['delta_vs_baseline']['CLS'],flush=True)

if __name__=='__main__':
    if sys.argv[1]=='verify':verify(sys.argv[2],len(sys.argv)>3)
    elif sys.argv[1]=='integrate':integrate(sys.argv[2])
