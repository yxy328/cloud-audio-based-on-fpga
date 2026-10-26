"""Freeze this working tree and build isolated, independently accounted candidates."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
REPO = PROJECT.parent
GOWIN = Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def save(p, value): p.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def manifest(root):
    return [{'Path': p.relative_to(root).as_posix(), 'SHA256': sha(p)}
            for folder in ('pcm5102_pam8403/src', 'pmod_hub75e/src', 'build_inputs')
            for p in sorted((root/folder).rglob('*')) if p.is_file()] + [
            {'Path': name, 'SHA256': sha(root/name)} for name in
            ('pcm5102_pam8403/PCM5102_UNIFIED.gprj', 'pcm5102_pam8403/tools/build_unified.tcl')]

def prepare():
    assert not (HERE/'base').exists(), 'Never overwrite frozen inputs'
    prior = PROJECT/'reports/fx_priority_20261026'
    expected = json.loads((prior/'production_inputs.json').read_text(encoding='utf-8-sig'))
    drift = [r['Path'] for r in expected if sha(REPO/r['Path']) != r['SHA256']]
    audit = json.loads((prior/'production_audit.json').read_text(encoding='utf-8-sig'))
    artifact_drift = [name for name, digest in audit['actual_build_file_hashes'].items()
                      if sha(PROJECT/name) != digest]
    base = HERE/'base'
    for folder in ('src', 'tools', 'sim'):
        shutil.copytree(PROJECT/folder, base/PROJECT.name/folder,
                        ignore=shutil.ignore_patterns('build', '__pycache__'))
    shutil.copy2(PROJECT/'PCM5102_UNIFIED.gprj', base/PROJECT.name/'PCM5102_UNIFIED.gprj')
    shutil.copytree(REPO/'pmod_hub75e/src', base/'pmod_hub75e/src')
    (base/'build_inputs').mkdir()
    for name in ('PCM5102_UNIFIED_process_config.json', 'project_process_config.json'):
        shutil.copy2(PROJECT/'impl'/name, base/'build_inputs'/name)
    shutil.copytree(PROJECT/'android_app/app', HERE/'app_before/app')
    for name in ('test-core.ps1', 'build-apk.ps1'):
        shutil.copy2(PROJECT/'android_app'/name, HERE/'app_before'/name)
    shutil.copy2(PROJECT/'android_app/dist/FPGA-Music-Unified.apk', HERE/'previous_default.apk')
    shutil.copy2(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs', HERE/'previous_default.fs')
    save(base/'sources.json', manifest(base))
    for name, args in [('starting_status.txt', ['status', '--porcelain=v1']),
                       ('starting_diff.patch', ['diff', '--binary', 'HEAD'])]:
        with (HERE/name).open('wb') as f:
            subprocess.run(['git', '-C', str(REPO), *args], stdout=f, check=True)
    save(HERE/'baseline_check.json', {
        'production_input_count': len(expected), 'source_drift': drift,
        'actual_build_file_drift': artifact_drift,
        'bitstream_matches': sha(HERE/'previous_default.fs') == audit['bitstream_sha256'],
        'gowin_matches': sha(GOWIN) == audit['gowin_sha256'],
        'previous_apk_sha256': sha(HERE/'previous_default.apk'),
        'previous_fs_sha256': sha(HERE/'previous_default.fs'),
        'metrics': audit['metrics'], 'safety_CLS': 35,
        'current_manifest_version': '1.31-iconback / Code32',
        'prior_gradle_version_stale': '1.26-fx3 / Code27'})
    print((HERE/'baseline_check.json').read_text(encoding='utf-8'))

def candidate(label, source='base'):
    target = HERE/label
    assert not target.exists()
    shutil.copytree(HERE/source, target, ignore=shutil.ignore_patterns('impl', 'sources.json', '*.log', 'exit.json'))
    return target

def build(label):
    root = HERE/label
    assert not (root/'build.log').exists()
    save(root/'sources.json', manifest(root))
    with (root/'build.log').open('w', encoding='utf-8') as log:
        result = subprocess.run([str(GOWIN), str(root/PROJECT.name/'tools/build_unified.tcl')],
                                cwd=root/PROJECT.name, stdout=log, stderr=log)
    save(root/'exit.json', {'returncode': result.returncode,
        'inputs_unchanged': manifest(root) == json.loads((root/'sources.json').read_text(encoding='utf-8'))})
    print(label, 'exit', result.returncode)

if __name__ == '__main__':
    if sys.argv[1] == 'prepare': prepare()
    elif sys.argv[1] == 'apds':
        target = candidate('apds_reuse')
        source = PROJECT/'reports/local_reuse_20261025/apds_serial/pcm5102_pam8403/src/apds9960_ctrl.v'
        assert sha(source) == '4AAA3F1F0E20BFFFB35B49567427ED0054B972D9167F98C5337A3E69FDC77492'
        shutil.copy2(source, target/PROJECT.name/'src/apds9960_ctrl.v')
        build('apds_reuse')
    elif sys.argv[1] == 'build': build(sys.argv[2])
