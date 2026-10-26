from work import *
root=candidate('ir_tuning_v1','ir_tuning')
p=root/PROJECT.name/'src/hc05_keymap.v'
s=p.read_text(encoding='utf-8');old="(value0[2:0]-3'd1)*7";new="(value0[3:0]-4'd1)*7"
assert old in s;p.write_text(s.replace(old,new),encoding='utf-8')
save(root/'fix.json',{'change':'avoid unsigned string8 ->0 underflow in variable part-select; all8 strings must be writable',
    'prior_failed_case':'BANK,8,84 replied OK but field8 retained72; functional failure, not accepted'})
