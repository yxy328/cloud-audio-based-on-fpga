from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/downloadable_song.v';s=p.read_text(encoding='utf-8')
s=s.replace('PRIME=4, RUN=5;', 'PRIME=4, RUN=5, MAP_SCAN=6;')
a=s.index('    always @* begin\n        covered_mask=0;');b=s.index('    // Only one copy',a)
s=s[:a]+'''    reg [$clog2(CONTROL_KEYS)-1:0] map_index;
    wire [7:0] map_pitch=checked_map[map_index*8+:8];
    // Build the coverage union once per END/PLAY, using one decoder.
    // Twelve extra fabric clocks do not touch the audio frame schedule.
'''+s[b:]
s=s.replace('index<=0; checked_map<=note_map; check_play<=1; state<=CHECK_FETCH;', 'index<=0; checked_map<=note_map; check_play<=1; covered_mask<=0;map_index<=0;state<=MAP_SCAN;')
s=s.replace('index<=0; checked_map<=note_map; check_play<=0; state<=CHECK_FETCH;', 'index<=0; checked_map<=note_map; check_play<=0; covered_mask<=0;map_index<=0;state<=MAP_SCAN;')
s=s.replace('check_play<=0; done<=0;', 'covered_mask<=0;map_index<=0;check_play<=0; done<=0;')
s=s.replace('                CHECK_FETCH: state<=CHECK_WAIT;', '''                MAP_SCAN:begin
                    if(map_pitch>=60 && map_pitch<=72)covered_mask[map_pitch-60]<=1'b1;
                    if(map_index==CONTROL_KEYS-1)state<=CHECK_FETCH;
                    else map_index<=map_index+1'b1;
                end
                CHECK_FETCH: state<=CHECK_WAIT;''')
p.write_text(s,encoding='utf-8')
print('One shared coverage decoder for score END/PLAY validation')
