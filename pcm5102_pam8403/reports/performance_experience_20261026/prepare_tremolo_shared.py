"""The one structural alternative: reuse the chorus phase without changing chorus speed.
Four tremolo rates 0.745/1.490/2.980/5.960 Hz, using folded bits of the existing LFO.
"""
from work import *
root=candidate('tremolo_shared','tremolo_v2');p=root/PROJECT.name
def edit(name,old,new):
    path=p/name;s=path.read_text(encoding='utf-8-sig');assert old in s,(name,old[:70]);path.write_text(s.replace(old,new),encoding='utf-8')
path=p/'src/audio_fx_chain.v';s=path.read_text(encoding='utf-8')
start=s.index('    reg [23:0] trem_phase;');end=s.index('    reg [2:0] previous_mask,held_mask;',start)
s=s[:start]+'''    reg [7:0] held_tremolo;
    reg [7:0] trem_triangle;
'''+s[end:]
s=s.replace('T_DEPTH=24,T_GAIN=25,T_AUDIO=26,T_OUT=27;', 'T_DEPTH=24,T_AUDIO=25,T_OUT=26;')
s=s.replace('always @* begin\n        mul_a=', '''always @* begin
        case(held_tremolo[7:4])
            1:trem_triangle=lfo[15] ? 8'd128-{1'b0,lfo[14:8]} : {1'b0,lfo[14:8]};
            2:trem_triangle=lfo[14] ? 8'd128-{1'b0,lfo[13:7]} : {1'b0,lfo[13:7]};
            3:trem_triangle=lfo[13] ? 8'd128-{1'b0,lfo[12:6]} : {1'b0,lfo[12:6]};
            default:trem_triangle=lfo[12] ? 8'd128-{1'b0,lfo[11:5]} : {1'b0,lfo[11:5]};
        endcase
        mul_a=''')
s=s.replace("mul_b=$signed({1'b0,trem_gain});", "mul_b=$signed(9'd128-{1'b0,product[10:3]});")
s=s.replace('trem_phase<=0;held_tremolo<=0;trem_gain<=128;', 'held_tremolo<=0;')
s=s.replace("                trem_phase<=tremolo[7:4]==0 ? 24'd0 : trem_phase+trem_step;\n", '')
s=s.replace('T_DEPTH:state<=T_GAIN;\n            T_GAIN:begin trem_gain<=8\'d128-(product>>3);state<=T_AUDIO;end', 'T_DEPTH:state<=T_AUDIO;')
assert not any(x in s for x in ('trem_phase','trem_step','trem_gain','T_GAIN'))
path.write_text(s,encoding='utf-8')
edit('src/hc05_keymap.v','value0!=4 || value1>8 || accumulator>8','value0!=4 || value1>4 || accumulator>8')
edit('src/hc05_keymap.v','tremolo_config<={value1[3:0],accumulator[3:0]}', "tremolo_config<={1'b0,value1[2:0],accumulator[3:0]}")
save(root/'candidate_scope.json',{'structural_alternative_to':'tremolo_v2',
    'reason':'first complete independent-phase implementation cost34 CLS; only15 CLS admitted',
    'scope':'global after FX before master; same physical fixed-rate chorus phase, independently select four folded tremolo rates',
    'rate_Hz':[48828.125/65536*2**n for n in range(4)],'protocol':'EFFECT,4,rate,depth rate0off/1..4; depth0..8',
    'TAKE':'same cfg field508:501; saves rate/depth, phase not saved; old cfg0 off',
    'same_chorus_speed':True,'shared_DSP':True,'max_added_clocks':3,'production_integrated':False})
print(root)
