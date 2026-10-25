from delivery import *
import re

versions={
    'python':sys.version,'python_executable':sys.executable,
    'gowin':'V1.9.11.03 Education (actual PnR report)',
    'gowin_executable_sha256':sha(GOWIN),
}
for name,command in {
    'iverilog':['C:/iverilog/bin/iverilog.exe','-V'],
    'vvp':['C:/iverilog/bin/vvp.exe','-V'],
    'windows_powershell':['powershell.exe','-NoProfile','-Command','$PSVersionTable.PSVersion.ToString()'],
}.items():
    r=subprocess.run(command,capture_output=True)
    output=(r.stdout+r.stderr).decode('utf-8',errors='replace')
    versions[name]=next((x for x in output.splitlines() if x.strip()),'unavailable')
write_json(HERE/'tool_versions.json',versions)
final=json.loads((HERE/'final_production_audit.json').read_text(encoding='utf-8'))
assert final['status']=='validated' and final['build_exit_code']==0
assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==final['bitstream_sha256']
frozen=json.loads((HERE/'base_inputs.json').read_text(encoding='utf-8'))
inputs=[r for r in frozen if r['Path'].startswith(('pcm5102_pam8403/src/','pmod_hub75e/src/'))
        or r['Path'] in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj','pcm5102_pam8403/tools/build_unified.tcl')]
differences=[r['Path'] for r in inputs if sha(REPO/r['Path'])!=r['SHA256']]
assert differences==['pcm5102_pam8403/src/apds9960_ctrl.v'],differences
recorded=json.loads((HERE/'final_inputs.json').read_text(encoding='utf-8'))
assert all(sha(REPO/r['Path'])==r['SHA256'] for r in recorded)
apk=PROJECT/'android_app/dist/FPGA-Music-Unified.apk'
freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
assert sha(apk)==freeze['previous_apk_sha256']
assert sha(HERE/'previous_default/pnr/PCM5102_UNIFIED.fs')==freeze['previous_default_fs_sha256']
for p in (HERE/'app_frozen').rglob('*'):
    if p.is_file():
        q=PROJECT/'android_app'/p.relative_to(HERE/'app_frozen')
        assert q.exists() and sha(p)==sha(q),f'App changed: {q}'
base_verification=(HERE/'base/pcm5102_pam8403/VERIFICATION.md').read_bytes()
current=(PROJECT/'VERIFICATION.md').read_bytes()
assert current.endswith(base_verification[base_verification.index(b'\n')+1:]),'Existing verification notes changed'
if (HERE/'evidence_hashes.json').exists():
    hashes=json.loads((HERE/'evidence_hashes.json').read_text(encoding='utf-8'))
    assert all(sha(HERE/p)==digest for p,digest in hashes.items()),'Report evidence changed'
print('PASS final bitstream, frozen-source delta, all final input hashes, preserved App/APK, old bitstream and verification history')
