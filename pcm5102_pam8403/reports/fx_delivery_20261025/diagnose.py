from delivery import *
import xml.etree.ElementTree as ET
def hierarchy(label):
    path=HERE/label/'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml'
    if not path.exists():return {}
    result={}
    def walk(e,p):
        name=p+'/'+e.get('name','')
        result[name]={k:int(e.get(k,'0')) for k in ('Lut','Alu','Register','Bsram','Ssram')}
        for c in e:walk(c,name)
    walk(ET.parse(path).getroot(),'')
    return result
a=hierarchy('base')
for label in sys.argv[1:]:
    b=hierarchy(label);rows=[]
    for name in sorted(set(a)|set(b)):
        delta={k:b.get(name,{}).get(k,0)-a.get(name,{}).get(k,0) for k in ('Lut','Alu','Register','Bsram','Ssram')}
        if any(delta.values()):rows.append({'module':name,**delta})
    write_json(HERE/(label+'_hierarchy_delta.json'),rows)
    print(label)
    for row in sorted(rows,key=lambda r:abs(r['Lut']+r['Alu']),reverse=True)[:10]:print(row)
