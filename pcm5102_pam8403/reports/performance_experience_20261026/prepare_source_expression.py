"""E3 initial candidate: latch independent IR/gesture vibrato enable per note.
Rate, depth and onset wait remain shared. No per-voice delay counters or new DSP.
"""
from work import *
root=candidate('source_expression_v1');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:75]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('tools/generate_hc05_decoder.py','("VIBRATO_SET", "VIBRATO,", 9)', '("VIBRATO_SET", "VIBRATO,", None)')
edit('tools/generate_hc05_replies.py',"    'EFFECT3,#,##,###,#,##,###\\r\\n',", "    'EFFECT3,#,##,###,#,##,###\\r\\n',\n    'VIBSRC,#,#\\r\\n',")
edit('src/hc05_keymap.v','output reg [31:0] vibrato_inc,','output reg [1:0] source_vibrato,\n    input wire [1:0] source_vibrato_applied,\n    output reg [31:0] vibrato_inc,')
edit('src/hc05_keymap.v','master_volume<=16;analog_mode<=0;', 'source_vibrato<=0;master_volume<=16;analog_mode<=0;')
path=p/'src/hc05_keymap.v';s=path.read_text(encoding='utf-8');a=s.index('else if(decoded_command==CMD_VIBRATO_SET)');b=s.index('else if(decoded_command==CMD_BANK_SET)',a)
s=s[:a]+'''else if(decoded_command==CMD_VIBRATO_SET)begin
                            if(line_length==9 && line[7:0]=="?")begin
                                reply<={2'd0,source_vibrato,2'd0,source_vibrato_applied,104'd0};respond(5'd31,6'd12);
                            end else begin control_parse<=13;parse_numbers(8,1);end
                        end
                        '''+s[b:];path.write_text(s,encoding='utf-8')
edit('src/hc05_keymap.v','default:result(7);', '''13:if(field_count==2)begin
                                           if(value0<1 || value0>2 || accumulator>1)result(2);
                                           else begin
                                               source_vibrato[value0[1:0]-2'd1]<=accumulator[0];
                                               gesture_vibrato<=accumulator[0] || source_vibrato[value0==1 ? 1 : 0];result(0);
                                           end
                                       end else if(accumulator>1)result(2);
                                       else begin source_vibrato<={2{accumulator[0]}};gesture_vibrato<=accumulator[0];result(0);end
                                    default:result(7);''')
edit('src/hc05_keymap.v','else if(field_index>=field_count-1) result(7);', 'else if(field_index>=field_count-1 && !(control_parse==13 && field_index==0)) result(7);')
edit('src/hc05_keymap.v','if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;', '''if(control_parse==13 && field_index==0)field_count<=2;
                                if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;''')
for name in ('src/gesture_top.v','src/sensor_poly_audio.v'):
    edit(name,'input wire [31:0] vibrato_inc,','input wire [1:0] source_vibrato,\n    input wire [31:0] vibrato_inc,')
edit('src/gesture_top.v','.vibrato_inc(vibrato_inc),','.source_vibrato(source_vibrato),.vibrato_inc(vibrato_inc),')
edit('src/sensor_poly_audio.v','reg [31:0] pitches[0:3];','reg [31:0] pitches[0:3];\n    reg vib_tags[0:3];')
edit('src/sensor_poly_audio.v','if(take_ir)begin pitches[wr]<=ir_inc;', 'if(take_ir)begin vib_tags[wr]<=source_vibrato[0];pitches[wr]<=ir_inc;')
edit('src/sensor_poly_audio.v','if(take_gesture)begin pitches[second_wr]<=gesture_inc;', 'if(take_gesture)begin vib_tags[second_wr]<=source_vibrato[1];pitches[second_wr]<=gesture_inc;')
edit('src/sensor_poly_audio.v','.PRESET_FRAMES(1),.NOTE_FRAMES', '.SOURCE_VIB(1),.PRESET_FRAMES(1),.NOTE_FRAMES')
edit('src/sensor_poly_audio.v','.event_valid(pop),.event_inc(next_event[31:0]),', '.event_vibrato(vib_tags[rd]),.event_valid(pop),.event_inc(next_event[31:0]),')
edit('src/tdm_synth.v','parameter integer PRESET_FRAMES=0,', 'parameter integer SOURCE_VIB=0,\n    parameter integer PRESET_FRAMES=0,')
edit('src/tdm_synth.v','input wire event_valid, chord_valid, test_valid, vibrato_enabled,', 'input wire event_valid, chord_valid, test_valid, vibrato_enabled,\n    input wire event_vibrato,')
edit('src/tdm_synth.v','localparam integer CONTEXT_BITS=556, CONTEXT_PAD=576;', 'localparam integer CONTEXT_BITS=556+(SOURCE_VIB ? 2 : 0), CONTEXT_PAD=576;')
edit('src/tdm_synth.v','localparam integer FIFO_BITS=PRESET_FRAMES ? 167 : 184;', 'localparam integer FIFO_BITS=(PRESET_FRAMES ? 167 : 184)+(SOURCE_VIB ? 1 : 0);')
edit('src/tdm_synth.v','reg [183:0] command;', 'reg [184:0] command;\n    reg request_vibrato;\n    wire source_vib_on=SOURCE_VIB ? context_work[556] : 1\'b1;\n    wire next_vib=(pending && delay_frames==0) ? context_work[557] : context_work[556];')
edit('src/tdm_synth.v','wire [183:0] fifo_input={', "wire [184:0] fifo_input={(SOURCE_VIB ? event_vibrato : 1'b1),")
edit('src/tdm_synth.v','wire [183:0] fifo_command;', 'wire [184:0] fifo_command;')
edit('src/tdm_synth.v','assign fifo_command={fifo_q[166:35],', 'assign fifo_command={(SOURCE_VIB ? fifo_q[FIFO_BITS-1] : 1\'b1),fifo_q[166:35],')
edit('src/tdm_synth.v','PRESET_FRAMES ? {fifo_input[183:52],fifo_input[34:0]} : fifo_input;', "PRESET_FRAMES ? {(SOURCE_VIB ? fifo_input[184] : 1'b1),fifo_input[183:52],fifo_input[34:0]} : fifo_input;")
edit('src/tdm_synth.v','wire [CONTEXT_BITS-1:0] stepped_context={', 'wire [CONTEXT_BITS-1:0] stepped_context={context_work[557],next_vib,')
edit('src/tdm_synth.v',"default:event_data={20'd0,request_adsr[129:114]};", "default:event_data={18'd0,request_vibrato,context_q[16],request_adsr[129:114]};")
edit('src/tdm_synth.v','request_adsr<=0;env_ramp_gain<=0;', 'request_vibrato<=0;request_adsr<=0;env_ramp_gain<=0;')
edit('src/tdm_synth.v','slot<=allocation; request_inc<=command_inc;', "slot<=allocation;request_vibrato<=SOURCE_VIB ? command[184] : 1'b1;request_inc<=command_inc;")
edit('src/tdm_synth.v','context_work<=assembled_context[555:0];','context_work<=assembled_context[CONTEXT_BITS-1:0];')
edit('src/tdm_synth.v','mul_b<=lfo_scaled;state<=PITCH_WAIT;', "mul_b<=source_vib_on ? lfo_scaled : 18'sd0;state<=PITCH_WAIT;")
edit('src/tdm_synth.v','BODY_WAIT:begin voice_write_word=2;', "PITCH_WAIT:if(SOURCE_VIB)begin voice_write_word=15;voice_write_data={18'd0,context_work[557],next_vib,context_work[555:540]};end else voice_we=0;\n            BODY_WAIT:begin voice_write_word=2;")
edit('src/top.v','wire [31:0] vibrato_inc;', 'wire [1:0] source_vibrato,source_vibrato_applied;\n    wire [31:0] vibrato_inc;')
# Different connections for the keymap (configuration) and audio producer (replay-aware).
edit('src/top.v','.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),', '.source_vibrato(source_vibrato),.source_vibrato_applied(source_vibrato_applied),\n        .bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),')
edit('src/top.v','.control_vibrato(perf_replay ?', '.source_vibrato(source_vibrato_applied),.control_vibrato(perf_replay ?')
edit('src/top.v',"{1'b1,10'd0,gesture_bank,gesture_vibrato,gesture_timbre}","{1'b1,source_vibrato,8'd0,gesture_bank,gesture_vibrato,gesture_timbre}")
edit('src/top.v',"{1'b0,fx_settings,fx_mask,effective_wet}","{1'b1,fx_settings,fx_mask,effective_wet}")
edit('src/top.v','wire [1:0] old_replay_mode=', "assign source_vibrato_applied=perf_replay ? (perf_state[495] ? perf_state[510:509] : {2{perf_state[499]}}) : source_vibrato;\n    wire [1:0] old_replay_mode=")
for script in ('generate_hc05_decoder.py','generate_hc05_replies.py'):
    subprocess.run([sys.executable,str(p/'tools'/script)],check=True)
save(root/'candidate_scope.json',{'scope':'IR/gesture note-on vibrato enable snapshots; shared rate/depth/onset wait preserved',
    'protocol':'VIBRATO,1,en IR / VIBRATO,2,en gesture / VIBRATO,?; old VIBRATO,en both',
    'geometry':'producer tag+1, event FIFO+1 bit, existing576-bit context uses 2 spare bits; new context word15 write uses free PITCH_WAIT slot',
    'TAKE':'marker495, config510:509, old shared vib499 ->both; independent candidate only',
    'not_yet_validated':['simultaneous producers','pending to active flag timing','long-frame interaction','App'],
    'production_integrated':False})
print(root)
