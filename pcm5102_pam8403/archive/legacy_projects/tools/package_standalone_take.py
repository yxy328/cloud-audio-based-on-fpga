"""Freeze one build, then collect its matching source/tests/bitstream."""
import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'sim/build/take_release_final'
OUT = ROOT / '独立录放_完整工程'
TOOLS = ['build_take.tcl', 'pnr_take.tcl', 'run_sim.ps1', 'run_take_sim.ps1',
         'run_recording_tests.ps1', 'check_take_layout.py']
TESTS = ['tb_performance_take', 'tb_take_atomic', 'tb_take_key_control', 'tb_take_spi_guard',
         'tb_take_nor_store', 'tb_hc05_take', 'tb_top_take', 'tb_hub75e_status',
         'tb_hc05_extensions', 'tb_hc05_download', 'tb_touch_tdm_synth',
         'tb_gesture_external_control', 'tb_tdm_take_equivalence']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def prepare():
    assert not SNAPSHOT.exists(), 'An immutable build snapshot already exists'
    SNAPSHOT.mkdir(parents=True)
    for folder in ['src', 'sim', 'sim/reference']:
        for source in (ROOT / folder).glob('*'):
            if source.is_file():
                copy(source, SNAPSHOT / folder / source.name)
    project = ET.parse(ROOT / 'PCM5102_EVENT_TAKE.gprj')
    for node in project.findall('.//File'):
        source = (ROOT / node.attrib['path']).resolve()
        assert source.is_file(), source
        if node.attrib['path'].startswith('../'):
            relative = 'src/' + source.name
            copy(source, SNAPSHOT / relative)
            node.set('path', relative)
    project.write(SNAPSHOT / 'PCM5102_EVENT_TAKE.gprj', encoding='utf-8', xml_declaration=True)
    for name in TOOLS:
        copy(ROOT / 'tools' / name, SNAPSHOT / 'tools' / name)
    script = SNAPSHOT / 'tools/run_sim.ps1'
    text = script.read_text(encoding='utf-8-sig')
    text = text.replace('../pmod_hub75e/src/ttp229_gpio_input.v', 'src/ttp229_gpio_input.v')
    text = text.replace('../pmod_hub75e/sim/tb_ttp229_gpio_input.v', 'sim/tb_ttp229_gpio_input.v')
    script.write_text(text, encoding='utf-8')
    copy(ROOT.parent / 'pmod_hub75e/sim/tb_ttp229_gpio_input.v', SNAPSHOT / 'sim/tb_ttp229_gpio_input.v')
    copy(ROOT / 'impl/PCM5102_EVENT_TAKE_process_config.json', SNAPSHOT / 'impl/PCM5102_EVENT_TAKE_process_config.json')
    manifest = {p.relative_to(SNAPSHOT).as_posix(): sha(p) for p in sorted(SNAPSHOT.rglob('*')) if p.is_file()}
    (SNAPSHOT / 'SOURCE_SHA256.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'snapshot': str(SNAPSHOT), 'files': len(manifest)}, ensure_ascii=False))


def finalize():
    profile_path = SNAPSHOT / 'RELEASE_PROFILE.json'
    profile = json.loads(profile_path.read_text()) if profile_path.is_file() else {
        'prefix': 'PCM5102_EVENT_TAKE', 'place_option': 0, 'route_option': 0, 'log': 'build.log'}
    prefix = profile['prefix']
    manifest = json.loads((SNAPSHOT / 'SOURCE_SHA256.json').read_text(encoding='utf-8'))
    for relative, expected in manifest.items():
        if not relative.startswith('impl/'):
            assert sha(SNAPSHOT / relative) == expected, f'Changed source: {relative}'
    logs = []
    for test in TESTS:
        log = (SNAPSHOT / f'sim/build/{test}.log').read_text(encoding='utf-8-sig')
        assert 'PASS' in log and 'FATAL:' not in log, test
        logs.append(test + '\n' + log)
    pnr = SNAPSHOT / 'impl/pnr'
    timing = (pnr / f'{prefix}_tr_content.html').read_text(encoding='utf-8')
    for check in ['Numbers of Setup Violated Endpoints', 'Numbers of Hold Violated Endpoints']:
        assert re.search(re.escape(check) + r'</td>\s*<td>0</td>', timing), check
    fmax = re.search(r'<td>clk</td>\s*<td>50\.000\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)', timing)
    assert fmax and float(fmax[1]) >= 50
    slack = re.search(r'<td class="label">Slack</td>\s*<td>([-\d.]+)</td>', timing)
    assert slack and float(slack[1]) >= 0
    resource = (pnr / f'{prefix}.rpt.txt').read_text(encoding='utf-8')
    logic = re.search(r'Logic\s*\|\s*(\d+)/23040', resource)[1]
    registers = re.search(r'Register\s*\|\s*(\d+)/23280', resource)[1]
    bsram = re.search(r'BSRAM\s*\|\s*(\d+)/56', resource)[1]
    cls = re.search(r'CLS\s*\|\s*(\d+)/11520', resource)[1]
    bitstream = pnr / f'{prefix}.fs'
    spec = importlib.util.spec_from_file_location('take_layout', SNAPSHOT / 'tools/check_take_layout.py')
    layout = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(layout)
    image = layout.inspect_bitstream(bitstream)
    hex_lines = (SNAPSHOT / 'sim/build/take_nor_slot.hex').read_text().splitlines()
    region = bytes(int(word, 16) for line in hex_lines if not line.startswith('//') for word in line.split())
    independent_crc = layout.inspect_slot(region[:8192])
    assert independent_crc['committed'] and independent_crc['crc32_computed'] == independent_crc['crc32_stored'] == '623FB7CE'
    logs.append('Independent Python binascii.crc32 PASS\n' + json.dumps(independent_crc, indent=2))
    assert not OUT.exists(), 'Do not overwrite an existing delivery'
    OUT.mkdir()
    for relative in manifest:
        copy(SNAPSHOT / relative, OUT / relative)
    copy(bitstream, OUT / 'FINAL_EVENT_RECORDER.fs')
    copy(pnr / f'{prefix}.rpt.txt', OUT / '验证/资源报告.txt')
    copy(pnr / f'{prefix}_tr_content.html', OUT / '验证/时序报告.html')
    copy(SNAPSHOT / f'impl/gwsynthesis/{prefix}_syn_rsc.xml', OUT / '验证/综合资源.xml')
    copy(SNAPSHOT / profile['log'], OUT / '验证/构建日志.txt')
    # Make the chosen successful placement explicit for future full builds.
    build_script = OUT / 'tools/build_take.tcl'
    text = build_script.read_text(encoding='utf-8')
    text = text.replace('    run all',
        f"    set_option -place_option {profile['place_option']} -route_option {profile['route_option']}\n    run all")
    build_script.write_text(text, encoding='utf-8')
    config_path = OUT / 'impl/PCM5102_EVENT_TAKE_process_config.json'
    config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    assert config['MULTIBOOT_MODE'] == 'Single' and int(config['MULTIBOOT_SPI_FLASH_ADDRESS'], 16) == 0
    assert float(config['Global_Freq']) == 50 and config['MSPI'] and not config['JTAG']
    config['Place_Option'] = str(profile['place_option'])
    config['Route_Option'] = str(profile['route_option'])
    config_path.write_text(json.dumps(config, indent=2), encoding='utf-8')
    (OUT / 'SOURCE_SHA256.json').write_text(json.dumps(
        {relative: sha(OUT / relative) for relative in manifest}, indent=2), encoding='utf-8')
    (OUT / '验证/仿真记录.txt').write_text('\n\n'.join(logs), encoding='utf-8')
    values = {'SHA256': image['sha256'], 'PAYLOAD': str(image['configuration_payload_bytes']),
              'LOGIC': logic, 'REGISTERS': registers, 'BSRAM': bsram, 'CLS': cls,
              'FMAX': fmax[1], 'SLACK': slack[1]}
    doc = (ROOT / 'RECORD_PLAYBACK.md').read_text(encoding='utf-8')
    for key, value in values.items():
        doc = doc.replace('{{' + key + '}}', value)
    assert '{{' not in doc, 'Unresolved release metadata'
    (OUT / '完整说明.md').write_text(doc, encoding='utf-8')
    (ROOT / 'RECORD_PLAYBACK.md').write_text(doc, encoding='utf-8')
    (OUT / '构建指纹.json').write_text(json.dumps({**values, 'image_range': image,
        'hardware_verified': False, 'tests': TESTS, 'placement_profile': profile}, ensure_ascii=False, indent=2), encoding='utf-8')
    sums = [sha(p) + '  ' + p.relative_to(OUT).as_posix() for p in sorted(OUT.rglob('*')) if p.is_file()]
    (OUT / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='utf-8')
    archive = ROOT / '独立录放_完整工程.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.rglob('*')):
            if p.is_file():
                z.write(p, OUT.name + '/' + p.relative_to(OUT).as_posix())
    assert len(list(OUT.rglob('*.fs'))) == 1
    print(json.dumps({'directory': str(OUT), 'archive': str(archive), **values}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['prepare', 'finalize'])
    (prepare if parser.parse_args().operation == 'prepare' else finalize)()
