"""E2 static IR tuning hardware screen; no promise of TAKE format compatibility yet."""
from work import *
root=candidate('ir_tuning');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:70]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('tools/generate_hc05_decoder.py','("BANK_SET", "BANK,", 6)', '("BANK_SET", "BANK,", None)')
edit('tools/generate_hc05_replies.py',"    'EFFECT3,#,##,###,#,##,###\\r\\n',", "    'EFFECT3,#,##,###,#,##,###\\r\\n',\n    'IRMAP,' + ','.join(['##']*8) + '\\r\\n',")
edit('src/hc05_keymap.v','output reg [31:0] vibrato_inc,','output reg [55:0] ir_tuning,\n    output reg [31:0] vibrato_inc,')
edit('src/hc05_keymap.v','master_volume<=16;analog_mode<=0;', "ir_tuning<={7'd72,7'd71,7'd69,7'd67,7'd65,7'd64,7'd62,7'd60};master_volume<=16;analog_mode<=0;")
path=p/'src/hc05_keymap.v';s=path.read_text(encoding='utf-8');a=s.index('else if(decoded_command==CMD_BANK_SET)');b=s.index('else if(decoded_command==CMD_MAP_QUERY)',a)
s=s[:a]+'''else if(decoded_command==CMD_BANK_SET)begin
                            if(line_length==6 && line[7:0]=="?")begin
                                reply<={'''+','.join("1'b0,ir_tuning[%d +:7]"%(7*n) for n in range(8))+''',48'd0};respond(5'd31,6'd31);
                            end else begin control_parse<=13;parse_numbers(5,1);end
                        end
                        '''+s[b:];path.write_text(s,encoding='utf-8')
edit('src/hc05_keymap.v','default:result(7);', '''13:if(field_count==2)begin
                                           if(value0<1 || value0>8 || accumulator<48 || accumulator>84)result(2);
                                           else if(!edit_allowed || take_recording)result(1);
                                           else begin ir_tuning[(value0[2:0]-3'd1)*7 +:7]<=accumulator[6:0];result(0);end
                                       end else if(accumulator>1)result(2);
                                       else begin gesture_bank<=accumulator[0];result(0);end
                                    default:result(7);''')
edit('src/hc05_keymap.v','else if(field_index>=field_count-1) result(7);', 'else if(field_index>=field_count-1 && !(control_parse==13 && field_index==0)) result(7);')
edit('src/hc05_keymap.v','if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;', '''if(control_parse==13 && field_index==0)field_count<=2;
                                if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;''')
for name in ('src/gesture_top.v','src/sensor_poly_audio.v'):
    edit(name,'input wire [31:0] vibrato_inc,','input wire [55:0] ir_tuning,\n    input wire [31:0] vibrato_inc,')
edit('src/gesture_top.v','.vibrato_inc(vibrato_inc),','.ir_tuning(ir_tuning),.vibrato_inc(vibrato_inc),')
path=p/'src/sensor_poly_audio.v';s=path.read_text(encoding='utf-8');a=s.index('        case (ir_note_index)');b=s.index('        endcase',a)+len('        endcase')
s=s[:a]+'        ir_inc=ir_step(ir_tuning[ir_note_index*7 +:7]);'+s[b:]
function='''    function [31:0] ir_step;
        input [6:0] note;
        begin case(note)
'''+''.join(f"            {note}:ir_step=32'd{round(440*2**((note-69)/12)*2**32/(50_000_000/1024))};\n" for note in range(48,85))+'''            default:ir_step=0;
        endcase end
    endfunction
'''
s=s.replace('    reg [31:0] gesture_inc, ir_inc;',function+'    reg [31:0] gesture_inc, ir_inc;');path.write_text(s,encoding='utf-8')
edit('src/top.v','wire [31:0] vibrato_inc;', 'wire [55:0] ir_tuning;\n    wire [31:0] vibrato_inc;')
edit('src/top.v','.vibrato_inc(vibrato_inc),','.ir_tuning(ir_tuning),.vibrato_inc(vibrato_inc),')
for script in ('generate_hc05_decoder.py','generate_hc05_replies.py'):
    subprocess.run([sys.executable,str(p/'tools'/script)],check=True)
save(root/'candidate_scope.json',{'scope':'eight IR strings static MIDI48..84, default original pitches, atomic per-string edits while idle',
    'protocol':'BANK,string,note / BANK,? -> IRMAP eight values; legacy BANK,0/1 continues gesture bank',
    'hardware_screen_only':True,'TAKE_incomplete':'live IR table is not yet stored in528-bit snapshot; do not accept regardless of PnR until addressed',
    'not_yet_validated':['new/old TAKE tuning preservation','full note/queue tests','App controls and error handling'],
    'production_integrated':False})
print(root)
