from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
original=(P/'sim/build/unified/control12_shared_reply/pcm5102_pam8403/src/downloadable_song.v').read_text(encoding='utf-8')
changed=original.replace('wire [7:0] map_pitch=checked_map[map_index*8+:8];','''wire [7:0] map_pitch=checked_map[map_index*8+:8];
    // Range guards already constrain MIDI to 60..72. A four-bit offset
    // addresses only the thirteen mask bits, rather than all 45 score bits.
    wire [3:0] map_offset=map_pitch[3:0]-4'd12;
    wire [3:0] write_offset=arg1[3:0]-4'd12;
    wire [12:0] fetched_mask=fetched[28:16];''')
changed=changed.replace('fetched[16+map_pitch-60]','fetched_mask[map_offset]').replace('covered_mask[map_pitch-60]','covered_mask[map_offset]').replace("(13'b1 << (arg1-60))","(13'b1 << write_offset)")
for name,source in [('base',original),('narrow',changed)]:
    d=R/'score_index_experiment'/name;d.mkdir(parents=True,exist_ok=True)
    (d/'downloadable_song.v').write_text(source.replace('CONTROL_KEYS=7','CONTROL_KEYS=12').replace('ENABLE_LOOKAHEAD=0','ENABLE_LOOKAHEAD=1'),encoding='utf-8')
    (d/'area.gprj').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gowin-fpga-project>
<Project><Template>FPGA</Template><Version>5</Version>
<Device name="GW5A-25A" pn="GW5A-LV25MG121NC1/I0">gw5a25a-002</Device>
<FileList><File path="downloadable_song.v" type="file.verilog" enable="1"/></FileList></Project>
''',encoding='utf-8')
    (d/'build.tcl').write_text('''cd [file dirname [info script]]
open_project area.gprj
set_option -top_module downloadable_song -output_base_name area -resource_sharing 1 -retiming 1 -global_freq 50
run syn
''',encoding='utf-8')
(R/'narrow_downloadable_song.v').write_text(changed,encoding='utf-8')
print('Prepared isolated same-parameter area comparison for bounded score indices')
