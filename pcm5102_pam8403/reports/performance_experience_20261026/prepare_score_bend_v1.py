from work import *
root=candidate('score_bend_v1','score_bend');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:75]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('src/downloadable_song.v','input wire [15:0] arg0, arg1, arg2, arg3,','input wire [15:0] arg0, arg1, arg2, arg3,\n    input wire [15:0] score_min,score_max,')
edit('src/downloadable_song.v','else if((fetched[28:16] & ~covered_mask)!=0)', '''else if(fetched[44:29]!=0 && (fetched[44:29]<score_min || fetched[44:29]>score_max)) finish(2);
                    else if((fetched[28:16] & ~covered_mask)!=0)''')
edit('src/hc05_keymap.v','.arg3(song_arg3),.score_ratio(score_ratio),','.arg3(song_arg3),.score_min(bend_min),.score_max(bend_max),.score_ratio(score_ratio),')
edit('src/hc05_keymap.v','song_operation<=1; parse_numbers(11,1);', '''if(line_length==12 && line[7:0]=="?")begin
                                respond(5'd31,6'd12);
                            end else begin song_operation<=1;parse_numbers(11,1);end''')
edit('tools/generate_hc05_replies.py',"    'EFFECT3,#,##,###,#,##,###\\r\\n',", "    'EFFECT3,#,##,###,#,##,###\\r\\n',\n    'SONGBEND,1\\r\\n',")
subprocess.run([sys.executable,str(p/'tools/generate_hc05_replies.py')],check=True)
edit('src/fsr_pitch_scaler.v','(score_ratio!=0 && score_keys[index])', '(score_ratio!=0 && index<7 && score_keys[index])')
save(root/'candidate_scope.json',{'scope':'per-event shared-chord bend target with existing glide; no instantaneous static offset mode',
    'protocol':'SONG_BEGIN,? -> SONGBEND,1; SONG_CHORD,index,mask,duration[,Q2.14 ratio]; old3 fields unchanged',
    'range_validation':'END and PLAY validate every nonzero target against current bend_min/max, retaining old active score on END failure',
    'timing':'target selected at event mask transition; original frame pitch scan, no new oscillator reset; initial note frames may use previous glide position',
    'voice_conflict':'mapped touch voice is shared with physical input; target applies to that key while audition sounds it',
    'TAKE':'existing applied low_steps snapshot; no format widening',
    'production_integrated':False})
print(root)
