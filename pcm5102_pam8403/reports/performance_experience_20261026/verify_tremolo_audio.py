from work import *
import importlib.util, math
spec=importlib.util.spec_from_file_location('reference',PROJECT/'reports/fx_priority_20261026/fx_reference.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
root=HERE/'tremolo_v2';p=root/PROJECT.name
test=(PROJECT/'sim/tb_audio_fx_chain.v').read_text(encoding='utf-8')
test=test.replace('module tb_audio_fx_chain;', 'module tb_tremolo_audio;\n    reg [7:0] tremolo=0;integer trem_i;')
test=test.replace('.mask(mask),','.tremolo(tremolo),.mask(mask),')
test=test.replace('%h %h %d\\n",reset_i,dry_i,mask_i,settings_i,mix_i,expected','%h %h %h %d\\n",reset_i,dry_i,mask_i,settings_i,mix_i,trem_i,expected')
test=test.replace('status!=6','status!=7').replace('wet_mix=mix_i;','wet_mix=mix_i;tremolo=trem_i;')
(p/'sim/tb_tremolo_audio.v').write_text(test,encoding='utf-8')
steps=[0,344,687,1031,1374,1718,2062,2405,2749]
vector=HERE/'tremolo_vectors.txt';count=0;rates=[]
with vector.open('w',encoding='ascii') as f:
    for rate in range(9):
        if rate:rates.append({'rate':rate,'measured_from_DDS_increment_Hz':steps[rate]*ref.FS/2**24})
        for depth in (0,4,8):
            model=ref.Effects();phase=0;nframes=2000 if rate==0 else 2*math.ceil(2**24/steps[rate])
            for n in range(nframes):
                phase=(phase+steps[rate])%(2**24) if rate else 0
                triangle=128-((phase>>16)&127) if phase&(1<<23) else (phase>>16)&127
                dry=[-32768,32767,0,-1,1,16000,-16000][n%7]
                cfg=rate*16+depth
                base=model.step(dry,7,0x52,0x444)
                expected=ref.tz(base*(128-triangle*depth//8),128) if rate and depth else base
                f.write(f'{int(n==0)} {dry} 7 52 444 {cfg:02x} {expected}\n');count+=1
    model=ref.Effects();phase=0
    for n in range(12000):
        reset=n==0 or n==5000
        if reset:model.reset();phase=0
        rate=(n//900)%9;depth=(n//700)%9
        phase=(phase+steps[rate])%(2**24) if rate else 0
        triangle=128-((phase>>16)&127) if phase&(1<<23) else (phase>>16)&127
        base=model.step(0 if n>=5000 else 25000,0,0x52,0x444)
        expected=ref.tz(base*(128-triangle*depth//8),128) if rate and depth else base
        f.write(f'{int(reset)} {0 if n>=5000 else 25000} 0 52 444 {rate*16+depth:02x} {expected}\n');count+=1
binary=HERE/'tremolo_audio.vvp'
with (HERE/'tremolo_audio.log').open('w',encoding='utf-8') as log:
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2001','-s','tb_tremolo_audio','-o',str(binary),str(p/'sim/tb_tremolo_audio.v'),str(p/'src/audio_fx_chain.v')],stdout=log,stderr=log,check=True)
    subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),'+vectors='+str(vector),'+outputs='+str(HERE/'tremolo_output.csv')],stdout=log,stderr=log,check=True)
save(HERE/'tremolo_audio_results.json',{'RTL_samples_checked':count,'rates':rates,'depths':[0,4,8],
    'dynamic_switch_reset_silence':True,'off_or_zero_depth_matches_FX3':True,
    'TAKE_phase_limit':'configuration saved; phase not stored, deterministic modulation phase is not guaranteed across arbitrary playback start',
    'max_stage_clocks':53})
print((HERE/'tremolo_audio.log').read_text(encoding='utf-8'))
