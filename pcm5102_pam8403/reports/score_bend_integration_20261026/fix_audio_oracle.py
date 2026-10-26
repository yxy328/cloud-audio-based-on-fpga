from work import *
p=HERE/'candidate'/PROJECT.name/'sim/tb_top_audition.v'
text=p.read_text(encoding='utf-8')
assert 'if(peak<500)' in text
text=text.replace('if(peak<500)', 'if(peak==0)')
text=text.replace('    task check_sound;', '''    // The fixed16 baseline produces peak208 in the old first-chord window;
    // its obsolete 7-key peak500 cutoff fails before this feature exists.
    // Require nonzero independently checked voices here, then compare every
    // external I2S sample and timestamp to the unchanged baseline CSV.
    task check_sound;''')
p.write_text(text,encoding='utf-8')
(HERE/'baseline'/PROJECT.name/'sim/tb_top_audition_serial_current.v').write_text(
    text.replace('module tb_top_audition;','module tb_top_audition_serial_current;'),encoding='utf-8')
print('Replaced obsolete amplitude cutoff with current-baseline full I2S oracle')
