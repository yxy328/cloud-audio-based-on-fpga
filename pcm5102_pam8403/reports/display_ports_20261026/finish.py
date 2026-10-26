"""Collect immutable evidence and integrate only a fully validated candidate."""
from work import *
import stat
import xml.etree.ElementTree as ET

DISPLAY_TESTS=['tb_hub75e_ram_equivalence','tb_hub75e_window_raster','tb_hub75e_audio_display',
               'tb_hub75e_status','tb_display_window_differential','tb_display_window_differential64']
INTEGRATION_TESTS=['tb_top_touch16_recovery','tb_fx3_frame_take','tb_fx3_replay_decode','tb_fx_take_atomic_528']

def collect(label):
    root=HERE/label
    project=root/PROJECT.name
    test_root=root
    functional_reference=None
    if (root/'functional_reference.json').exists():
        functional_reference=json.loads((root/'functional_reference.json').read_text(encoding='utf-8'))
        test_root=HERE/functional_reference['parent']
        mine={r['Path']:r['SHA256'] for r in manifest(root)}
        parent={r['Path']:r['SHA256'] for r in manifest(test_root)}
        assert [p for p in mine if mine[p]!=parent[p]]==['pcm5102_pam8403/tools/build_unified.tcl']
        assert sha(project/'src/hub75e_rhythm_display.v')==functional_reference['display_sha256']
    freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
    tests=[]
    for name in DISPLAY_TESTS+INTEGRATION_TESTS:
        folder=test_root/'tests' if name in DISPLAY_TESTS else test_root/PROJECT.name/'sim/build'
        files=([folder/(name+'.log')] if (folder/(name+'.log')).exists() else [])+list(folder.glob(name+'.attempt*.log'))
        files=sorted(files,key=lambda p:p.stat().st_mtime_ns)
        assert files, name
        log=files[-1];content=log.read_text(encoding='utf-8-sig',errors='replace')
        tests.append({'name':name,'log':str(log.relative_to(HERE)),'log_sha256':sha(log),
                      'pass_lines':re.findall(r'^PASS[^\r\n]*',content,re.M),
                      'passed':bool(re.search(r'^PASS',content,re.M)) and not re.search(r'FATAL|error:',content)})
    assert len(tests)==10 and all(t['passed'] for t in tests), tests
    assert manifest(root)==json.loads((root/'sources.json').read_text(encoding='utf-8'))
    assert sha(GOWIN)==freeze['gowin_sha256']
    audit(label)
    result=json.loads((root/'audit.json').read_text(encoding='utf-8'))
    pnr=project/'impl/pnr'
    required=['PCM5102_UNIFIED.rpt.txt','PCM5102_UNIFIED_tr_content.html',
              'PCM5102_UNIFIED.timing_paths','cmd.do','device.cfg']
    result['actual_build_file_hashes']={name:sha(pnr/name) for name in required if (pnr/name).exists()}
    result['actual_build_file_hashes']['synthesis.prj']=sha(project/'impl/gwsynthesis/PCM5102_UNIFIED.prj')
    def syn_options(path):
        return {e.attrib.get('type'):e.attrib.get('value') for e in ET.parse(path).iter()
                if e.tag=='Option' and e.attrib.get('type')!='output_file'}
    actual_options=syn_options(project/'impl/gwsynthesis/PCM5102_UNIFIED.prj')
    baseline_options=syn_options(HERE/'production_before/impl/gwsynthesis/PCM5102_UNIFIED.prj')
    result['synthesis_option_delta_vs_baseline']={k:[baseline_options.get(k),actual_options.get(k)]
         for k in set(actual_options)|set(baseline_options) if actual_options.get(k)!=baseline_options.get(k)}
    assert not result['synthesis_option_delta_vs_baseline'], result['synthesis_option_delta_vs_baseline']
    result['actual_synthesis_options']=actual_options
    result['tool_hashes']={p.name:sha(p) for p in (GOWIN,GOWIN.with_name('GowinSynthesis.exe'),IVERILOG,VVP)}
    def hierarchy(path):
        element=next(e for e in ET.parse(path).iter() if e.attrib.get('name')=='u_guide_display')
        return dict(element.attrib)
    result['display_hierarchy']={
        'baseline':hierarchy(HERE/'production_before/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml'),
        'candidate':hierarchy(project/'impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml')}
    save(root/'audit.json',result)
    benches=[HERE/(name+'.v') if (HERE/(name+'.v')).exists() else test_root/PROJECT.name/'sim'/(name+'.v')
             for name in DISPLAY_TESTS+INTEGRATION_TESTS]
    helpers=[HERE/p for p in ('work.py','finish.py','prepare_tests.py','window_ports.vfrag')]
    save(root/'verification.json',{'all_passed':True,'checks':tests,
         'display_sha256':sha(project/'src/hub75e_rhythm_display.v'),
         'reference_sha256':sha(HERE/'baseline'/PROJECT.name/'src/hub75e_rhythm_display.v'),
         'functional_reference':functional_reference,
         'harness_hashes':{str(p.relative_to(HERE)):sha(p) for p in benches+helpers},
         'comparison':'cycle-by-cycle pins, note_ready, overflow, snapshot, 64 logical rows and six tap values; simulation, not formal proof'})
    print('Verified',len(tests),'functional checks',flush=True)
    return result

def integrate(label):
    result=collect(label)
    root=HERE/label
    freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
    assert result['status']=='validated',result['status']
    assert result['metrics']['CLS']['used']<freeze['baseline_audit']['metrics']['CLS']['used'], 'CLS-first admission: a RAM saving alone is insufficient'
    assert result['unrouted_nets']==0
    assert result['metrics']['BSRAM']['used']<=freeze['baseline_audit']['metrics']['BSRAM']['used']-4
    assert result['metrics']['CLS']['capacity']-result['metrics']['CLS']['used']>=35
    allowed=['pcm5102_pam8403/src/hub75e_rhythm_display.v']
    if (root/'functional_reference.json').exists():allowed.append('pcm5102_pam8403/tools/build_unified.tcl')
    assert result['changed_inputs_vs_baseline']==allowed
    assert json.loads((root/'exit.json').read_text(encoding='utf-8'))=={'returncode':0,'inputs_unchanged':True}
    assert all(sha(REPO/r['Path'])==r['SHA256'] for r in freeze['production_inputs']), 'Production drift'
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==freeze['baseline_fs_sha256']
    assert sha(PROJECT/'sim/tb_hub75e_rhythm_display.v')==sha(HERE/'baseline'/PROJECT.name/'sim/tb_hub75e_rhythm_display.v'), 'Production test fixture drift'
    changes=[(root/PROJECT.name/'src/hub75e_rhythm_display.v',PROJECT/'src/hub75e_rhythm_display.v')]
    if len(allowed)>1:
        shutil.copy2(PROJECT/'tools/build_unified.tcl',HERE/'production_before/build_unified.tcl')
        changes.append((root/PROJECT.name/'tools/build_unified.tcl',PROJECT/'tools/build_unified.tcl'))
    for folder in ('gwsynthesis','pnr'):
        for path in sorted((root/PROJECT.name/'impl'/folder).glob('PCM5102_UNIFIED*')):
            if path.is_file():changes.append((path,PROJECT/'impl'/folder/path.name))
    changes += [(root/PROJECT.name/'impl/pnr'/name,PROJECT/'impl/pnr'/name) for name in ('cmd.do','device.cfg')]
    assert sha(HERE/'production_before/impl/pnr/PCM5102_UNIFIED.fs')==freeze['baseline_fs_sha256']
    assert sha(HERE/'production_before/hub75e_rhythm_display.v')==next(
        r['SHA256'] for r in freeze['production_inputs'] if r['Path'].endswith('/hub75e_rhythm_display.v'))
    for src,dst in changes:
        if dst.exists():dst.chmod(dst.stat().st_mode|stat.S_IWRITE)
        shutil.copy2(src,dst)
        assert sha(src)==sha(dst)
    named=HERE/'PCM5102_UNIFIED_DISPLAY_PORTS_20261026.fs'
    assert not named.exists()
    shutil.copy2(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs',named)
    # Update the architecture-specific test fixture while preserving its name
    # and all original externally observable checks.
    bench=PROJECT/'sim/tb_hub75e_rhythm_display.v'
    shutil.copy2(bench,HERE/'production_before/tb_hub75e_rhythm_display.v')
    text=(HERE/'tb_hub75e_window_raster.v').read_text(encoding='utf-8').replace(
        'module tb_hub75e_window_raster;', 'module tb_hub75e_rhythm_display;')
    bench.write_text(text,encoding='utf-8',newline='\n')
    inputs=[{'Path':r['Path'],'SHA256':sha(REPO/r['Path'])} for r in freeze['production_inputs']]
    assert {r['Path']:r['SHA256'] for r in inputs}=={r['Path']:r['SHA256'] for r in manifest(root) if not r['Path'].startswith('build_inputs/')}
    save(HERE/'integration.json',{'selected':label,'production_inputs':inputs,'checks':10,
         'production_changes':allowed+['pcm5102_pam8403/sim/tb_hub75e_rhythm_display.v'],
         'production_bitstream_sha256':sha(named),'rollback_bitstream_sha256':freeze['baseline_fs_sha256'],
         'outputs':[{'path':str(dst.relative_to(REPO)),'SHA256':sha(dst)} for _,dst in changes],
         'test_fixture_sha256':sha(bench),'burned_fpga':False,'wrote_board_flash':False})
    print('Integrated',label,'with',len(changes),'verified outputs',flush=True)

if __name__=='__main__':
    if sys.argv[1]=='collect':collect(sys.argv[2])
    elif sys.argv[1]=='integrate':integrate(sys.argv[2])
