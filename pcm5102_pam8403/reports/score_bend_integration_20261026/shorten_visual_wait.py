"""Skip only display pre-roll wall time; keep every 1024-clock audio frame."""
from work import *
p=HERE/'candidate'/PROJECT.name/'sim/tb_top_audition.v'
text=p.read_text(encoding='utf-8')
assert 'task skip_visual_wait' not in text
text=text.replace('    task natural_mapping;begin', '''    // Full millisecond/pre-roll scheduling is covered by tb_score_legacy.
    // This top-level audio test checks silence before fast-forwarding only
    // the visual cursor wait; all note durations and audio frames stay real.
    task skip_visual_wait;begin
        wait(dut.u_keymap.u_download.state==5);
        @(negedge clk);dut.u_keymap.u_download.elapsed_ms=59;
    end endtask
    task natural_mapping;begin''')
text=text.replace('#20000000;', '#200000;')
text=text.replace('check_silence(first); // 60ms pre-roll must not leak music.',
                  'check_silence(first); // Observe silent pre-roll before skipping the visual wait.\n        skip_visual_wait;')
text=text.replace('        wait(dut.audition_keys==7\'h15);', '        skip_visual_wait;\n        wait(dut.audition_keys==7\'h15);')
p.write_text(text,encoding='utf-8')
base=HERE/'baseline'/PROJECT.name/'sim/tb_top_audition_serial_current.v'
base.write_text(text.replace('module tb_top_audition;','module tb_top_audition_serial_current;'),encoding='utf-8')
print('Shortened only visual pre-roll wait; untouched 50MHz / 1024-clock audio frames')
