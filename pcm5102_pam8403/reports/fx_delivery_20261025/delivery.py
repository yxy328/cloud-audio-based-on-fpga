"""Isolated, current-working-tree FX experiments. No production mutations."""
from pathlib import Path
import datetime, difflib, hashlib, importlib.util, json, shutil, subprocess, sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
REPO = PROJECT.parent
GOWIN = Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def write_json(p, data):
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def manifest(root):
    return [{'Path': p.relative_to(root).as_posix(), 'SHA256': sha(p)}
            for p in sorted(root.rglob('*')) if p.is_file() and 'sim/build/' not in p.relative_to(root).as_posix()
            and '/impl/' not in p.relative_to(root).as_posix()]

def prepare():
    target = HERE / 'base'
    if target.exists():
        raise RuntimeError('Frozen baseline already exists')
    project = target / PROJECT.name
    project.mkdir(parents=True)
    for folder in ('src', 'tools', 'sim'):
        shutil.copytree(PROJECT / folder, project / folder, ignore=shutil.ignore_patterns('build', '__pycache__'))
    for p in list(PROJECT.glob('*.gprj')) + list(PROJECT.glob('*.md')):
        shutil.copy2(p, project / p.name)
    shutil.copytree(REPO / 'pmod_hub75e' / 'src', target / 'pmod_hub75e' / 'src')
    shutil.copytree(REPO / 'pmod_hub75e' / 'sim', target / 'pmod_hub75e' / 'sim', ignore=shutil.ignore_patterns('build'))
    (project / 'impl').mkdir()
    (target / 'build_inputs').mkdir()
    for name in ('PCM5102_UNIFIED_process_config.json', 'project_process_config.json'):
        p = PROJECT / 'impl' / name
        if p.exists():
            shutil.copy2(p, project / 'impl' / name)
            shutil.copy2(p, target / 'build_inputs' / name)
    for filename, args in [('starting_status.txt', ['status', '--porcelain=v1']),
                           ('starting_diff.patch', ['diff', '--binary', 'HEAD']),
                           ('starting_head.txt', ['rev-parse', 'HEAD'])]:
        with (HERE / filename).open('wb') as f:
            subprocess.run(['git', '-C', str(REPO), *args], stdout=f, check=True)
    saved = HERE / 'previous_default'
    saved.mkdir()
    for folder in ('pnr', 'gwsynthesis'):
        if (PROJECT / 'impl' / folder).exists():
            shutil.copytree(PROJECT / 'impl' / folder, saved / folder)
    shutil.copytree(PROJECT / 'android_app', HERE / 'app_frozen',
                    ignore=shutil.ignore_patterns('build', '.gradle', 'dist', 'design', '*.apk', '*.idsig', '.git'))
    write_json(HERE / 'base_inputs.json', manifest(target))
    write_json(HERE / 'freeze.json', {
        'created_at': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        'source': str(PROJECT), 'baseline': str(target), 'includes_uncommitted_files': True,
        'gowin_executable': str(GOWIN), 'gowin_sha256': sha(GOWIN),
        'strategy': {'place': 2, 'route': 0, 'maxfan': 23, 'global_freq': 50, 'resource_sharing': 1, 'retiming': 1},
        'previous_default_fs_sha256': sha(PROJECT / 'impl/pnr/PCM5102_UNIFIED.fs'),
        'previous_apk_sha256': sha(PROJECT / 'android_app/dist/FPGA-Music-Unified.apk'),
        'hardware_tested': False,
    })
    print('Frozen', len(manifest(target)), 'files at', target)

def candidate(label):
    target = HERE / label
    if target.exists():
        raise RuntimeError('Candidate already exists')
    shutil.copytree(HERE / 'base', target, ignore=shutil.ignore_patterns('impl', 'build', 'sources.json', 'build.log', 'exit.json', '*.gprj.user'))
    project = target / PROJECT.name
    (project / 'impl').mkdir()
    return target

def apds():
    old = PROJECT / 'reports/local_reuse_place1_20261025'
    original = PROJECT / 'reports/local_reuse_20261025/baseline/pcm5102_pam8403/src/apds9960_ctrl.v'
    migrated = old / 'apds_serial_place1/pcm5102_pam8403/src/apds9960_ctrl.v'
    current = HERE / 'base/pcm5102_pam8403/src/apds9960_ctrl.v'
    if current.read_bytes() != original.read_bytes():
        raise RuntimeError('APDS differs from historical baseline; manual port required')
    target = candidate('apds')
    shutil.copy2(migrated, target / 'pcm5102_pam8403/src/apds9960_ctrl.v')
    write_json(HERE / 'apds_migration.json', {
        'current_equals_historical_baseline': True,
        'original_sha256': sha(original), 'current_sha256': sha(current),
        'candidate_sha256': sha(migrated),
        'changed_rtl': ['src/apds9960_ctrl.v'],
        'i2c_master_and_dual_analog_from_current_tree': True,
    })
    (HERE / 'apds.diff').write_text(''.join(difflib.unified_diff(
        current.read_text(encoding='utf-8-sig').splitlines(True),
        migrated.read_text(encoding='utf-8-sig').splitlines(True),
        fromfile='current/apds9960_ctrl.v', tofile='apds/apds9960_ctrl.v')), encoding='utf-8')
    fixtures = HERE / 'fixtures'
    fixtures.mkdir()
    shutil.copy2(PROJECT / 'reports/local_reuse_20261025/fixtures/tb_apds_scenarios.sv', fixtures)
    print('Verified APDS origin; migrated only its local arithmetic')

def simulate(label):
    project = HERE / label / PROJECT.name
    out = HERE / 'functional' / label
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    for name, defines in [('scenarios', []), ('guard', ['-DREALTIME'])]:
        compiled = out / (name + '.vvp')
        command = ['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', 'tb_apds_scenarios',
                   *defines, '-o', str(compiled), str(HERE / 'fixtures/tb_apds_scenarios.sv'),
                   'src/apds9960_ctrl.v']
        r = subprocess.run(command, cwd=project, capture_output=True, text=True)
        (out / (name + '_compile.log')).write_text(r.stdout + r.stderr, encoding='utf-8')
        if r.returncode: raise RuntimeError(r.stderr)
        with (out / (name + '.log')).open('w', encoding='utf-8') as f:
            r = subprocess.run(['C:/iverilog/bin/vvp.exe', str(compiled)], cwd=project, stdout=f, stderr=f)
        lines = (out / (name + '.log')).read_text().splitlines()
        results[name] = {'exit_code': r.returncode, 'pass': [x for x in lines if x.startswith('PASS')],
                         'guard': [x for x in lines if x.startswith('GUARD')]}
        write_json(out / 'results.json', results)
        if r.returncode or not results[name]['pass']: raise RuntimeError(f'{label} {name} failed')
    tests = ['tb_top_dual_analog', 'tb_ads1115_bus', 'tb_analog_expression',
             'tb_apds_nack', 'tb_i2c_master_bus', 'tb_top_idle']
    invocation = "& './tools/run_sim.ps1' -Tests @(" + ','.join("'"+t+"'" for t in tests) + ')'
    with (out / 'integration.log').open('w', encoding='utf-8') as f:
        r = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', invocation],
                           cwd=project, stdout=f, stderr=f)
    results['integration'] = {'exit_code': r.returncode, 'tests': tests}
    write_json(out / 'results.json', results)
    print(label, json.dumps(results))
    if r.returncode: raise RuntimeError('Integration regression failed')

def build(label):
    root = HERE / label
    project = root / PROJECT.name
    if (root / 'build.log').exists():
        raise RuntimeError('Build evidence already exists; use a new candidate label')
    write_json(root / 'sources.json', manifest(root))
    with (root / 'build.log').open('w', encoding='utf-8') as f:
        result = subprocess.run([str(GOWIN), str(project / 'tools/build_unified.tcl')],
                                cwd=project, stdout=f, stderr=subprocess.STDOUT)
    write_json(root / 'exit.json', {'returncode': result.returncode})
    print(label, 'build exit', result.returncode)
    sys.exit(result.returncode)

def audit(labels):
    spec = importlib.util.spec_from_file_location('fxaudit', PROJECT / 'tools/audit_fx_builds.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    info = mod.sources(HERE / 'base')
    base = mod.audit(HERE / 'base', info, {})
    rows = [base] + [mod.audit(HERE / l, info, base['metrics']) for l in labels if l != 'base']
    for row in rows:
        root=HERE/row['label'];project=root/PROJECT.name
        exit_path=root/'exit.json'
        if exit_path.exists():row['build_exit_code']=json.loads(exit_path.read_text())['returncode']
        if row.get('build_exit_code') and 'RP0006' in (root/'build.log').read_text(encoding='utf-8',errors='replace'):
            row['status']='synthesis_resource_exceeded'
        row['actual_build_file_hashes']={p.relative_to(root).as_posix():sha(p) for p in (
            project/'impl/gwsynthesis/PCM5102_UNIFIED.prj',project/'impl/pnr/cmd.do',
            project/'impl/gwsynthesis/PCM5102_UNIFIED.vg',project/'impl/pnr/device.cfg',
            project/'impl/pnr/PCM5102_UNIFIED.rpt.txt',
            project/'impl/pnr/PCM5102_UNIFIED_tr_content.html',project/'impl/pnr/PCM5102_UNIFIED.timing_paths',
            project/'impl/PCM5102_UNIFIED_process_config.json',project/'tools/build_unified.tcl') if p.exists()}
    write_json(HERE / 'build_audit.json', rows)
    for row in rows:
        timing = row['timing'] or {}
        print(row['label'], row['status'], {n: v['used'] for n, v in row['metrics'].items()},
              'delta', row['delta_vs_baseline'], 'unrouted', row['unrouted_nets'],
              'violations', timing.get('setup_violated_endpoints'), timing.get('hold_violated_endpoints'),
              'WNS', (timing.get('setup_raw_worst_path') or {}).get('slack_ns'),
              'changed', row['changed_inputs_vs_baseline'], 'corrupt', row['snapshot_corrupt_inputs'])
    comparison = {}
    for name in ('scenarios', 'guard'):
        paths = [HERE / 'functional' / l / (name + '.log') for l in ('base', 'apds')]
        if all(p.exists() for p in paths):
            traces = [[x for x in p.read_text().splitlines() if x.split(' ')[0] in
                       ('CMD', 'POLL', 'EVENT', 'ENDPOINT')] for p in paths]
            comparison[name] = {'semantic_records': len(traces[0]), 'equal': traces[0] == traces[1]}
            assert traces[0] == traces[1]
    write_json(HERE / 'apds_trace_comparison.json', comparison)

if __name__ == '__main__':
    if sys.argv[1] == 'prepare': prepare()
    elif sys.argv[1] == 'candidate': print(candidate(sys.argv[2]))
    elif sys.argv[1] == 'apds': apds()
    elif sys.argv[1] == 'sim': simulate(sys.argv[2])
    elif sys.argv[1] == 'build': build(sys.argv[2])
    elif sys.argv[1] == 'audit': audit(sys.argv[2:])
