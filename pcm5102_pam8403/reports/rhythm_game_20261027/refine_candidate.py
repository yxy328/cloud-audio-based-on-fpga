from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
def edit(name,old,new):
    p=R/name;s=p.read_text(encoding='utf-8');assert old in s,(name,old[:70]);p.write_text(s.replace(old,new),encoding='utf-8')
edit('src/hc05_keymap.v',"CMD_VIS_QUERY: reply<={{2'd0,visual_requested}","CMD_VIS_QUERY: if(visual_snapshot[111:108]==2)reply<={{2'd0,visual_requested},4'd0,{2'd0,reference_ratio},{2'd0,reference_phase},12'd0,84'd0};\n                    else reply<={{2'd0,visual_requested}")
edit('src/downloadable_song.v','    output reg note_spawn,','    output wire spawn_long,\n    output reg note_spawn,')
edit('src/downloadable_song.v','    assign event_duration=cur_word[15:0];','    assign event_duration=cur_word[15:0];\n    reg future_long;\n    assign spawn_long=future_long;')
# Capture alongside the pulse, before the future RAM cursor can be refilled.
edit('src/downloadable_song.v','                            spawn_keys<=future_keys;','                            spawn_keys<=future_keys;future_long<=future_word[15:0]>=500;')
edit('src/hc05_keymap.v','    output wire game_event_start,game_event_end,','    output wire game_spawn_long,game_event_start,game_event_end,')
edit('src/hc05_keymap.v','.event_start(game_event_start),','.spawn_long(game_spawn_long),.event_start(game_event_start),')
edit('src/top.v','    wire game_event_start,game_event_end;','    wire game_spawn_long,game_event_start,game_event_end;')
edit('src/top.v','.game_event_start(game_event_start),','.game_spawn_long(game_spawn_long),.game_event_start(game_event_start),')
edit('src/top.v','.game_event_start(game_event_start && !downloaded_audition),','.game_spawn_long(game_spawn_long),.game_event_start(game_event_start && !downloaded_audition),')
edit('src/hub75e_rhythm_display.v','    input wire game_event_start,game_event_end,','    input wire game_spawn_long,game_event_start,game_event_end,')
edit('src/hub75e_rhythm_display.v','    localparam integer READ_PORTS=ENABLE_GAME ? 2 : 6;','    localparam integer READ_PORTS=ENABLE_GAME ? 2 : 6;\n    localparam integer DATA_BITS=CONTROL_KEYS*(ENABLE_GAME ? 2 : 1);')
# Memory holds a lane mask and a long-note mask; no extra physical RAM block.
p=R/'src/hub75e_rhythm_display.v';s=p.read_text(encoding='utf-8')
for name in ['head_memory','head_read_q','head_read_value','keys_s0','upper_notes','head_write_data','panel_heads','memory','q;','upper_glyph','note_rows','notes;']:
    # Each listed declaration starts with the original lane width.
    s=s.replace('[CONTROL_KEYS-1:0] '+name,'[DATA_BITS-1:0] '+name)
s=s.replace("keys_s0<=spawn_keys;","keys_s0<=ENABLE_GAME ? {(game_spawn_long && game_settings[6] ? spawn_keys : {CONTROL_KEYS{1'b0}}),spawn_keys} : spawn_keys;")
s=s.replace('                    if(ENABLE_GAME)begin','                    if(ENABLE_GAME)begin\n                        if(notes[lane+CONTROL_KEYS])begin r=28;g=0;b=31;end')
# A narrow pulse is a long-note cue regardless of the chosen base theme.
s=s.replace('if(game_settings[1:0]==1)','if(!notes[lane+CONTROL_KEYS] && game_settings[1:0]==1)').replace('if(game_settings[1:0]==2)','if(!notes[lane+CONTROL_KEYS] && game_settings[1:0]==2)')
p.write_text(s,encoding='utf-8')
# Closing at the scheduled boundary permits releasing precisely on that edge.
edit('src/rhythm_game.v','if((touch_keys & required_keys)!=required_keys)finish_event(0);\n                    else if(event_end || !playing || event_start)finish_event(1);','if(event_end || !playing || event_start)finish_event(1);\n                    else if((touch_keys & required_keys)!=required_keys)finish_event(0);')

p=R/'sim/tb_control12_protocol.v';s=p.read_text(encoding='utf-8').replace('module tb_control12_protocol;','module tb_rhythm_protocol;')
s=s.replace(".take_recording(1'b0)",".visual_snapshot({4'd2,108'd0}),.visual_requested(2'd0),.reference_ratio(2'd0),.reference_phase(2'd0),.take_recording(1'b0)")
anchor='        send("MAP?\\015","MAP,60,61,62,63,64,65,66,67,68,69,70,71\\015\\012");'
s=s.replace(anchor,'''        send("VIS,0,228\\015","OK\\015\\012");
        if(dut.game_settings!==228)$fatal(1,"game settings not applied");
        send("VIS?\\015","VIS,0,0,0,0,0,0,0\\015\\012");
        send("VIS,0,256\\015","ERR,RANGE\\015\\012");
        send("VIS,1,228\\015","ERR,RANGE\\015\\012");
        send("VIS,0,\\015","ERR,CMD\\015\\012");
        send("VIS,3\\015","OK\\015\\012");
        if(dut.remote_mode!==3)$fatal(1,"legacy page selection changed");
'''+anchor,1)
(R/'sim/tb_rhythm_protocol.v').write_text(s,encoding='utf-8')
print('Long-note cue, protocol and boundary fixes prepared')
