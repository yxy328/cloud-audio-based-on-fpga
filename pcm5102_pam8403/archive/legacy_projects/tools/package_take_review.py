"""Collect one self-contained review project, deliberately without any .fs."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[1]
out = root / '录制回放_开发验证'
out.mkdir(exist_ok=True)

def copy(source, relative):
    target = out / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)

project = ET.parse(root / 'PCM5102_EVENT_TAKE.gprj')
for node in project.findall('.//File'):
    relative = node.attrib['path']
    source = (root / relative).resolve()
    assert source.is_file(), source
    if relative.startswith('../'):
        relative = 'src/' + source.name
        node.set('path', relative)
    copy(source, relative)
project.write(out / 'PCM5102_EVENT_TAKE.gprj', encoding='utf-8', xml_declaration=True)

# Include simulator helper RTL omitted from the production file list.
for source in (root / 'src').glob('*.v'):
    copy(source, 'src/' + source.name)
for source in (root / 'sim').glob('*.v'):
    copy(source, 'sim/' + source.name)
copy(root.parent / 'pmod_hub75e/sim/tb_ttp229_gpio_input.v', 'sim/tb_ttp229_gpio_input.v')
for name in ['build_take.tcl', 'run_sim.ps1', 'run_take_sim.ps1']:
    copy(root / 'tools' / name, 'tools/' + name)
script = out / 'tools/run_sim.ps1'
text = script.read_text(encoding='utf-8-sig').replace('../pmod_hub75e/src/ttp229_gpio_input.v', 'src/ttp229_gpio_input.v')
text = text.replace('../pmod_hub75e/sim/tb_ttp229_gpio_input.v', 'sim/tb_ttp229_gpio_input.v')
script.write_text(text, encoding='utf-8')
copy(root / 'impl/PCM5102_EVENT_TAKE_process_config.json', 'impl/project_process_config.json')
copy(root / 'RECORD_PLAYBACK.md', '说明.md')
copy(root / 'android_app/dist/FPGA-Event-Take-preview.apk', 'FPGA-Event-Take-preview.apk')

# All App sources/assets and licenses, without SDKs, caches or signing keys.
for folder in ['app/src', 'core_test', 'third_party']:
    for source in (root / 'android_app' / folder).rglob('*'):
        if source.is_file():
            copy(source, 'android_app/' + source.relative_to(root / 'android_app').as_posix())
for name in ['app/build.gradle', 'build.gradle', 'settings.gradle', 'build-apk.ps1', 'test-core.ps1', 'prepare-sdk.ps1']:
    source = root / 'android_app' / name
    if source.is_file():
        copy(source, 'android_app/' + name)

logs = ['tb_performance_take.log', 'tb_take_nor_store_final.log', 'tb_hc05_take.log', 'tb_top_take.log',
        'tb_hc05_extensions.log', 'tb_hc05_download.log', 'tb_hub75e_status.log',
        'tb_touch_tdm_synth.log', 'tb_gesture_external_control.log',
        'take_build_no_sharing.log', 'take_build_sharing.log', 'take_build_50mhz.log']
parts = []
for name in logs:
    source = root / 'sim/build' / name
    if source.is_file():
        value = source.read_text(encoding='utf-8-sig', errors='replace')
        if name.startswith('take_build'):
            value = '\n'.join(value.splitlines()[-18:])
        parts.append(name + '\n' + value)
(out / '验证记录.txt').write_text('\n\n'.join(parts), encoding='utf-8')

# Verify that the collected project requires no sibling directory.
for node in project.findall('.//File'):
    assert (out / node.attrib['path']).is_file()
cst = (out / 'src/PCM5102_EVENT_TAKE.cst').read_text(encoding='utf-8-sig')
pins = re.findall(r'IO_LOC\s+"[^"]+"\s+(\w+);', cst)
assert len(pins) == len(set(pins)), 'Duplicated FPGA ball assignment'
assert not list(out.rglob('*.fs')), 'Never package an unrelated bitstream'
checksums = []
for source in sorted(out.rglob('*')):
    if source.is_file() and source.name != 'SHA256SUMS.txt':
        checksums.append(hashlib.sha256(source.read_bytes()).hexdigest() + '  ' + source.relative_to(out).as_posix())
(out / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='utf-8')
archive = root / '录制回放_开发验证.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for source in sorted(out.rglob('*')):
        if source.is_file():
            z.write(source, out.name + '/' + source.relative_to(out).as_posix())
print(json.dumps({'archive': str(archive), 'files': len(checksums), 'bytes': archive.stat().st_size,
                  'bitstreams': 0, 'status': 'DEVELOPMENT_ONLY_RESOURCE_FIT_FAILED'}, ensure_ascii=False))
