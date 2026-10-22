"""Audit a frozen scope build against timing, source hashes and reserved budgets."""
from pathlib import Path
import argparse
import hashlib
import html
import json
import re

parser=argparse.ArgumentParser()
parser.add_argument('label')
parser.add_argument('--report-reserve-shortfall',action='store_true',
    help='Report a future-budget shortfall explicitly; still require device capacity, timing and exact sources')
args=parser.parse_args()
assert re.fullmatch(r'[A-Za-z0-9_-]+',args.label)
root=Path(__file__).resolve().parents[1]
snapshot=root/'sim/build/unified'/args.label
pnr=snapshot/'pcm5102_pam8403/impl/pnr'
stem='PCM5102_UNIFIED'
log=(snapshot/'build.log').read_text(encoding='utf-8-sig',errors='replace')
assert not re.search(r'(?im)^ERROR|unrouted nets|DesRoute failed',log), 'PnR contains errors'
rpt=(pnr/f'{stem}.rpt.txt').read_text(encoding='utf-8',errors='replace')
resources={}
for name in ('Logic','Register','CLS','BSRAM','DSP'):
    m=re.search(rf'(?m)^\s*{name}\s*\|\s*([\d.]+)/([\d.]+)',rpt)
    assert m,name
    resources[name]=float(m[1]) if '.' in m[1] else int(m[1])
baseline={'Logic':21088,'Register':10239,'CLS':11060,'BSRAM':44,'DSP':26.5}
assert resources['Logic']<=23040 and resources['CLS']<=11520,resources
reserve_shortfall={'Logic':max(0,resources['Logic']-21390),
                   'CLS':max(0,resources['CLS']-11155)}
if not args.report_reserve_shortfall:
    assert not any(reserve_shortfall.values()),f'Future resource reserve consumed: {reserve_shortfall}; {resources}'
assert resources['BSRAM']<=52 and resources['DSP']==26.5, resources
s=(pnr/f'{stem}_tr_content.html').read_text(encoding='utf-8',errors='replace')
rows=[]
for row in re.findall(r'<tr[^>]*>(.*?)</tr>',s,re.S|re.I):
    cells=[html.unescape(re.sub('<[^>]+>','',x)).strip() for x in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S|re.I)]
    if cells:rows.append(cells)
summary={r[0]:r[1] for r in rows if len(r)==2}
assert summary['Numbers of Setup Violated Endpoints']=='0'
assert summary['Numbers of Hold Violated Endpoints']=='0'
frequency=next(r for r in rows if len(r)==6 and r[1]=='clk' and '(MHz)' in r[3])
fmax=float(frequency[3].split('(')[0])
assert float(frequency[2].split('(')[0])==50 and fmax>=50,frequency
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
checked=0
for entry in json.loads((snapshot/'sources.json').read_text(encoding='utf-8-sig')):
    relative=Path(entry['Path'].replace('\\','/'))
    assert sha(snapshot/relative)==entry['SHA256'],f'Frozen input changed: {relative}'
    if '/src/' in relative.as_posix() or relative.suffix=='.gprj':
        assert sha(root.parent/relative)==entry['SHA256'],f'Working input differs: {relative}'
        checked+=1
fs=pnr/f'{stem}.fs'
header=fs.read_text(encoding='ascii',errors='replace')[:4096]
code=re.search(r'(?m)^//UserCode:\s*(0x[0-9a-fA-F]+)',header)
assert code and fs.stat().st_size>100000,'Missing complete bitstream'
result={
    'build':args.label,'resources':resources,'baseline':baseline,
    'delta':{k:resources[k]-baseline[k] for k in baseline},
    'remaining':{'Logic':23040-resources['Logic'],'CLS':11520-resources['CLS'],'BSRAM':56-resources['BSRAM']},
    'reserved':{'Logic':1650,'CLS':365,'BSRAM':4},
    'future_reserve_passed':not any(reserve_shortfall.values()),
    'future_reserve_shortfall':reserve_shortfall,
    'clock_mhz':50,'fmax_mhz':fmax,'setup_violations':0,'hold_violations':0,
    'matching_working_inputs':checked,'user_code':code[1],'sha256':sha(fs),
}
(snapshot/'scope_release_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
