"""Verify frozen inputs and signed artifacts before updating local rolling entries.
No programming, installation, serial communication or physical Flash operation.
"""
from work import *
import re, stat

def copy_generated(source, destination):
    # Gowin marks bitstreams read-only. Keep the source attributes after copying.
    source, destination = Path(source), Path(destination)
    if destination.exists():
        destination.chmod(stat.S_IREAD | stat.S_IWRITE)
    with source.open('rb') as source_file, destination.open('wb') as destination_file:
        shutil.copyfileobj(source_file, destination_file)
    shutil.copystat(source, destination)
    return destination
audits=json.loads((HERE/'build_audit.json').read_text(encoding='utf-8'))
assert audits['score_bend_alt']['status'] not in ('incomplete','synthesis_only')
d=audits['score_bend_alt']['can_integrate_resource_and_timing_only']
chosen='score_bend_alt' if d else 'base'
if d:assert (HERE/'score_app_integration.json').exists(),'Admitted hardware needs its phone adapter'
stage=json.loads((HERE/'latest_app_stage.json').read_text(encoding='utf-8'))
stage_root=Path(stage['directory']);apk=Path(stage['apk'])
assert sha(apk)==stage['apk_sha256']
for row in json.loads((stage_root/'sources_after.json').read_text(encoding='utf-8')):
    assert sha(PROJECT/'android_app'/row['Path'])==row['SHA256'],row['Path']
assert 'PASS local FX scenes' in (stage_root/'core.log').read_text(encoding='utf-8',errors='replace')
assert audits[chosen]['status']=='validated'
if chosen!='base':assert audits[chosen]['passes_35_CLS_reserve']
root=HERE/chosen;frozen=root/PROJECT.name
for row in json.loads((root/'sources.json').read_text(encoding='utf-8')):
    assert sha(root/row['Path'])==row['SHA256'],row['Path']
# Compare the production inputs first; changes are applied separately, never hidden here.
for row in json.loads((HERE/'base/sources.json').read_text(encoding='utf-8')):
    name=row['Path']
    if name.startswith('build_inputs/'):continue
    assert sha(REPO/name)==sha(root/name),'Production source differs from chosen frozen build: '+name
sdk=PROJECT/'android_app/tools/sdk/build-tools'
jar=next(p/'lib/apksigner.jar' for p in sorted(sdk.iterdir(),reverse=True) if (p/'lib/apksigner.jar').exists())
certs={}
for label,path in [('new',apk),('Code34',PROJECT/'android_app/dist/FPGA-Music-Stickers-Code34.apk'),('Code27',PROJECT/'android_app/dist/FPGA-Music-FX3-Code27.apk')]:
    result=subprocess.run(['java','-jar',str(jar),'verify','--print-certs',str(path)],capture_output=True,text=True,encoding='utf-8',errors='replace',check=True)
    (HERE/f'certificate_{label}.txt').write_text(result.stdout+result.stderr,encoding='utf-8')
    m=re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)',result.stdout);assert m,label
    certs[label]=m[1].upper()
assert len(set(certs.values()))==1,'Signing certificate mismatch'
before=HERE/'production_before_release'
if not before.exists():
    for folder in ('pnr','gwsynthesis'):
        shutil.copytree(PROJECT/'impl'/folder,before/'impl'/folder)
    shutil.copy2(PROJECT/'android_app/dist/FPGA-Music-Unified.apk',before/'previous_rolling.apk')
else:
    # Resume the first copy attempt without replacing its pre-release backup.
    assert sha(before/'impl/pnr/PCM5102_UNIFIED.fs')==sha(HERE/'previous_default.fs')
    assert sha(before/'previous_rolling.apk')==sha(HERE/'previous_default.apk')
    assert (before/'impl/gwsynthesis/PCM5102_UNIFIED.prj').exists()
subprocess.run(['pwsh','-NoProfile','-NonInteractive','-File',str(HERE/'prepare_output_copy.ps1'),str(PROJECT)],check=True)
fs=frozen/'impl/pnr/PCM5102_UNIFIED.fs';assert sha(fs)==audits[chosen]['bitstream_sha256']
named_fs=HERE/'PCM5102_UNIFIED_PERFORMANCE_20261026.fs';copy_generated(fs,named_fs)
for folder in ('pnr','gwsynthesis'):
    shutil.copytree(frozen/'impl'/folder,PROJECT/'impl'/folder,dirs_exist_ok=True,copy_function=copy_generated)
copy_generated(apk,PROJECT/'android_app/dist/FPGA-Music-Unified.apk')
output_hashes=[]
for folder in ('pnr','gwsynthesis'):
    for source in sorted((frozen/'impl'/folder).rglob('*')):
        if not source.is_file():continue
        relative=source.relative_to(frozen)
        digest=sha(source)
        assert sha(PROJECT/relative)==digest,str(relative)
        output_hashes.append({'Path':relative.as_posix(),'SHA256':digest})
save(HERE/'production_output_hashes.json',output_hashes)
assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==sha(fs)
assert sha(PROJECT/'android_app/dist/FPGA-Music-Unified.apk')==sha(apk)
artifacts={
    apk.name:{'path':str(apk),'sha256':sha(apk)},
    named_fs.name:{'path':str(named_fs),'sha256':sha(named_fs)},
    'rollback_Code34.apk':{'path':str(PROJECT/'android_app/dist/FPGA-Music-Stickers-Code34.apk'),'sha256':sha(PROJECT/'android_app/dist/FPGA-Music-Stickers-Code34.apk')},
    'rollback_Code27.apk':{'path':str(PROJECT/'android_app/dist/FPGA-Music-FX3-Code27.apk'),'sha256':sha(PROJECT/'android_app/dist/FPGA-Music-FX3-Code27.apk')},
    'rollback_FX3.fs':{'path':str(PROJECT/'reports/fx_priority_20261026/PCM5102_UNIFIED_FX3_20261026.fs'),'sha256':sha(PROJECT/'reports/fx_priority_20261026/PCM5102_UNIFIED_FX3_20261026.fs')},
    'previous_default.fs':{'path':str(HERE/'previous_default.fs'),'sha256':sha(HERE/'previous_default.fs')},
}
save(HERE/'release.json',{'app_version':f"{stage['version']} / Code{stage['code']}",'app_stage':{**stage,'staged_only':False,'rolling_entry_updated':True},
    'hardware_label':chosen,'hardware_resources':audits[chosen]['metrics'],'artifacts':artifacts,
    'same_signing_certificate':certs,'rolling_hashes_match':True,'installed':False,'programmed':False,'physical_flash_written':False,
    'source_snapshot':str(root/'sources.json'),'source_inputs_match_frozen_build':True,
    'output_snapshot':str(HERE/'production_output_hashes.json'),'copied_output_file_count':len(output_hashes),
    'bitstream_source':'validated frozen build; copied together with synthesis/PnR reports, not a new build in production path'})
# Keep the operation sheet and entry points on the actual released app version.
quick=PROJECT/'PERFORMANCE_QUICKSTART.md';text=quick.read_text(encoding='utf-8').replace('FPGA-Music-Performance-Code33.apk',apk.name)
quick.write_text(text,encoding='utf-8')
print('Verified certificates, sources and rolling hashes; released local artifacts only')
print(HERE/'release.json')
