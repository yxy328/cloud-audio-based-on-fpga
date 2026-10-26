from pathlib import Path
import json,math,csv
import numpy as np
from fx_reference import FS,tz
HERE=Path(__file__).resolve().parent;F=HERE/'functional'
meta=json.loads((F/'vectors_full.json').read_text(encoding='utf-8'))
y=np.loadtxt(F/'outputs_full.csv',delimiter=',',dtype=np.int64)
assert len(y)==meta['frames'] and np.array_equal(y[:,0],np.arange(len(y)))
out=y[:,1];phases={p['name']:p for p in meta['phases']}
results={'sample_rate':FS,'frames':len(y),'max_cycles':int(max(y[:,2])),'reverb':[],'delay':[]}
edcs=[]
for i in range(4):
    p=phases[f'reverb_impulse{i}'];n=phases[f'reverb_negative{i}']
    a=out[p['start']:p['start']+p['frames']].copy();b=out[n['start']:n['start']+n['frames']]
    assert np.array_equal(a,-b),f'Asymmetric reverb {i}'
    a[0]=0
    nz=np.flatnonzero(a);assert len(nz) and np.all(a[-10000:]==0)
    energy=np.cumsum((a.astype(np.float64)**2)[::-1])[::-1]
    edc=10*np.log10(np.maximum(energy,1e-30)/energy[0])
    def crossing(db):return int(np.flatnonzero(edc<=db)[0])/FS
    t5,t25=crossing(-5),crossing(-25)
    r={'preset':i,'feedback':[.625,.75,.8125,.875][i],
       'first_wet_ms':int(nz[0])*1000/FS,'last_nonzero_ms':int(nz[-1])*1000/FS,
       'direct_EDC_minus60_ms':crossing(-60)*1000,
       'T20_extrapolated_RT60_ms':(t25-t5)*3000,
       'positive_negative_exactly_symmetric':True,'last10000_samples_zero':True,
       'wet_peak':int(np.max(np.abs(a))),'wet_energy':float(energy[0])}
    results['reverb'].append(r);edcs.append(edc)
for i in range(4):
    p=phases[f'delay_impulse{i}'];a=out[p['start']:p['start']+p['frames']].copy();a[0]=0
    nz=np.flatnonzero(a);first=int(nz[0]);nominal=4096*[1,2,4,6][i]
    results['delay'].append({'tap':i,'first_wet_frame':first,'first_wet_ms':first*1000/FS,
        'nominal_ms':nominal*1000/FS,'configuration_extra_frames':first-nominal,
        'first_wet_amplitude':int(a[first])})
p=phases['chorus_tone'];a=out[p['start']:p['start']+p['frames']]
errors=[];old_errors=[]
for n in range(2000,p['frames']):
    triangle=n&32767 if n<32768 else 32767-(n&32767)
    d=1024+triangle/128
    dry=int(12000*math.sin(2*math.pi*440*n/FS))
    ideal=dry+6000*math.sin(2*math.pi*440*(n-d)/FS)
    old_tap=int(12000*math.sin(2*math.pi*440*(n-int(d))/FS))
    errors.append(int(a[n])-ideal);old_errors.append(dry+tz(old_tap,2)-ideal)
new_rms=math.sqrt(sum(e*e for e in errors)/len(errors));old_rms=math.sqrt(sum(e*e for e in old_errors)/len(old_errors))
assert new_rms<old_rms/10,(new_rms,old_rms)
results['chorus']={'lfo_Hz':FS/65536,'delay_samples_base':1024,'excursion_samples':[31.99609375,63.99609375,127.99609375,255.9921875],
    'test_tone_Hz':440,'interpolated_error_RMS_LSB':new_rms,'integer_delay_error_RMS_LSB':old_rms,
    'error_reduction_dB':20*math.log10(old_rms/new_rms),
    'metric':'Error against analytic continuously delayed sine, excluding startup; not an acoustic recording or total THD measurement'}
with (F/'reverb_EDC.csv').open('w',newline='',encoding='ascii') as f:
    w=csv.writer(f);w.writerow(['time_ms']+[f'preset{i}_dB' for i in range(4)])
    for n in range(0,120000,100):w.writerow([n*1000/FS]+[float(max(-120,e[n])) for e in edcs])
(HERE/'audio_metrics.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
print(json.dumps(results,indent=2))
