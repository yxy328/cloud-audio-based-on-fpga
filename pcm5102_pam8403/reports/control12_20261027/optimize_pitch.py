from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/fsr_pitch_scaler.v';s=p.read_text()
s=s.replace('PER_VOICE_BEND=0, CONTROL_KEYS=7,','PER_VOICE_BEND=0, CONTROL_KEYS=7, MAP_ROM=0,')
s=s.replace('parameter integer CONTROL_KEYS=7,','parameter integer CONTROL_KEYS=7, MAP_ROM=0,')
s=s.replace('input wire [CONTROL_KEYS*32-1:0] note_increments,','input wire [CONTROL_KEYS*32-1:0] note_increments,\n    input wire [CONTROL_KEYS*8-1:0] note_map,')
s=s.replace('#(.CONTROL_KEYS(CONTROL_KEYS),.NOTE_INCREMENTS', '#(.CONTROL_KEYS(CONTROL_KEYS),.MAP_ROM(MAP_ROM),.NOTE_INCREMENTS')
s=s.replace('.note_increments(note_increments),.bend_write', '.note_increments(note_increments),.note_map(note_map),.bend_write')
anchor='    reg [15:0] frame_ratio,selected_bend,mul_ratio;'
steps=[23012828,24381242,25831026,27367019,28994347,30718440,32545054,34480283,36530588,38702809,41004198,43442435,46025656]
rom='    wire [25:0] scan_base;\n    generate if(MAP_ROM)begin: pitch_rom\n        (* syn_romstyle="block_rom" *) reg [25:0] memory[0:255];\n        reg [25:0] q;integer n;\n        initial begin\n            for(n=0;n<256;n=n+1)memory[n]=0;\n'
rom+=''.join(f"            memory[{60+i}]=26'd{v};\n" for i,v in enumerate(steps))
rom+='        end\n        always @(posedge clk)q<=memory[note_map[index*8+:8]];\n        assign scan_base=q;\n    end else assign scan_base=note_increments[index*32+:26];endgenerate\n'
assert anchor in s;s=s.replace(anchor,rom+anchor)
s=s.replace('mul_base<=note_increments[index*32 +: 26]', 'mul_base<=scan_base')
p.write_text(s)
p=P/'src/top.v';s=p.read_text();a=s.index('    midi_note_lut #(');b=s.index('    );',a)+len('    );')
old=s[a:b];s=s[:a]+'    generate if(CONTROL_KEYS==7)begin: legacy_note_rom\n'+old+'\n    end else assign touch_base_increments=0;endgenerate'+s[b:]
s=s.replace('fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),','fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),.MAP_ROM(CONTROL_KEYS==12),')
s=s.replace('.note_increments(touch_base_increments),', '.note_increments(touch_base_increments),.note_map(touch_note_map),')
p.write_text(s)
print('Merged MIDI ROM into pitch scan; production inputs unchanged')
