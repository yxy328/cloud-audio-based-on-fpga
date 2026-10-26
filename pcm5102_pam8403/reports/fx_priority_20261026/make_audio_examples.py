"""Identical synthetic plucked chords through dry/R/CDR; RTL validates each PCM sample."""
from pathlib import Path
import math,json,subprocess,wave,array,hashlib,sys
from fx_reference import Effects,FS
H=Path(__file__).resolve().parent;out=H/'audio_examples';out.mkdir(exist_ok=True)
count=round(FS*4.5);notes=[(0,(261.6256,329.6276,391.9954)),(.55,(293.6648,369.9944,440)),(1.1,(329.6276,415.3047,493.8833)),(1.65,(261.6256,329.6276,391.9954))]
dry=[]
for n in range(count):
    t=n/FS;v=0
    for start,chord in notes:
        dt=t-start
        if 0<=dt<.9:
            env=min(1,dt/.003)*math.exp(-dt*6)*(1-min(1,max(0,(dt-.7)/.2)))
            v+=sum(1900*env*(math.sin(2*math.pi*f*dt)+.23*math.sin(4*math.pi*f*dt)+.08*math.sin(6*math.pi*f*dt)) for f in chord)
    dry.append(round(v))
phases=[];vector=out/'vectors.txt'
with vector.open('w',encoding='ascii') as f:
    for name,mask,settings,mix in [('dry',0,0xd6,0x864),('reverb',4,0xd6,0x864),('chorus_delay_reverb',7,0xd6,0x864)]:
        e=Effects();start=len(phases)*count
        for n,x in enumerate(dry):f.write(f'{int(n==0)} {x} {mask} {settings:02x} {mix:03x} {e.step(x,mask,settings,mix)}\n')
        phases.append({'name':name,'start':start,'frames':count,'mask':mask,'settings':settings,'mix':mix})
if '--export' not in sys.argv:
    with (out/'rtl.log').open('w') as f:
        r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(H/'functional/fx_full.vvp'),f'+vectors={vector}',f'+outputs={out/"rtl.csv"}'],stdout=f,stderr=f)
    assert r.returncode==0,(out/'rtl.log').read_text()
assert f'frames={count*3} max_latency=49' in (out/'rtl.log').read_text()
samples=[int(line.split(',')[1]) for line in (out/'rtl.csv').read_text().splitlines()]
assert len(samples)==count*3
for phase in phases:
    v=samples[phase['start']:phase['start']+count];file=out/(phase['name']+'.wav')
    with wave.open(str(file),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(round(FS));w.writeframes(array.array('h',v).tobytes())
    phase.update(peak=max(map(abs,v)),clipped=sum(x in (-32768,32767) for x in v),sha256=hashlib.sha256(file.read_bytes()).hexdigest().upper())
(out/'manifest.json').write_text(json.dumps({'true_sample_rate':FS,'wav_sample_rate':round(FS),'source':'synthetic plucked chord; RTL PCM, not board recording','phases':phases},indent=2)+'\n')
print('PASS 3 identical-input RTL audio examples, no clipping:',[(p['name'],p['peak'],p['clipped']) for p in phases])
