"""Control-induced discontinuity vs the same input with unchanged controls.
All outputs are checked sample-by-sample against RTL before metrics are accepted.
RMS matching attenuates every example to the quietest RMS; it never boosts one.
"""
from pathlib import Path
import array, hashlib, importlib.util, json, math, subprocess, wave

HERE=Path(__file__).resolve().parent; PROJECT=HERE.parent.parent
spec=importlib.util.spec_from_file_location('reference',PROJECT/'reports/fx_priority_20261026/fx_reference.py')
reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)
FS=reference.FS
def dump(name,data): (HERE/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def write_wav(p,samples):
    with wave.open(str(p),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(round(FS));w.writeframes(array.array('h',samples).tobytes())

out=HERE/'audio';out.mkdir(exist_ok=True)
examples=PROJECT/'reports/fx_priority_20261026/audio_examples'
rows=[];waves=[]
for name in ('dry','reverb','chorus_delay_reverb'):
    path=examples/(name+'.wav')
    with wave.open(str(path),'rb') as w:
        assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==48828
        samples=array.array('h',w.readframes(w.getnframes()))
    rms=math.sqrt(sum(x*x for x in samples)/len(samples));waves.append((name,samples,rms));rows.append({'name':name,'source_sha256':sha(path),'RMS_LSB':rms})
target=min(row[2] for row in waves)
for row,(name,samples,rms) in zip(rows,waves):
    gain=target/rms;path=out/(name+'_rms_reference.wav');write_wav(path,[round(x*gain) for x in samples])
    row.update({'attenuation_dB':20*math.log10(gain),'reference_sha256':sha(path)})
dump('listening_references.json',{'true_sample_rate':FS,'method':'whole-file RMS, attenuation only; not perceptual LUFS loudness normalization','examples':rows,'board_recording':False})

switch=50123;frames=switch+2000
cases=[
    ('chorus_wet_step',(1,0x52,0x004),(1,0x52,0x005)),
    ('delay_wet_step',(2,0x52,0x040),(2,0x52,0x050)),
    ('reverb_wet_step',(4,0x52,0x400),(4,0x52,0x500)),
    ('all_wet_jump',(7,0x52,0x000),(7,0x52,0x888)),
    ('chorus_off',(1,0x52,0x008),(0,0x52,0x008)),
    ('delay_off',(2,0x52,0x080),(0,0x52,0x080)),
    ('reverb_off',(4,0x52,0x800),(0,0x52,0x800)),
    ('chorus_on',(0,0x52,0x008),(1,0x52,0x008)),
    ('chorus_depth',(1,0x52,0x008),(1,0x53,0x008)),
    ('delay_time',(2,0x52,0x080),(2,0x56,0x080)),
    ('delay_feedback',(2,0x52,0x080),(2,0x62,0x080)),
    ('reverb_preset',(4,0x52,0x800),(4,0xD2,0x800)),
    ('scene_change',(5,0x51,0x203),(2,0x18,0x040)),
    ('slider_boundary_chatter',(7,0x52,0x444),None),
]
metrics=[];vector=HERE/'transition_vectors.txt'
with vector.open('w',encoding='ascii') as f:
    for name,before,after in cases:
        changed=reference.Effects();unchanged=reference.Effects();ys=[];refs=[];effects=[]
        for n in range(frames):
            # Smooth ongoing chord; bounds leave enough headroom to isolate control changes.
            dry=round(5500*math.sin(2*math.pi*440*n/FS)+2400*math.sin(2*math.pi*659.255*n/FS))
            cfg=before if n<switch else (after if after is not None else (7,0x52,0x444 if (n-switch)//500%2 else 0x555))
            y=changed.step(dry,*cfg);ref=unchanged.step(dry,*before)
            f.write(f'{int(n==0)} {dry} {cfg[0]} {cfg[1]:02x} {cfg[2]:03x} {y}\n')
            ys.append(y);refs.append(ref);effects.append(y-ref)
        boundary=effects[switch]-effects[switch-1]
        metric={'case':name,'before':before,'after':after,'switch_frame':switch,
            'adjacent_output_jump_LSB':ys[switch]-ys[switch-1],
            'counterfactual_signal_jump_LSB':refs[switch]-refs[switch-1],
            'control_induced_boundary_jump_LSB':boundary,
            'control_induced_boundary_dBFS':20*math.log10(abs(boundary)/32768) if boundary else None,
            'max_control_error_first_ms_LSB':max(abs(x) for x in effects[switch:switch+49]),
            'clipped_samples':sum(x in (-32768,32767) for x in ys)}
        metrics.append(metric)
        write_wav(out/(name+'.wav'),ys[switch-4883:])

binary=HERE/'transition.vvp';iverilog=Path('C:/iverilog/bin/iverilog.exe');vvp=iverilog.with_name('vvp.exe')
with (HERE/'transitions.log').open('w',encoding='utf-8') as log:
    subprocess.run([str(iverilog),'-g2001','-s','tb_audio_fx_chain','-o',str(binary),str(PROJECT/'sim/tb_audio_fx_chain.v'),str(PROJECT/'src/audio_fx_chain.v')],stdout=log,stderr=log,check=True)
    subprocess.run([str(vvp),str(binary),'+vectors='+str(vector),'+outputs='+str(HERE/'transition_output.csv')],stdout=log,stderr=log,check=True)
dump('transition_metrics.json',{'RTL_verified_frames':frames*len(cases),'sample_rate':FS,
    'interpretation':'one synthetic chord and control timing; measured discontinuity is not a confirmed audible defect',
    'vector_sha256':sha(vector),'output_sha256':sha(HERE/'transition_output.csv'),'cases':metrics})
print((HERE/'transitions.log').read_text(encoding='utf-8'))
print('Measured',len(cases),'control transitions; raw and RMS listening references retained')
