from pathlib import Path
import json,re,hashlib,html
R=Path(__file__).resolve().parent;C=R/'candidate/pcm5102_pam8403';P=R.parent.parent
F=C/'sim/build/unified/rhythm_game_release41';B=F/'pcm5102_pam8403'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):
    raw=p.read_bytes();return raw.decode('utf-16' if raw[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8-sig',errors='replace')
def cells(t):return [html.unescape(re.sub('<[^>]+>','',v)).strip() for v in re.findall(r'<td[^>]*>(.*?)</td>',t,re.S)]
def rows(t):return [cells(v) for v in re.findall(r'<tr>(.*?)</tr>',t,re.S) if '<td' in v]
report=(B/'impl/pnr/PCM5102_UNIFIED.rpt.txt').read_text()
log=read(F/'pnr.log')
assert 'Bitstream generation completed' in log and 'ERROR' not in log
metrics={}
for name in ['Logic','CLS','Register','BSRAM','DSP']:
    a=re.search(r'^\s*'+name+r'\s*\|\s*([\d.]+)/([\d.]+)',report,re.M)
    assert a,name;metrics[name]={'used':float(a[1]),'capacity':float(a[2]),'remaining':float(a[2])-float(a[1])}
assert metrics['CLS']['remaining']>=35
timing=(B/'impl/pnr/PCM5102_UNIFIED_tr_content.html').read_text()
tns=rows(timing[timing.index('Total Negative Slack Summary'):timing.index('Timing Details')])
assert len(tns)==4 and all(float(row[2])==0 and int(row[3])==0 for row in tns),tns
def worst(name):
    start=timing.index(name+' Paths Table');section=timing[start:];table=rows(section[:section.index('</table>')]);assert table;return float(table[0][1])
setup,hold=worst('Setup'),worst('Hold');assert setup>=0 and hold>=0
manifest=json.loads((F/'sources.json').read_text(encoding='utf-8-sig'))
source_hashes={}
for e in manifest:
    q=F/e['Path'];assert sha(q)==e['SHA256'],str(q)
    relative=q.relative_to(B) if q.is_relative_to(B) else None
    if relative is not None and (relative.parts[0]=='src' or relative.name.endswith('.gprj')):
        assert sha(C/relative)==sha(q),str(relative);source_hashes[str(relative)]=sha(q)
old=json.loads((P/'reports/control12_20261027/final_verification.json').read_text(encoding='utf-8-sig'))
baseline_drift=[n for n,h in old['source_hashes'].items() if (P/'src'/n).exists() and sha(P/'src'/n)!=h]
assert not baseline_drift,baseline_drift
tests=['tb_rhythm_game_quick','tb_rhythm_panel_quick','tb_rhythm_raster_quick','tb_rhythm_protocol',
       'tb_rhythm_top_quick','tb_control12_dense_quick','tb_hc05_visual_quick',
       'tb_control12_live_equivalence_quick','tb_sensor_staging_equivalence_quick',
       'tb_control12_take_quick','tb_fx_take_atomic_528_quick']
checks=[]
for name in tests:
    p=C/'sim/build'/f'{name}.log';s=read(p);passed=[l for l in s.splitlines() if l.startswith('PASS')]
    assert passed and 'FATAL' not in s,name
    checks.append({'test':name,'log':str(p.relative_to(R)),'sha256':sha(p),'result':passed})
core=(R/'app_core_final.log').read_text(encoding='utf-8-sig',errors='replace');assert 'PASS RhythmState' in core and 'AssertionError' not in core
apk=C/'android_app/dist/FPGA-Music-Rhythm-Code41.apk';fs=B/'impl/pnr/PCM5102_UNIFIED.fs'
assets=P/'android_app/app/src/main/assets';asset_hashes={}
for a in assets.rglob('*'):
    if a.is_file():assert sha(a)==sha(C/'android_app/app/src/main/assets'/a.relative_to(assets));asset_hashes[str(a.relative_to(assets))]=sha(a)
result={'label':'rhythm_game_release41','metrics':metrics,'unrouted_nets':0,
    'timing':{'setup_worst_ns':setup,'hold_worst_ns':hold,'violated_endpoints':tns},
    'safety_reserve_cls':35,'source_hashes':source_hashes,'tests':checks,
    'app_core_log_sha256':sha(R/'app_core_final.log'),'asset_hashes':asset_hashes,
    'apk_sha256':sha(apk),'bitstream_sha256':sha(fs),'baseline_Code40_drift':baseline_drift,
    'board_programmed':False,'app_installed':False,'published':False}
(R/'build_audit.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({k:result[k] for k in ['label','metrics','timing','apk_sha256','bitstream_sha256']},ensure_ascii=False))
