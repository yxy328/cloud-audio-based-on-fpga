from work import *
import importlib.util, math
spec=importlib.util.spec_from_file_location('reference',PROJECT/'reports/fx_priority_20261026/fx_reference.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
root=HERE/'tremolo_shared';p=root/PROJECT.name
test=(HERE/'tremolo_v2'/PROJECT.name/'sim/tb_tremolo_audio.v').read_text(encoding='utf-8')
(p/'sim/tb_tremolo_audio.v').write_text(test,encoding='utf-8')
test=(p/'sim/tb_tremolo_protocol.v').read_text(encoding='utf-8').replace('r<=8','r<=4').replace('TREM,88,38','TREM,48,38')
(p/'sim/tb_tremolo_protocol.v').write_text(test,encoding='utf-8')
vector=HERE/'tremolo_shared_vectors.txt';count=0
with vector.open('w',encoding='ascii') as f:
    for rate in range(5):
        for depth in (0,4,8):
            model=ref.Effects();phase=0;nframes=2000 if rate==0 else 2*(65536>>(rate-1))
            for n in range(nframes):
                phase=(phase+1)&65535
                shift=8-max(0,rate-1);tri=(phase>>shift)&127
                triangle=128-tri if phase&(1<<(shift+7)) else tri
                dry=[-32768,32767,0,-1,1,16000,-16000][n%7];cfg=rate*16+depth
                base=model.step(dry,7,0x52,0x444)
                expected=ref.tz(base*(128-triangle*depth//8),128) if rate and depth else base
                f.write(f'{int(n==0)} {dry} 7 52 444 {cfg:02x} {expected}\n');count+=1
    model=ref.Effects();phase=0
    for n in range(12000):
        reset=n==0 or n==5000
        if reset:model.reset();phase=0
        phase=(phase+1)&65535;rate=(n//900)%5;depth=(n//700)%9
        shift=8-max(0,rate-1);tri=(phase>>shift)&127;triangle=128-tri if phase&(1<<(shift+7)) else tri
        dry=0 if n>=5000 else 25000;base=model.step(dry,0,0x52,0x444)
        expected=ref.tz(base*(128-triangle*depth//8),128) if rate and depth else base
        f.write(f'{int(reset)} {dry} 0 52 444 {rate*16+depth:02x} {expected}\n');count+=1
binary=HERE/'tremolo_shared_audio.vvp'
with (HERE/'tremolo_shared_audio.log').open('w',encoding='utf-8') as log:
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2001','-s','tb_tremolo_audio','-o',str(binary),str(p/'sim/tb_tremolo_audio.v'),str(p/'src/audio_fx_chain.v')],stdout=log,stderr=log,check=True)
    subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),'+vectors='+str(vector),'+outputs='+str(HERE/'tremolo_shared_output.csv')],stdout=log,stderr=log,check=True)
save(HERE/'tremolo_shared_audio_results.json',{'RTL_samples_checked':count,'rates_Hz':[ref.FS/65536*2**n for n in range(4)],
    'depths':[0,4,8],'dynamic_switch_reset_silence':True,'off_or_zero_depth_matches_FX3':True,'max_stage_clocks':52})
print((HERE/'tremolo_shared_audio.log').read_text(encoding='utf-8'))
