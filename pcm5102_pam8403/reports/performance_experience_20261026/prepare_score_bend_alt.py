"""The single structural D alternative, prompted by 20 CLS cost vs 15 admitted."""
from work import *
root=candidate('score_bend_alt','score_bend_v1');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:90]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('src/downloadable_song.v','    integer k;', '''    integer k;
    // WRITE guarantees r is 0 (legacy) or8192..32768; PITCH guarantees
    // lo8192..15918 and hi16864..32768. Shared high bits need no comparator.
    function target_outside;
        input [15:0] r,lo,hi;
        begin target_outside=(r!=0) &&
            ((!r[15] && !r[14] && r[12:0]<lo[12:0]) ||
             (r[15] && !hi[15]) ||
             (!r[15] && r[14] && !hi[15] && r[13:0]>hi[13:0]));end
    endfunction''')
edit('src/downloadable_song.v','fetched[44:29]!=0 && (fetched[44:29]<score_min || fetched[44:29]>score_max)', 'target_outside(fetched[44:29],score_min,score_max)')
edit('src/hc05_keymap.v','''if(line_length==12 && line[7:0]=="?")begin
                                respond(5'd31,6'd12);
                            end else begin song_operation<=1;parse_numbers(11,1);end''', 'song_operation<=1;parse_numbers(11,1);')
edit('src/hc05_keymap.v','''!(song_operation==6 && field_index==2 &&
                                control_parse==0 && performance_parse==0 && !bend_parse && !adsr_parse)''', '''!((song_operation==6 && field_index==2 || song_operation==1 && field_index==0) &&
                                control_parse==0 && performance_parse==0 && !bend_parse && !adsr_parse)''')
edit('src/hc05_keymap.v','if(song_operation==6 && field_index==2 && control_parse==0', 'if(song_operation==1 && field_index==0 && control_parse==0 && performance_parse==0 && !bend_parse && !adsr_parse)field_count<=2;\n                                if(song_operation==6 && field_index==2 && control_parse==0')
edit('src/hc05_keymap.v','''end else begin
                                song_arg0<=(field_count==1) ? accumulator : value0;''', '''end else if(song_operation==1 && field_count==2 && accumulator!=1)result(7);
                            else begin
                                song_arg0<=(field_count==1) ? accumulator : value0;''')
edit('tools/generate_hc05_replies.py',"    'SONGBEND,1\\r\\n',\n",'')
subprocess.run([sys.executable,str(p/'tools/generate_hc05_replies.py')],check=True)
save(root/'candidate_scope.json',{'structural_alternative_to':'score_bend_v1',
    'reason':'full safe implementation20 CLS leaves30, 5 short of35 safety',
    'format_negotiation':'SONG_BEGIN,count,1 returns OK; legacy one-field unchanged; old firmware rejects format marker before data',
    'comparison_domain':'target0 or8192..32768, lower8192..15918, upper16864..32768; truncated comparisons only under proven shared high bits',
    'compatibility':'new/old score commands, active/staging banks and TAKE low_steps unchanged',
    'production_integrated':False})
print(root)
