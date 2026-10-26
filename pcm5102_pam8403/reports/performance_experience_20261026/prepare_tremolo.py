"""One isolated global tremolo candidate. No production source is changed."""
from work import *

root = candidate('tremolo')
p = root/PROJECT.name
def edit(name, old, new):
    path=p/name;text=path.read_text(encoding='utf-8-sig');assert old in text,(name,old[:80]);path.write_text(text.replace(old,new),encoding='utf-8')

edit('src/audio_fx_chain.v','input wire [11:0] wet_mix,','input wire [11:0] wet_mix,\n    input wire [7:0] tremolo,')
edit('src/audio_fx_chain.v','R_WET_MUL=22,R_MIX=23;', 'R_WET_MUL=22,R_MIX=23,\n        T_DEPTH=24,T_GAIN=25,T_AUDIO=26,T_OUT=27;')
edit('src/audio_fx_chain.v','reg [4:0] state;', '''reg [4:0] state;
    reg [23:0] trem_phase;
    reg [7:0] held_tremolo,trem_gain;
    wire [7:0] trem_triangle=trem_phase[23] ? 8'd128-{1'b0,trem_phase[22:16]} : {1'b0,trem_phase[22:16]};
    reg [11:0] trem_step;
    always @* case(tremolo[7:4])
        1:trem_step=344;2:trem_step=687;3:trem_step=1031;4:trem_step=1374;
        5:trem_step=1718;6:trem_step=2062;7:trem_step=2405;8:trem_step=2749;
        default:trem_step=0;
    endcase
    wire signed [17:0] trem_scaled=(product>>>7)+$signed({26'd0,(product[26] && (|product[6:0]))});''')
edit('src/audio_fx_chain.v','default:mul_b=0;', '''T_DEPTH:begin mul_a=$signed({1'b0,trem_triangle});mul_b=$signed({5'd0,held_tremolo[3:0]});end
        T_AUDIO:begin mul_a=$signed(stage);mul_b=$signed({1'b0,trem_gain});end
        default:mul_b=0;''')
edit('src/audio_fx_chain.v','state<=IDLE;previous_mask<=0;', 'state<=IDLE;trem_phase<=0;held_tremolo<=0;trem_gain<=128;previous_mask<=0;')
edit('src/audio_fx_chain.v','state==R_FB_MUL || state==R_WET_MUL)product<=mul_a*mul_b;', 'state==R_FB_MUL || state==R_WET_MUL || state==T_DEPTH || state==T_AUDIO)product<=mul_a*mul_b;')
edit('src/audio_fx_chain.v','held_mask<=mask;previous_mask<=mask;', '''held_tremolo<=tremolo;
                trem_phase<=tremolo[7:4]==0 ? 24'd0 : trem_phase+trem_step;
                held_mask<=mask;previous_mask<=mask;''')
edit('src/audio_fx_chain.v','R_MIX:begin sample<=held_mask[2] ? saturate(mixed) : stage;valid<=1;state<=IDLE;end', '''R_MIX:begin
                if(held_tremolo[7:4]!=0 && held_tremolo[3:0]!=0)begin
                    if(held_mask[2])stage<=saturate(mixed);state<=T_DEPTH;
                end else begin sample<=held_mask[2] ? saturate(mixed) : stage;valid<=1;state<=IDLE;end
            end
            T_DEPTH:state<=T_GAIN;
            T_GAIN:begin trem_gain<=8'd128-(product>>3);state<=T_AUDIO;end
            T_AUDIO:state<=T_OUT;
            T_OUT:begin sample<=trem_scaled[15:0];valid<=1;state<=IDLE;end''')

edit('src/hc05_keymap.v','output reg [31:0] vibrato_inc,','output reg [7:0] tremolo_config,\n    input wire [7:0] tremolo_applied,\n    output reg [31:0] vibrato_inc,')
edit('src/hc05_keymap.v','master_volume<=16;analog_mode<=0;', 'tremolo_config<=0;master_volume<=16;analog_mode<=0;')
edit('src/hc05_keymap.v','if(line_length==8 && line[7:0]=="?")begin','''if(line_length==10 && line[23:0]=="4,?")begin
                                reply<={tremolo_config,tremolo_applied,96'd0};respond(5'd31,6'd12);
                            end else if(line_length==8 && line[7:0]=="?")begin''')
edit('src/hc05_keymap.v','2:if(field_count==4)begin','''2:if(field_count==3)begin
                                          if(value0!=4 || value1>8 || accumulator>8)result(2);
                                          else begin tremolo_config<={value1[3:0],accumulator[3:0]};result(0);end
                                      end else if(field_count==4)begin''')
edit('src/hc05_keymap.v','if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;', '''if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;
                                if(control_parse==2 && field_index==0 && accumulator==4)field_count<=3;''')
edit('tools/generate_hc05_replies.py',"    'EFFECT3,#,##,###,#,##,###\\r\\n',", "    'EFFECT3,#,##,###,#,##,###\\r\\n',\n    'TREM,##,##\\r\\n',")
subprocess.run([sys.executable,str(p/'tools/generate_hc05_replies.py')],check=True)

edit('src/top.v','wire [31:0] vibrato_inc;', 'wire [7:0] tremolo_config,tremolo_applied;\n    wire [31:0] vibrato_inc;')
edit('src/top.v','.vibrato_inc(vibrato_inc),', '.tremolo_config(tremolo_config),.tremolo_applied(tremolo_applied),.vibrato_inc(vibrato_inc),')
edit('src/top.v',"{1'b1,10'd0,gesture_bank,gesture_vibrato,gesture_timbre}","{1'b1,2'd0,tremolo_config,gesture_bank,gesture_vibrato,gesture_timbre}")
edit('src/top.v','audio_fx_chain u_effects (', '''assign tremolo_applied=perf_replay ? (perf_state[511] ? perf_state[508:501] : 8'd0) : tremolo_config;
    audio_fx_chain u_effects (''')
edit('src/top.v','.mask(fx_applied_mask),.settings(fx_applied_settings),.wet_mix(fx_applied_mix),', '.mask(fx_applied_mask),.settings(fx_applied_settings),.wet_mix(fx_applied_mix),.tremolo(tremolo_applied),')
edit('src/top.v','fx_applied_mask==0 ? dry_audio_sample : effect_sample','(fx_applied_mask==0 && (tremolo_applied[7:4]==0 || tremolo_applied[3:0]==0)) ? dry_audio_sample : effect_sample')
save(root/'candidate_scope.json',{'global_tremolo':'after C/D/R, before existing master volume slew',
    'protocol':'EFFECT,4,rate,depth / EFFECT,4,?', 'rate_Hz':'0 off; 1..8 nominal Hz',
    'depth':'0..8: 0..100% attenuation, discrete 1/128 gain',
    'TAKE':'same 528 bits; formerly zero bits 508:501 store config, old records decode off',
    'phase':'free global phase; restart off / PANIC / TAKE end; phase is not recorded',
    'shared_mult':True,'max_added_clocks':4,'production_integrated':False})
print(root)
