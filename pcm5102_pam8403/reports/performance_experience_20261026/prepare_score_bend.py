"""D initial candidate: optional per-event Q2.14 target; unchanged 128 events/60000ms.
This is a hardware admission screen, not a released score format or App feature.
"""
from work import *
root=candidate('score_bend');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:70]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('src/downloadable_song.v','input wire [15:0] arg0, arg1, arg2,','input wire [15:0] arg0, arg1, arg2, arg3,\n    output wire [15:0] score_ratio,')
edit('src/downloadable_song.v','reg [28:0] score [0:255];','reg [44:0] score [0:255];')
edit('src/downloadable_song.v','reg [28:0] fetched;', 'reg [44:0] fetched;')
edit('src/downloadable_song.v','reg [28:0] cur_word, next_word, future_word;', 'reg [44:0] cur_word, next_word, future_word;\n    assign score_ratio=cur_word[44:29];')
edit('src/downloadable_song.v','if(operation==2)\n                                score', 'if(operation==2)\n                                score') # Assert the old write structure.
edit('src/downloadable_song.v',"<={(13'b1 << (arg1-60)),arg2};", "<={16'd0,(13'b1 << (arg1-60)),arg2};")
edit('src/downloadable_song.v','<={arg1[12:0],arg2};','<={arg3,arg1[12:0],arg2};')
edit('src/downloadable_song.v','(operation==6 && arg1>8191)', '(operation==6 && (arg1>8191 || (arg3!=0 && (arg3<8192 || arg3>32768))))')
edit('src/hc05_keymap.v','output reg [31:0] vibrato_inc,','output wire [15:0] score_ratio,\n    output reg [31:0] vibrato_inc,')
edit('src/hc05_keymap.v','reg [15:0] song_arg0, song_arg1, song_arg2;', 'reg [15:0] song_arg0, song_arg1, song_arg2, song_arg3;')
edit('src/hc05_keymap.v','.arg0(song_arg0),.arg1(song_arg1),.arg2(song_arg2),','.arg0(song_arg0),.arg1(song_arg1),.arg2(song_arg2),.arg3(song_arg3),.score_ratio(score_ratio),')
edit('src/hc05_keymap.v','song_arg2<=accumulator;', "song_arg2<=field_count==4 ? value2 : accumulator;song_arg3<=field_count==4 ? accumulator : 16'd0;")
edit('src/hc05_keymap.v','else if(field_index>=field_count-1) result(7);', '''else if(field_index>=field_count-1 && !(song_operation==6 && field_index==2 &&
                                control_parse==0 && performance_parse==0 && !bend_parse && !adsr_parse)) result(7);''')
edit('src/hc05_keymap.v','if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;', '''if(song_operation==6 && field_index==2 && control_parse==0 && performance_parse==0 && !bend_parse && !adsr_parse)field_count<=4;
                                if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;''')
# Optional target is selected per mapped sounding key by the existing shared pitch pipeline.
edit('src/fsr_pitch_scaler.v','input wire [15:0] bend_min,bend_max,bend_slew,','input wire [15:0] bend_min,bend_max,bend_slew,\n    input wire [15:0] score_ratio,\n    input wire [6:0] score_keys,')
edit('src/fsr_pitch_scaler.v','.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.phase_increments', '.score_ratio(score_ratio),.score_keys(score_keys),.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.phase_increments')
edit('src/fsr_pitch_scaler.v','target_q<=targets[index];', 'target_q<=(score_ratio!=0 && score_keys[index]) ? score_ratio : targets[index];')
edit('src/top.v','wire [31:0] vibrato_inc;', 'wire [15:0] score_ratio;\n    wire [31:0] vibrato_inc;')
edit('src/top.v','.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),', '.score_ratio(score_ratio),.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),')
edit('src/top.v','fsr_pitch_scaler #(.PER_VOICE_BEND(1)) u_fsr_pitch_scaler (', '''fsr_pitch_scaler #(.PER_VOICE_BEND(1)) u_fsr_pitch_scaler (
        .score_ratio(score_ratio),.score_keys(downloaded_audition ? song_guide_keys : 7'd0),''')
save(root/'candidate_scope.json',{'protocol_candidate':'SONG_CHORD,index,mask,duration[,ratio] with 0 meaning keep manual targets; legacy unchanged',
    'format':'45-bit event (13 mask,16 duration,16 target) in same256 two banks; target per chord event',
    'semantics':'target glides using existing C2; actual application can lag event boundary by existing pitch scan/frame; not static immediate offset',
    'voice_conflict':'physical and audition note on same mapped key share target; separate per-note targets within same chord not represented',
    'TAKE':'existing low_steps record applied bent increments; no new snapshot field',
    'not_yet_validated':['pre-note timing','CSV/MIDI import/export','pause/stop corner cases','exact-score download protocol'],
    'production_integrated':False})
print(root)
