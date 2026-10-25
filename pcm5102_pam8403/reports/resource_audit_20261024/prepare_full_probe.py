"""Freeze exactly the known-good build inputs, changing only APDS widths."""
from pathlib import Path
import hashlib
import json
import shutil

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
builds=PROJECT/'sim/build/unified'
base=builds/'engine_share_base_20261024'
target=builds/'resource_apds_width17_20261024'
target.mkdir(exist_ok=False)
manifest=json.loads((base/'sources.json').read_text(encoding='utf-8-sig'))
for row in manifest:
    relative=Path(row['Path'].replace('\\','/'))
    assert not relative.is_absolute() and '..' not in relative.parts
    source=base/relative
    assert hashlib.sha256(source.read_bytes()).hexdigest().upper()==row['SHA256'].upper(),relative
    dest=target/relative
    dest.parent.mkdir(exist_ok=True,parents=True)
    shutil.copyfile(source,dest)
changed='pcm5102_pam8403/src/apds9960_ctrl.v'
shutil.copyfile(HERE/'apds_candidate17/apds9960_ctrl.v',target/changed)
new_manifest=[]
differences=[]
for row in manifest:
    relative=row['Path'].replace('\\','/')
    sha=hashlib.sha256((target/relative).read_bytes()).hexdigest().upper()
    new_manifest.append({'Path':relative,'SHA256':sha})
    if sha!=row['SHA256'].upper():
        differences.append(relative)
assert differences==[changed],differences
(target/'sources.json').write_text(json.dumps(new_manifest,indent=2),encoding='utf-8')
(HERE/'full_probe_inputs.json').write_text(json.dumps({
    'baseline':str(base),'candidate':str(target),'changed_files':differences,
    'source_files_checked':len(manifest)},indent=2),encoding='utf-8')
print(target)
