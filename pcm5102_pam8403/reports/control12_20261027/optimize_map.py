from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/hc05_keymap.v';s=p.read_text(encoding='utf-8')
s=s.replace('output reg [CONTROL_KEYS*8-1:0] note_map','output wire [CONTROL_KEYS*8-1:0] note_map')
anchor='    localparam COLLECT=0,'
insert='''    // Legal pitches 60..72 have unique low nibbles (C..F,0..8).
    // Store only these four bits; reconstruct the fixed high nibble.
    reg [CONTROL_KEYS*4-1:0] map_nibbles;
    function [CONTROL_KEYS*4-1:0] pack_map;
        input [CONTROL_KEYS*8-1:0] mapping;integer n;
        begin for(n=0;n<CONTROL_KEYS;n=n+1)pack_map[n*4+:4]=mapping[n*8+:4];end
    endfunction
    genvar map_key;
    generate for(map_key=0;map_key<CONTROL_KEYS;map_key=map_key+1)begin: map_slots
        wire [3:0] low=map_nibbles[map_key*4+:4];
        assign note_map[map_key*8+:8]={low>=12 ? 4'd3 : 4'd4,low};
    end endgenerate
'''
assert anchor in s;s=s.replace(anchor,insert+anchor)
s=s.replace('note_map<=DEFAULT_MAP','map_nibbles<=pack_map(DEFAULT_MAP)')
s=s.replace("note_map[(line[26:24]-3'd1)*8 +: 8]<=requested_note", "map_nibbles[(line[26:24]-3'd1)*4 +: 4]<=requested_note[3:0]")
s=s.replace("note_map[(value0[3:0]-4'd1)*8 +:8]<=accumulator[7:0]", "map_nibbles[(value0[3:0]-4'd1)*4 +:4]<=accumulator[3:0]")
p.write_text(s,encoding='utf-8')
p=P/'src/fsr_pitch_scaler.v';s=p.read_text(encoding='utf-8').replace('syn_ramstyle="distributed_ram"','syn_ramstyle="block_ram"');p.write_text(s,encoding='utf-8')
print('Compact pitch map; use final BSRAM for bend targets')
