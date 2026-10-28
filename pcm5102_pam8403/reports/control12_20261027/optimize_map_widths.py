from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
F=P/'sim/build/unified/control12_shared_reply/pcm5102_pam8403'
# Retain the RAM prototypes as frozen evidence; return the audio and TAKE
# datapaths to the fully routed, timing-valid shared_reply implementation.
for name in ['top.v','touch_tdm_synth.v','performance_take.v','fsr_pitch_scaler.v','hc05_keymap.v']:
    (P/'src'/name).write_bytes((F/'src'/name).read_bytes())
for name in ['tb_control12_step_ram.v','tb_control12_step_ram_fast.v']:
    p=P/'sim'/name;d=R/'packed_step_tests';d.mkdir(exist_ok=True)
    if p.exists():p.rename(d/name)
p=P/'src/downloadable_song.v';s=(R/'narrow_downloadable_song.v').read_text(encoding='utf-8')
def sub(a,b):
    global s
    assert a in s,a[:100]
    s=s.replace(a,b)
sub('parameter integer ENABLE_LOOKAHEAD=0,','parameter integer ENABLE_LOOKAHEAD=0, TRUSTED_MAP=0,')
sub('reg [CONTROL_KEYS*8-1:0] checked_map;','''localparam MAP_BITS=TRUSTED_MAP ? 4 : 8;
    reg [CONTROL_KEYS*MAP_BITS-1:0] checked_map;
    function [CONTROL_KEYS*MAP_BITS-1:0] pack_checked_map;
        input [CONTROL_KEYS*8-1:0] notes;
        integer key;
        begin
            for(key=0;key<CONTROL_KEYS;key=key+1)
                pack_checked_map[key*MAP_BITS+:MAP_BITS]=notes[key*8+:MAP_BITS];
        end
    endfunction''')
sub('wire [7:0] map_pitch=checked_map[map_index*8+:8];','''wire [3:0] map_low=checked_map[map_index*MAP_BITS+:4];
    wire [7:0] map_pitch;
    generate if(TRUSTED_MAP)begin: compact_map
        assign map_pitch={map_low>=12 ? 4'd3 : 4'd4,map_low};
    end else assign map_pitch=checked_map[map_index*MAP_BITS+:8];endgenerate''')
sub('checked_map<=note_map','checked_map<=pack_checked_map(note_map)')
p.write_text(s,encoding='utf-8')
p=P/'src/hc05_keymap.v';s=p.read_text(encoding='utf-8')
sub('downloadable_song #(.CONTROL_KEYS(CONTROL_KEYS),', 'downloadable_song #(.CONTROL_KEYS(CONTROL_KEYS),.TRUSTED_MAP(CONTROL_KEYS==12),')
sub('wire [7:0] map_reply_note=note_map[map_reply_key*8+:8];','''wire [3:0] map_reply_low=map_nibbles[map_reply_key*4+:4];
    wire map_reply_sixty=map_reply_low<6 || map_reply_low>=12;''')
sub('(map_reply_note<70 ? map_reply_note[3:0]-4\'d12 : map_reply_note[3:0]-4\'d6)',"(map_reply_sixty ? map_reply_low-4'd12 : map_reply_low-4'd6)")
sub('(map_reply_note<70 ? 4\'d6 : 4\'d7)',"(map_reply_sixty ? 4'd6 : 4'd7)")
p.write_text(s,encoding='utf-8')
p=P/'src/fsr_pitch_scaler.v';s=p.read_text(encoding='utf-8')
sub('MAP_ROM=0, TRUSTED_BEND_WRITE=0,','MAP_ROM=0, TRUSTED_BEND_WRITE=0, COMPACT_MAP=0,')
sub('.TRUSTED_BEND_WRITE(TRUSTED_BEND_WRITE),.NOTE_INCREMENTS', '.TRUSTED_BEND_WRITE(TRUSTED_BEND_WRITE),.COMPACT_MAP(COMPACT_MAP),.NOTE_INCREMENTS')
sub('always @(posedge clk)q<=memory[note_map[index*8+:8]];','''wire [3:0] map_low=note_map[index*8+:4];
        wire [7:0] selected_map;
        if(COMPACT_MAP)assign selected_map={map_low>=12 ? 4'd3 : 4'd4,map_low};
        else assign selected_map=note_map[index*8+:8];
        always @(posedge clk)q<=memory[selected_map];''')
p.write_text(s,encoding='utf-8')
p=P/'src/top.v';s=p.read_text(encoding='utf-8')
sub('.TRUSTED_BEND_WRITE(CONTROL_KEYS==12),','.TRUSTED_BEND_WRITE(CONTROL_KEYS==12),.COMPACT_MAP(CONTROL_KEYS==12),')
p.write_text(s,encoding='utf-8')
p=P/'sim/tb_control12_pitch.v';s=p.read_text(encoding='utf-8')
sub('.MAP_ROM(1),.PER_VOICE_BEND(1)', '.MAP_ROM(1),.COMPACT_MAP(1),.PER_VOICE_BEND(1)')
p.write_text(s,encoding='utf-8')
# The frame guard belongs only to the discarded RAM prototypes.
p=P/'sim/tb_control12_take.v';s=p.read_text(encoding='utf-8')
sub(',.FRAME_GUARD(32)','')
p.write_text(s,encoding='utf-8')
print('Restored validated audio/TAKE path; bounded mask indices and compact trusted map snapshots/selectors')
