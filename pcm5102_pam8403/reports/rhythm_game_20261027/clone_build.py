from pathlib import Path
import shutil,sys,json,hashlib
root=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403/sim/build/unified'
source=root/sys.argv[1];target=root/sys.argv[2]
assert source.parent==root and target.parent==root and not target.exists()
shutil.copytree(source,target,ignore=shutil.ignore_patterns('pnr','temp','*.log'))
for entry in json.loads((target/'sources.json').read_text(encoding='utf-8-sig')):
    assert hashlib.sha256((target/entry['Path']).read_bytes()).hexdigest().upper()==entry['SHA256']
(target/'parent_experiment.txt').write_text(str(source),encoding='utf-8')
print(target)
