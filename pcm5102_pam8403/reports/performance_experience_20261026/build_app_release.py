"""Build a named app stage; never installs or changes the rolling APK here."""
from work import *
import re
app=PROJECT/'android_app'
def app_manifest():
    paths=[p for p in (app/'app').rglob('*') if p.is_file()]
    paths += [app/name for name in ('test-core.ps1','build-apk.ps1','app/build.gradle')]
    return [{'Path':p.relative_to(app).as_posix(),'SHA256':sha(p)} for p in sorted(paths)]
manifest=app/'app/src/main/AndroidManifest.xml';gradle=app/'app/build.gradle'
ms=manifest.read_text(encoding='utf-8-sig');gs=gradle.read_text(encoding='utf-8-sig')
codes=[int(re.search(r'android:versionCode="(\d+)"',ms)[1]),int(re.search(r'versionCode (\d+)',gs)[1])]
codes += [int(m[1]) for p in (app/'dist').glob('*Code*.apk') if (m:=re.search(r'Code(\d+)\.apk$',p.name))]
retry=len(sys.argv)>1 and sys.argv[1]=='retry'
code=int(sys.argv[2]) if retry else max(codes)+1
version=f'1.{code-1}-performance';stage=HERE/f'app_code{code}'
if retry:
    before=json.loads((stage/'sources_before.json').read_text(encoding='utf-8'))
    assert before==app_manifest(),'Source drift while recovering build host failure'
    shutil.copy2(app/f'dist/FPGA-Music-Performance-Code{code}.apk',stage/'first_signed_before_shell_fix.apk')
else:
    stage.mkdir();save(stage/'previous_versions.json',{'manifest':ms,'gradle':gs})
    ms=re.sub(r'android:versionCode="\d+"',f'android:versionCode="{code}"',ms)
    ms=re.sub(r'android:versionName="[^"]+"',f'android:versionName="{version}"',ms)
    gs=re.sub(r'versionCode \d+',f'versionCode {code}',gs);gs=re.sub(r"versionName '[^']+'",f"versionName '{version}'",gs)
    manifest.write_text(ms,encoding='utf-8');gradle.write_text(gs,encoding='utf-8')
    before=app_manifest();save(stage/'sources_before.json',before)
steps=[('core.log',['-File',str(app/'test-core.ps1')]),
                  ('apk_build.log',['-File',str(app/'build-apk.ps1'),'-OutputApk',f'dist/FPGA-Music-Performance-Code{code}.apk'])]
if retry:steps=steps[1:]
for name,args in steps:
    if retry:name='apk_build_pwsh.log'
    with (stage/name).open('wb') as log:
        result=subprocess.run(['pwsh','-NoProfile','-ExecutionPolicy','Bypass',*args],cwd=app,stdout=log,stderr=log)
    assert result.returncode==0,(name,(stage/name).read_text(encoding='utf-8',errors='replace')[-3000:])
after=app_manifest();save(stage/'sources_after.json',after);assert before==after,'Sources changed during build; do not release this APK'
apk=app/f'dist/FPGA-Music-Performance-Code{code}.apk'
shutil.copytree(app/'app',stage/'app_sources')
save(stage/'result.json',{'code':code,'version':version,'apk':str(apk),'apk_sha256':sha(apk),
    'source_inputs_unchanged':True,'installed':False,'staged_only':True})
save(HERE/'latest_app_stage.json',{'directory':str(stage),**json.loads((stage/'result.json').read_text(encoding='utf-8'))})
print((stage/'result.json').read_text(encoding='utf-8'))
