from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
old=(P/'src/touch_tdm_synth.v').read_text(encoding='utf-8')
new=old.replace('reg signed [32:0] mul_a;','''// Fixed high-note steps are below 2^26; sine and mixer sums are
    // signed and also fit 27 bits. Narrowing operands is exact and lets
    // synthesis use one 27x18 DSP instead of the wider multiplier mode.
    reg signed [26:0] mul_a;''')
new=new.replace('reg signed [17:0] mul_b;','reg signed [16:0] mul_b;')
new=new.replace('reg signed [50:0] local_product;','reg signed [43:0] local_product;')
new=new.replace('reg signed [23:0] sum;','''// Sixteen signed 16-bit samples need at most 20 bits before
    // VOLUME_SHIFT attenuation; high keys receive one extra shift.
    localparam SUM_BITS=VOLUME_SHIFT<0 ? 24 : VOLUME_SHIFT>18 ? 2 : 20-VOLUME_SHIFT;
    reg signed [SUM_BITS-1:0] sum;''')
for name,source in [('base',old),('narrow',new)]:
 d=R/'touch_width_experiment'/name;d.mkdir(parents=True,exist_ok=True)
 (d/'touch_tdm_synth.v').write_text(source.replace('CONTROL_KEYS=7','CONTROL_KEYS=12'),encoding='utf-8')
 for f in ['touch_sine_rom.v','audio_master_volume.v']:(d/f).write_bytes((P/'src'/f).read_bytes())
 g=(R/'score_index_experiment/base/area.gprj').read_text().replace('downloadable_song.v','touch_tdm_synth.v').replace('</FileList>','<File path="touch_sine_rom.v" type="file.verilog" enable="1"/><File path="audio_master_volume.v" type="file.verilog" enable="1"/></FileList>')
 (d/'area.gprj').write_text(g,encoding='utf-8')
 t=(R/'score_index_experiment/base/build.tcl').read_text().replace('downloadable_song','touch_tdm_synth')
 (d/'build.tcl').write_text(t,encoding='utf-8')
(P/'src/touch_tdm_synth.v').write_text(new,encoding='utf-8')
print('Bounded touch arithmetic: exact 27x17 multiply, signed frame sum 20-VOLUME_SHIFT bits')
