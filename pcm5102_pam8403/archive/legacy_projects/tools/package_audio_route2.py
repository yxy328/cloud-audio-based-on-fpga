"""Freeze a reviewable source tree; package only a tested, timing-clean audio build."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAP = ROOT / 'sim/build/audio_route2_release_v1'
PROJECT = SNAP / 'pcm5102_pam8403'
OUT = ROOT / 'deliveries/HC05_AUDIO_ROUTE2_20261020'
TARGET = 'PCM5102_AUDIO_TAKE'
TESTS = ['tb_audio_take_safety', 'tb_top_flash_audio', 'tb_top_hc05_only',
         'tb_hc05_audio_record', 'tb_take_spi_guard', 'tb_touch_tdm_synth']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def prepare():
    assert not SNAP.exists(), 'Never overwrite an existing frozen snapshot'
    SNAP.mkdir(parents=True)
    for directory in ['src', 'sim/reference', 'tools', 'android_app/app/src/main',
                      'android_app/core_test', 'android_app/gradle', 'android_app/samples', 'android_app/third_party']:
        for source in (ROOT / directory).rglob('*'):
            if source.is_file() and '__pycache__' not in source.parts:
                copy(source, PROJECT / source.relative_to(ROOT))
    for source in (ROOT / 'sim').glob('*.v'):
        copy(source, PROJECT / source.relative_to(ROOT))
    for source in ROOT.glob('*'):
        if source.is_file() and source.suffix in ['.md', '.gprj']:
            copy(source, PROJECT / source.name)
    for source in (ROOT / 'android_app').glob('*'):
        if source.is_file() and (source.suffix in ['.md', '.ps1', '.gradle', '.bat'] or source.name == 'gradlew'):
            copy(source, PROJECT / 'android_app' / source.name)
    for relative in ['pmod_hub75e/src/ttp229_gpio_input.v', 'pmod_hub75e/sim/tb_ttp229_gpio_input.v']:
        copy(ROOT.parent / relative, SNAP / relative)
    config = ROOT / f'impl/{TARGET}_process_config.json'
    if config.is_file():
        copy(config, PROJECT / config.relative_to(ROOT))
        copy(config, SNAP / 'build_inputs' / config.name)
    inputs = {p.relative_to(SNAP).as_posix(): sha(p) for p in sorted(SNAP.rglob('*'))
              if p.is_file() and '/impl/' not in p.relative_to(SNAP).as_posix()}
    dump(SNAP / 'SOURCE_INPUTS.json', inputs)
    # Reuse local debug signing identity for an installable update. This key is
    # deliberately absent from both the source manifest and delivered archives.
    copy(ROOT / 'android_app/tools/debug.keystore', PROJECT / 'android_app/tools/debug.keystore')
    print(json.dumps({'snapshot_project': str(PROJECT), 'source_files': len(inputs)}, ensure_ascii=False))


def finalize():
    inputs = json.loads((SNAP / 'SOURCE_INPUTS.json').read_text(encoding='utf-8'))
    for relative, expected in inputs.items():
        if '/impl/' not in relative:
            assert sha(SNAP / relative) == expected, 'Changed frozen input: ' + relative
    pnr = PROJECT / 'impl/pnr'
    timing = (pnr / f'{TARGET}_tr_content.html').read_text(encoding='utf-8')
    for key in ['Numbers of Setup Violated Endpoints', 'Numbers of Hold Violated Endpoints']:
        assert re.search(re.escape(key) + r'</td>\s*<td>0</td>', timing), key
    frequency = re.search(r'<td>clk</td>\s*<td>50\.000\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)', timing)
    assert frequency and float(frequency[1]) >= 50
    slack = re.search(r'<td class="label">Slack</td>\s*<td>([-\d.]+)</td>', timing)
    assert slack and float(slack[1]) >= 0
    resource = (pnr / f'{TARGET}.rpt.txt').read_text(encoding='utf-8')
    metrics = {name: int(re.search(r'\b' + name + r'\s*\|\s*(\d+)/', resource)[1])
               for name in ['Logic', 'CLS', 'BSRAM', 'Register']}
    app_log = (PROJECT / 'release-tests.log').read_text(encoding='utf-8-sig', errors='replace')
    for assertion in ['PASS SppAudio:', 'PASS Flash -> HC05 FAR1 -> Java WAV:', 'PASS AudioRecording:']:
        assert assertion in app_log, assertion
    for name in TESTS:
        log = (PROJECT / f'sim/build/{name}.log').read_text(encoding='utf-8-sig', errors='replace')
        assert 'PASS' in log and 'FATAL' not in log, name
    spec = importlib.util.spec_from_file_location('audio_layout', PROJECT / 'tools/check_audio_take_layout.py')
    layout = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(layout)
    image = layout.inspect_image(pnr / f'{TARGET}.fs')
    fixture = (PROJECT / 'sim/build/audio_take_slot.hex').read_text().splitlines()
    data = bytes(int(v, 16) for line in fixture if not line.startswith('//') for v in line.split() if not v.startswith('@'))
    oracle = layout.inspect_slot(data, divisor=65535, maximum=1525)
    assert oracle['committed'] and oracle['samples'] == 1525, oracle
    apk = PROJECT / 'android_app/dist/FPGA-HC05-Audio-Route2.apk'
    assert apk.is_file() and 'Verifies' in (PROJECT / 'release-apk.log').read_text(errors='replace')
    assert not OUT.exists(), 'Never overwrite a delivery'
    OUT.mkdir(parents=True)
    copy(pnr / f'{TARGET}.fs', OUT / f'{TARGET}.fs')
    copy(apk, OUT / apk.name)
    copy(PROJECT / 'HC05_AUDIO_ROUTE2.md', OUT / 'README.md')
    copy(SNAP / 'SOURCE_INPUTS.json', OUT / 'SOURCE_INPUTS.json')
    for name in TESTS:
        copy(PROJECT / f'sim/build/{name}.log', OUT / f'verification/{name}.log')
    for source in pnr.glob(TARGET + '*'):
        if source.suffix in ['.html', '.txt']:
            copy(source, OUT / 'verification/pnr' / source.name)
    for name in ['release-build.log', 'release-tests.log', 'release-apk.log']:
        copy(PROJECT / name, OUT / 'verification' / name)
    for name in ['audio_flash_top.bin', 'audio_flash_top_expected.txt', 'audio_flash_from_top.wav', 'audio_take_slot.hex']:
        copy(PROJECT / 'sim/build' / name, OUT / 'verification' / name)
    source_zip = OUT / 'HC05_AUDIO_ROUTE2_sources.zip'
    with zipfile.ZipFile(source_zip, 'w', zipfile.ZIP_DEFLATED) as z:
        for relative in sorted(inputs):
            if '/impl/' not in relative:
                z.write(SNAP / relative, relative)
        z.write(SNAP / 'SOURCE_INPUTS.json', 'SOURCE_INPUTS.json')
    report = {'target': TARGET, 'status': 'EXPERIMENTAL_HARDWARE_ACCEPTANCE_PENDING',
              'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'resources_pnr': metrics, 'fmax_mhz': float(frequency[1]), 'worst_setup_slack_ns': float(slack[1]),
              'setup_violated_endpoints': 0, 'hold_violated_endpoints': 0,
              'bitstream': image, 'apk_sha256': sha(apk), 'source_files': len(inputs),
              'independent_python_crc32': oracle,
              'rtl': 'PASS; see logs; top UART accelerated only in simulation',
              'app': 'PASS JVM/FAR1/WAV/SPP mocks and APK build/signature; no physical phone tests',
              'hardware': 'NOT_RUN; no automatic programming; actual Flash/HC05/phone still pending',
              'gate_level_audio': 'NOT_RUN',
              'signing_key_in_archive': False, 'sdk_in_archive': False}
    dump(OUT / 'RELEASE.json', report)
    hashes = {p.relative_to(OUT).as_posix(): sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()}
    dump(OUT / 'SHA256.json', hashes)
    archive = OUT.with_suffix('.zip')
    assert not archive.exists()
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for source in sorted(OUT.rglob('*')):
            if source.is_file():
                z.write(source, OUT.name + '/' + source.relative_to(OUT).as_posix())
    print(json.dumps({'delivery': str(OUT), 'archive': str(archive), 'archive_sha256': sha(archive), **report}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['prepare', 'finalize'])
    args = p.parse_args()
    prepare() if args.action == 'prepare' else finalize()
