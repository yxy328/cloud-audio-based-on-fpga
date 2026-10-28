"""Optional candidate: remove duplicate guards only behind validated HC05."""
from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/fsr_pitch_scaler.v';s=p.read_text(encoding='utf-8')
s=s.replace('CONTROL_KEYS=7, MAP_ROM=0,','CONTROL_KEYS=7, MAP_ROM=0, TRUSTED_BEND_WRITE=0,')
s=s.replace('.MAP_ROM(MAP_ROM),.NOTE_INCREMENTS', '.MAP_ROM(MAP_ROM),.TRUSTED_BEND_WRITE(TRUSTED_BEND_WRITE),.NOTE_INCREMENTS')
s=s.replace('bend_write && bend_index<CONTROL_KEYS && bend_ratio>=bend_min && bend_ratio<=bend_max',
    'bend_write && (TRUSTED_BEND_WRITE || (bend_index<CONTROL_KEYS && bend_ratio>=bend_min && bend_ratio<=bend_max))')
assert s.count('TRUSTED_BEND_WRITE=0')==2
p.write_text(s,encoding='utf-8')
p=P/'src/top.v';s=p.read_text(encoding='utf-8').replace('fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),','fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),.TRUSTED_BEND_WRITE(CONTROL_KEYS==12),')
p.write_text(s,encoding='utf-8')
print('HC05 retains complete index/ratio validation; standalone scaler guards remain enabled by default')
