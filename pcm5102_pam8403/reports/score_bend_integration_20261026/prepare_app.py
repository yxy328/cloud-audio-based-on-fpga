"""Stage the existing score CSV adapter against the user's current artwork/UI."""
from work import *

source=(PRIOR/'integrate_score_app.py').read_text(encoding='utf-8')
source=source[source.index("app=PROJECT/'android_app'"):]
source=source.replace("app=PROJECT/'android_app'","app=HERE/'app_stage'")
source=source.replace("HERE/'score_app/", "PRIOR/'score_app/")
source=source.replace("'stage':'phone adapter integrated after final D admission'",
                      "'stage':'isolated staging; production integration requires new admission'")
source=source.replace("'hardware':'score_bend_v1'", "'hardware':'candidate'")
exec(compile(source,str(PRIOR/'integrate_score_app.py'),'exec'))

app=HERE/'app_stage'
path=app/'app/build.gradle'
text=path.read_text(encoding='utf-8')
text=re.sub(r'versionCode \d+', 'versionCode 39', text)
text=re.sub(r"versionName '[^']+'", "versionName '1.38-scorebend'", text)
path.write_text(text,encoding='utf-8')
path=app/'app/src/main/AndroidManifest.xml'
text=path.read_text(encoding='utf-8')
text=re.sub(r'android:versionCode="\d+"', 'android:versionCode="39"', text)
text=re.sub(r'android:versionName="[^"]+"', 'android:versionName="1.38-scorebend"', text)
path.write_text(text,encoding='utf-8')
print('Staged Code39 / 1.38-scorebend; Code38 artwork preserved')
