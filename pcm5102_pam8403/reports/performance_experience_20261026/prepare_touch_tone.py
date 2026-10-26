"""E1 minimal candidate: select sine/triangle for touch, retaining original sensor timbres."""
from work import *
root=candidate('touch_tone');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:70]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('tools/generate_hc05_decoder.py','("TONE_SET", "TONE,", 6)', '("TONE_SET", "TONE,", None)')
edit('tools/generate_hc05_replies.py',"    'EFFECT3,#,##,###,#,##,###\\r\\n',", "    'EFFECT3,#,##,###,#,##,###\\r\\n',\n    'TCHTONE,#,#\\r\\n',")
edit('src/hc05_keymap.v','output reg [31:0] vibrato_inc,','output reg touch_triangle,\n    input wire touch_triangle_applied,\n    output reg [31:0] vibrato_inc,')
edit('src/hc05_keymap.v','master_volume<=16;analog_mode<=0;', 'touch_triangle<=0;master_volume<=16;analog_mode<=0;')
path=p/'src/hc05_keymap.v';s=path.read_text(encoding='utf-8');a=s.index('else if(decoded_command==CMD_TONE_SET)');b=s.index('else if(decoded_command==CMD_VIBRATO_SET)',a)
s=s[:a]+'''else if(decoded_command==CMD_TONE_SET)begin
                            if(line_length==6 && line[7:0]=="?")begin
                                reply<={3'd0,touch_triangle,3'd0,touch_triangle_applied,104'd0};respond(5'd31,6'd13);
                            end else begin control_parse<=13;parse_numbers(5,1);end
                        end
                        '''+s[b:];path.write_text(s,encoding='utf-8')
edit('src/hc05_keymap.v','default:result(7);', '''13:if(field_count==2)begin
                                           if(value0!=0 || accumulator>1)result(2);
                                           else if(!edit_allowed || take_recording)result(1);
                                           else begin touch_triangle<=accumulator[0];result(0);end
                                       end else if(accumulator>7)result(2);
                                       else begin gesture_timbre<=accumulator[2:0];result(0);end
                                    default:result(7);''')
edit('src/hc05_keymap.v','else if(field_index>=field_count-1) result(7);', 'else if(field_index>=field_count-1 && !(control_parse==13 && field_index==0)) result(7);')
edit('src/hc05_keymap.v','if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;', '''if(control_parse==13 && field_index==0)field_count<=2;
                                if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;''')
edit('src/touch_tdm_synth.v','input wire clk,resetn,sample_ce,', 'input wire clk,resetn,sample_ce,\n    input wire triangle_tone,')
edit('src/touch_tdm_synth.v','wire signed [15:0] sine=SHARED_ARITH ? shared_sine : local_sine;', '''wire signed [15:0] triangle_wave=lookup_phase[31] ? $signed(16'h7fff-{lookup_phase[30:16],1'b0}) : $signed({lookup_phase[30:16],1'b0}-16'h8000);
    wire signed [15:0] sine=triangle_tone ? triangle_wave : (SHARED_ARITH ? shared_sine : local_sine);''')
edit('src/top.v','wire [31:0] vibrato_inc;', 'wire touch_triangle,touch_triangle_applied;\n    wire [31:0] vibrato_inc;')
edit('src/top.v','.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),', '.touch_triangle(touch_triangle),.touch_triangle_applied(touch_triangle_applied),\n        .bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),')
edit('src/top.v',"{1'b1,10'd0,gesture_bank,gesture_vibrato,gesture_timbre}","{1'b1,touch_triangle,9'd0,gesture_bank,gesture_vibrato,gesture_timbre}")
edit('src/top.v','touch_tdm_synth #(.VOLUME_SHIFT', '''assign touch_triangle_applied=perf_replay ? (perf_state[511] && perf_state[510]) : touch_triangle;
    touch_tdm_synth #(.VOLUME_SHIFT''')
edit('src/top.v','.physical_gates(perf_playing ? touch_note_gates : physical_notes),', '.triangle_tone(touch_triangle_applied),.physical_gates(perf_playing ? touch_note_gates : physical_notes),')
for script in ('generate_hc05_decoder.py','generate_hc05_replies.py'):
    subprocess.run([sys.executable,str(p/'tools'/script)],check=True)
save(root/'candidate_scope.json',{'scope':'touch sine/triangle only, no harmonic editor; fixed-phase triangle, potential aliasing must be measured before acceptance',
    'protocol':'TONE,0,0 sine; TONE,0,1 triangle; legacy TONE,0..7 retains shared sensor timbres; TONE,? touch query',
    'TAKE':'same528, formerly zero bit510 stores touch tone, FX3 bit511 identifies support; old records sine',
    'cost_conflict':'bit510 overlaps another independent candidate, joint integration would need relocation',
    'not_yet_validated':['tone spectrum and DC','normal note/expression frame deadlines','MIDI and app controls'],
    'production_integrated':False})
print(root)
