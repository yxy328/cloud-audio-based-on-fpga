"""Bind passing, scoped regressions to the selected frozen hardware inputs."""
from pathlib import Path
import hashlib,json,sys
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
label=sys.argv[1];selected=P/'sim/build/unified'/label/'pcm5102_pam8403'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
assert all(sha(p)==sha(selected/'src'/p.name) for p in (P/'src').iterdir() if p.is_file())
spec={
 'touch_width_equivalence.log':4,
 'width_final_top.log':2,
 'width_final_units.log':9,
 'width_final_compat.log':8,
}
logs={}
for name,total in spec.items():
    p=R/name;text=p.read_text(encoding='utf-8-sig',errors='replace')
    passed=[line for line in text.splitlines() if line.startswith('PASS')]
    assert len(passed)==total,(name,len(passed),total)
    assert all(mark not in text for mark in ['FATAL:', 'FAIL ', 'Exception:', 'compile failed','test timeout',' error:']),name
    logs[name]={'sha256':sha(p),'scope':'current width optimization RTL','checks':passed}
result={'label':label,'rtl_check_groups':sum(len(row['checks']) for row in logs.values()),
 'source_hashes':{p.name:sha(p) for p in (selected/'src').iterdir() if p.is_file()},
 'test_input_hashes':{str(p.relative_to(P)):sha(p) for p in list((P/'sim').glob('tb_control12*.v'))+list((P/'sim/reference').glob('*code39*'))+[P/'tools/test_control12.ps1',P/'tools/run_sim.ps1']},
 'logs':logs}
(R/'final_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'label':label,'rtl_check_groups':result['rtl_check_groups'],'source_match':True}))
