from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/rhythm_game.v';s=p.read_text(encoding='utf-8')
for old,new in [
    ('required_keys<=0;matched<=0;',''),
    ('now_ms<=0;due_ms<=0;','now_ms<=0;'),
    ('active<=0;long_note<=0;perfect<=1;holding<=0;','active<=0;holding<=0;'),
    ('flash_keys<=0;',''),
    ('eligible_q<=0;epoch<=0;read_epoch<=0;','epoch<=0;'),
]:
    assert old in s,old;s=s.replace(old,new)
s=s.replace('    reg active,long_note,perfect;','    // active/flash/epoch invalidate data until a complete event is captured.\n    // Only those validity controls need reset; note payloads need no clear.\n    reg active,long_note,perfect;')
p.write_text(s,encoding='utf-8')
p=R/'src/hub75e_rhythm_display.v';s=p.read_text(encoding='utf-8')
for line in ['            upper_notes <= 0;\n','            lower_notes <= 0;\n','            upper_pixel <= 0;\n','            lower_pixel <= 0;\n']:
    assert line in s,line;s=s.replace(line,'')
s=s.replace('            have_latched <= 0;','            // OE stays blank until a complete row has been prepared/shifted.\n            have_latched <= 0;',1)
p.write_text(s,encoding='utf-8')
print('Reset retained on valid/scan controls; invalid note/pixel payload clears removed')
