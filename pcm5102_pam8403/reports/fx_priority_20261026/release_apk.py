from pathlib import Path
import hashlib,subprocess,json,re,shutil
H=Path(__file__).resolve().parent;A=H.parent.parent/'android_app'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
jar=next((A/'tools/sdk/build-tools').glob('*/lib/apksigner.jar'))
files=[H/'previous_Code26.apk',A/'dist/FPGA-Music-FX3-Code27.apk']
certs=[]
for n,file in enumerate(files):
    r=subprocess.run(['java','-jar',str(jar),'verify','--verbose','--print-certs',str(file)],capture_output=True,text=True)
    assert r.returncode==0
    (H/('previous_apk_certificate.txt' if n==0 else 'apk_certificate.txt')).write_text(r.stdout,encoding='utf-8')
    certs.append(re.search(r'certificate SHA-256 digest: ([a-f0-9]+)',r.stdout)[1].upper())
assert certs[0]==certs[1]=='CBECCBE6A3DF4025A0DC82103D6DFB98C80DE795887C8F31A8CEBEABD0362E26'
shutil.copy2(files[1],A/'dist/FPGA-Music-Unified.apk')
source=[]
for file in sorted(A.rglob('*')):
    if not file.is_file():continue
    n=file.relative_to(A).as_posix()
    if n.startswith(('app/src/','core_test/')) or n in ('app/build.gradle','build-apk.ps1','test-core.ps1'):
        source.append({'Path':n,'SHA256':sha(file)})
(H/'app_sources.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(H/'apk_release.json').write_text(json.dumps({'versionCode':27,'versionName':'1.26-fx3','sha256':sha(files[1]),'rolling_sha256':sha(A/'dist/FPGA-Music-Unified.apk'),'previous_sha256':sha(files[0]),'certificate_sha256':certs[1],'source_manifest_sha256':sha(H/'app_sources.json')},indent=2)+'\n')
print('Code27 APK and rolling alias identical; signature matches Code26; app sources frozen')
