from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/rhythm_game.v';s=p.read_text(encoding='utf-8')
s=s.replace('Every lane is serviced in 2 clocks.','Every lane is serviced in 3 clocks.')
s=s.replace('score_bcd,combo_bcd,best_bcd,miss_bcd,age,24\'d0','score_bcd,combo_bcd,best_bcd,miss_bcd,32\'d0')
s=s.replace('eligible_q<=(edge_here || recent_valid[lane]) && candidate_age<=window_ms;','eligible_q<=edge_here || recent_valid[lane];')
s=s.replace('else if(age>=window_ms || event_end','else if(elapsed>{1\'b0,window_ms} || event_end')
# The signed ROM tests the actual edge's distance to the event. A separate
# recent-valid TTL prevents old timestamps returning after the 512ms wrap.
s=s.replace("    wire [7:0] age=elapsed[8] ? 8'hff : elapsed[7:0];\n",'')
s=s.replace("    wire [8:0] candidate_age=edge_here ? 9'd0 : stamp_age;\n",'')
p.write_text(s,encoding='utf-8')
p=R/'src/hub75e_rhythm_display.v';s=p.read_text(encoding='utf-8')
s=s.replace('// A 64x7 bitmap holds note heads rather than a per-note register queue.','// A circular bitmap holds note heads rather than a per-note register queue.\n// Twelve-lane game mode stores separate tap/hold masks and draws 1px heads.')
s=s.replace('// Same seven-lane layout/colors as rhythm_guide.v. Sharing the bitmap','// Legacy seven-lane and current twelve-lane layouts share the bitmap.')
p.write_text(s,encoding='utf-8')
print('Inclusive judgement boundaries, reserved-zero telemetry, comments finalized')
