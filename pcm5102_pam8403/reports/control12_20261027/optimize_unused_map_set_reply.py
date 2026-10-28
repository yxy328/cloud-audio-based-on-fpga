from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/hc05_keymap.v';s=p.read_text(encoding='utf-8')
old='CMD_MAP_SET: reply<='
assert old in s
# Twelve-key MAP sets use static OK. Only the seven-key compatibility mode
# emits the old dynamic OK,MAP,key,note reply and needs this snapshot arm.
s=s.replace(old,'CMD_MAP_SET: if(CONTROL_KEYS==7)reply<=')
p.write_text(s,encoding='utf-8')
print('Keep legacy MAP-set reply snapshot only in the seven-key configuration')
