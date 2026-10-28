"""Verify the frozen 50 MHz candidate, test logs and artifact fingerprints."""
from pathlib import Path
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
FROZEN = PROJECT / 'sim/build/unified/score256_46e/pcm5102_pam8403'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    pnr = FROZEN / 'impl/pnr'
    report = (pnr / 'PCM5102_UNIFIED.rpt.txt').read_text(errors='replace')
    resources = {}
    for name in ['Logic', 'CLS', 'Register', 'BSRAM', 'DSP']:
        match = re.search(r'^\s*' + name + r'\s*\|\s*(\d+)/(\d+)', report, re.M)
        assert match, name
        used, total = map(int, match.groups())
        assert used <= total, name
        resources[name] = dict(used=used, total=total)
    assert resources['BSRAM']['used'] == 54
    assert resources['DSP']['used'] == 25
    timing = (pnr / 'PCM5102_UNIFIED_tr_content.html').read_text(errors='replace')
    for kind in ['Setup', 'Hold']:
        violations = re.search(r'Numbers of ' + kind + r' Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert violations and int(violations[1]) == 0, kind + ' timing violations'
    slacks = {}
    for kind in ['Setup', 'Hold']:
        section = timing.split(f'name="{kind}_Slack_Table"', 1)[1].split('</table>', 1)[0]
        values = re.findall(r'<td>\d+</td>\s*<td>([-\d.]+)</td>', section)
        assert values and min(map(float, values)) >= 0
        slacks[kind] = min(map(float, values))
    frozen_files = list((FROZEN / 'src').iterdir())
    for file in frozen_files:
        if file.is_file():
            assert sha(file) == sha(PROJECT / 'src' / file.name), file.name
    for log, minimum in [('unit_rtl.log', 5), ('integration_rtl.log', 10),
                         ('uart256.log', 1), ('routed_scan.log', 1)]:
        text = (HERE / log).read_text(errors='replace')
        assert 'FATAL' not in text and len(re.findall(r'^PASS', text, re.M)) >= minimum, log
    assert 'PASS SongLibrary: 85496 assertions' in (HERE / 'core_tests.log').read_text(errors='replace')
    assert 'hashes identical' in (HERE / 'library_reproducibility.log').read_text(errors='replace')
    assert 'cycle-exact reference' in (HERE / 'spectrum_equivalence.log').read_text(errors='replace')
    assert "versionCode='46'" in (HERE / 'apk_build.log').read_text(errors='replace')
    apk = PROJECT / 'android_app/dist/FPGA-Music-Score256-Code46.apk'
    bitstream = pnr / 'PCM5102_UNIFIED.fs'
    assert apk.stat().st_size > 1000000 and bitstream.stat().st_size > 100000
    data = dict(date='2026-10-28', label='score256_46e', app_version_code=46,
                app_version_name='1.45-score256', max_events=256, target_mhz=50,
                resources=resources, remaining_cls=resources['CLS']['total']-resources['CLS']['used'],
                setup_slack_ns=slacks['Setup'], hold_slack_ns=slacks['Hold'],
                setup_violations=0, hold_violations=0,
                score_bsram=2, source_files_match_frozen=sum(f.is_file() for f in frozen_files),
                apk_sha256=sha(apk), bitstream_sha256=sha(bitstream),
                library=json.loads((HERE / 'library_delta.json').read_text()),
                rtl_tests='PASS', app_core='PASS', routed_scan='PASS',
                phone_installed=False, fpga_programmed=False)
    (HERE / 'release.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(data, indent=2))


if __name__ == '__main__':
    main()
