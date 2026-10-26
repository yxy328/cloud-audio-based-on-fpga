"""Independent two-bus static volume candidate; 0 / 25 / 50 / 100 percent.
IR and gesture remain one bus; this is deliberately not three independent sources.
"""
from work import *
root=candidate('source_volume_v2');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:70]);path.write_text(s.replace(old,new),encoding='utf-8')
edit('src/hc05_keymap.v','output reg [31:0] vibrato_inc,','output reg [3:0] source_volume,\n    input wire [3:0] source_volume_applied,\n    output reg [31:0] vibrato_inc,')
edit('src/hc05_keymap.v','master_volume<=16;analog_mode<=0;', "source_volume<=4'hf;master_volume<=16;analog_mode<=0;")
edit('src/hc05_keymap.v','control_parse<=4;parse_numbers(7,1);', '''if(line_length==8 && line[7:0]=="?")begin
                                reply<={source_volume,source_volume_applied,104'd0};respond(5'd31,6'd12);
                            end else begin control_parse<=4;parse_numbers(7,1);end''')
edit('src/hc05_keymap.v','4:if(accumulator>16)result(2);', '''4:if(field_count==2)begin
                                          if(value0<1 || value0>2 || accumulator>3)result(2);
                                          else begin
                                              if(value0==1)source_volume[1:0]<=accumulator[1:0];
                                              else source_volume[3:2]<=accumulator[1:0];result(0);
                                          end
                                      end else if(accumulator>16)result(2);''')
edit('src/hc05_keymap.v','else if(field_index>=field_count-1) result(7);', 'else if(field_index>=field_count-1 && !(control_parse==4 && field_index==0)) result(7);')
edit('src/hc05_keymap.v','if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;', '''if(control_parse==4 && field_index==0)field_count<=2;
                                if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;''')
edit('tools/generate_hc05_replies.py',"    'EFFECT3,#,##,###,#,##,###\\r\\n',", "    'EFFECT3,#,##,###,#,##,###\\r\\n',\n    'SRCVOL,#,#\\r\\n',")
subprocess.run([sys.executable,str(p/'tools/generate_hc05_replies.py')],check=True)
edit('src/top.v','wire [31:0] vibrato_inc;', 'wire [3:0] source_volume,source_volume_applied;\n    wire [31:0] vibrato_inc;')
edit('src/top.v','.bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),', '.source_volume(source_volume),.source_volume_applied(source_volume_applied),\n        .bend_min(bend_min),.bend_max(bend_max),.bend_slew(bend_slew),.tuning_ratio(tuning_ratio),')
# The previous match appears in keymap only (the touch synth has no tuning_ratio there).
edit('src/top.v',"{1'b1,10'd0,gesture_bank,gesture_vibrato,gesture_timbre}","{1'b1,source_volume,6'd0,gesture_bank,gesture_vibrato,gesture_timbre}")
edit('src/top.v',"{1'b0,fx_settings,fx_mask,effective_wet}","{1'b1,fx_settings,fx_mask,effective_wet}")
edit('src/top.v','audio_mixer u_output_mix', '''assign source_volume_applied=perf_replay ? (perf_state[495] ? perf_state[510:507] : 4'hf) : source_volume;
    function signed [15:0] source_attenuate;
        input signed [15:0] pcm;input [1:0] level;
        begin case(level)
            0:source_attenuate=0;
            1:source_attenuate=(pcm>>>2)+$signed({15'd0,pcm[15] && (|pcm[1:0])});
            2:source_attenuate=(pcm>>>1)+$signed({15'd0,pcm[15] && pcm[0]});
            default:source_attenuate=pcm;
        endcase end
    endfunction
    audio_mixer u_output_mix''')
edit('src/top.v','.sample1(touch_mix0)', '.sample1(source_attenuate(touch_mix0,source_volume_applied[1:0]))')
edit('src/top.v','.sample0(gesture_sample),.sample1(guitar_scaled_sample),', '.sample0(source_attenuate(gesture_sample,source_volume_applied[3:2])),.sample1(guitar_scaled_sample),')
save(root/'candidate_scope.json',{'scope':'touch vs shared IR/gesture, 0/25/50/100%; attenuation before original mixer',
    'protocol':'VOLUME,1,level touch; VOLUME,2,level sensor; VOLUME,? returns SRCVOL; legacy VOLUME,value preserved',
    'no_DSP_increment':'shift implementation chosen because touch has only 12 clocks spare at worst frame',
    'TAKE':'same528; marker495; config510:507; older records unity; overlaps tremolo proposal and requires relocation before joint acceptance',
    'production_integrated':False})
print(root)
