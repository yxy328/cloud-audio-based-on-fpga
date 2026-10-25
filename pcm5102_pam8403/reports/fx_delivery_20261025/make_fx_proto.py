from delivery import *

root=candidate(sys.argv[1] if len(sys.argv)>1 else 'fx_proto')
project=root/'pcm5102_pam8403'
shutil.copy2(HERE/'fixtures/audio_fx_minproto.v',project/'src/audio_fx_minproto.v')
p=project/'PCM5102_UNIFIED.gprj'
s=p.read_text(encoding='utf-8-sig').replace('</FileList>', '<File path="src/audio_fx_minproto.v" type="file.verilog" enable="1"/></FileList>')
p.write_text(s,encoding='utf-8')
p=project/'src/top.v'
s=p.read_text(encoding='utf-8-sig')
s=s.replace('audio_effects #(.ADDRESS_BITS(12)) u_effects (','audio_fx_minproto u_effects (\n        .mask(tuning_ratio[2:0]),.reverb_preset(gesture_timbre[1:0]),.overrun(),')
s=s.replace('        .mode(perf_replay ? perf_state[484 +: 2] : effect_mode),\n','')
s=s.replace('((perf_replay ? perf_state[484 +: 2] : effect_mode)==0 ? dry_audio_sample : effect_sample)',
            '(tuning_ratio[2:0]==0 ? dry_audio_sample : effect_sample)')
p.write_text(s,encoding='utf-8')
print('Isolated prototype: mask=tuning_ratio[2:0], reverb preset=gesture_timbre[1:0]. No shipping protocol.')
