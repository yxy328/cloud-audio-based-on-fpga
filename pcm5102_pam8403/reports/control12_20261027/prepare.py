"""Prepare a reversible 12-control candidate; never mutate production inputs."""
from pathlib import Path
import hashlib, json, shutil, subprocess

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
WORK = REPORT / 'candidate'
P = WORK / 'pcm5102_pam8403'

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def edit(name, changes):
    p = P / name
    s = p.read_text(encoding='utf-8')
    for old, new in changes:
        if old not in s:
            raise RuntimeError(f'{name}: missing {old[:100]!r}')
        s = s.replace(old, new)
    p.write_text(s, encoding='utf-8', newline='\n')

def prepare():
    if WORK.exists():
        raise RuntimeError('Candidate exists; do not overwrite an experiment')
    files = []
    for folder in ['pcm5102_pam8403/src', 'pcm5102_pam8403/tools', 'pmod_hub75e/src']:
        for src in (ROOT / folder).rglob('*'):
            if src.is_file() and '__pycache__' not in src.parts:
                rel = src.relative_to(ROOT)
                dst = WORK / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                files.append({'path': rel.as_posix(), 'sha256': digest(src)})
    for src in (ROOT / 'pcm5102_pam8403/sim').rglob('*.v'):
        if 'build' in src.relative_to(ROOT / 'pcm5102_pam8403/sim').parts:
            continue
        dst = WORK / src.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    shutil.copy2(ROOT / 'pcm5102_pam8403/PCM5102_UNIFIED.gprj', P)
    files.append({'path': 'pcm5102_pam8403/PCM5102_UNIFIED.gprj', 'sha256': digest(P / 'PCM5102_UNIFIED.gprj')})
    (P / 'impl').mkdir()
    (REPORT / 'freeze.json').write_text(json.dumps(files, indent=2), encoding='utf-8')

    edit('src/midi_note_lut.v', [
        ('parameter integer BLOCK_ROM=0', 'parameter integer BLOCK_ROM=0, CONTROL_KEYS=7'),
        ('[55:0] note_map', '[CONTROL_KEYS*8-1:0] note_map'),
        ('[223:0] phase_increments', '[CONTROL_KEYS*32-1:0] phase_increments'),
        ('reg [2:0] index=0,held_index=0;', 'reg [$clog2(CONTROL_KEYS)-1:0] index=0,held_index=0;'),
        ('index==6', 'index==CONTROL_KEYS-1'),
        ('voice<7', 'voice<CONTROL_KEYS'), ('key_index<7', 'key_index<CONTROL_KEYS'),
    ])
    edit('src/fsr_pitch_scaler.v', [
        ('parameter integer PER_VOICE_BEND=0,', 'parameter integer PER_VOICE_BEND=0, CONTROL_KEYS=7,'),
        ('module voice_pitch_scaler #(\n', 'module voice_pitch_scaler #(\n    parameter integer CONTROL_KEYS=7,\n'),
        ('[223:0]', '[CONTROL_KEYS*32-1:0]'),
        ('[255:0]', '[(CONTROL_KEYS+1)*32-1:0]'),
        ('input wire [2:0] bend_index', 'input wire [$clog2(CONTROL_KEYS)-1:0] bend_index'),
        ('[6:0] score_keys', '[CONTROL_KEYS-1:0] score_keys'),
        ('#(.NOTE_INCREMENTS(NOTE_INCREMENTS))', '#(.CONTROL_KEYS(CONTROL_KEYS),.NOTE_INCREMENTS(NOTE_INCREMENTS))'),
        ('reg [2:0] select_index, selected_index, product_index;', 'reg [$clog2(CONTROL_KEYS)-1:0] select_index, selected_index, product_index;'),
        ('select_index==6', 'select_index==CONTROL_KEYS-1'),
        ('targets[0:7]', 'targets[0:15]'), ('currents[0:7]', 'currents[0:15]'),
        ('reg [3:0] clear_left;', 'reg [4:0] clear_left;'),
        ('reg [2:0] index,state;', 'reg [$clog2(CONTROL_KEYS)-1:0] index;\n    reg [2:0] state;'),
        ('index<7', 'index<CONTROL_KEYS'),
        ("clear_left[2:0]-3'd1", "clear_left[3:0]-4'd1"),
        ('clear_left<=8', 'clear_left<=CONTROL_KEYS'),
        ('index==7', 'index==CONTROL_KEYS-1'), ('index==6', 'index==CONTROL_KEYS-1'),
    ])
    edit('src/touch_tdm_synth.v', [
        ('parameter integer VOLUME_SHIFT=4, EXTENDED_CONTROL=0,', 'parameter integer VOLUME_SHIFT=4, EXTENDED_CONTROL=0, CONTROL_KEYS=7,'),
        ('input wire [223:0] low_steps,', 'input wire [CONTROL_KEYS*32-1:0] low_steps,\n    input wire legacy_high_keys,'),
        ('reg [223:0] frame_steps;', 'reg [CONTROL_KEYS*32-1:0] frame_steps;\n    reg frame_legacy;'),
        ('frame_gates<=gates;frame_steps<=low_steps;', 'frame_gates<=gates;frame_steps<=low_steps;frame_legacy<=legacy_high_keys;'),
        ('((index<7) ? frame_steps', '((index<7 || (CONTROL_KEYS>7 && !frame_legacy && index<CONTROL_KEYS)) ? frame_steps'),
    ])
    edit('src/downloadable_song.v', [
        ('parameter integer CLK_HZ=50_000_000,', 'parameter integer CLK_HZ=50_000_000, CONTROL_KEYS=7,'),
        ('[55:0]', '[CONTROL_KEYS*8-1:0]'),
        ('[6:0] guide_keys', '[CONTROL_KEYS-1:0] guide_keys'),
        ('[6:0] spawn_keys', '[CONTROL_KEYS-1:0] spawn_keys'),
        ('[6:0] cur_keys', '[CONTROL_KEYS-1:0] cur_keys'),
        ('function [6:0] keys_for_mask', 'function [CONTROL_KEYS-1:0] keys_for_mask'),
        ('wire [6:0] fetched_keys', 'wire [CONTROL_KEYS-1:0] fetched_keys'),
        ('j<7', 'j<CONTROL_KEYS'), ('k<7', 'k<CONTROL_KEYS'),
    ])
    # Old fields 0..32 keep their meaning. Ten 16-bit extension fields follow
    # the original gate word. Both legacy and extended initial groups validate.
    edit('src/performance_take.v', [
        ('CLK_HZ=50000000, WORDS=33, DEPTH=1024', 'CLK_HZ=50000000, WORDS=33, DEPTH=1024, GATE_WORD=WORDS-1, LEGACY_WORDS=WORDS'),
        ('output wire play_valid,', 'output wire play_valid,\n    output reg legacy_playback,'),
        ('word_number==WORDS-1', 'word_number==GATE_WORD'),
        ('held[23:16]==WORDS-1', 'held[23:16]==GATE_WORD'),
        ('live_state[(WORDS-1)*16 +: 16]', 'live_state[GATE_WORD*16 +: 16]'),
        ('initial_next==WORDS', '(initial_next==WORDS || initial_next==LEGACY_WORDS)'),
        ('initial_next!=WORDS', '(initial_next!=WORDS && initial_next!=LEGACY_WORDS)'),
        ('primed<=1;group_active<=0;', 'if(!primed)legacy_playback<=initial_next==LEGACY_WORDS && WORDS!=LEGACY_WORDS;\n                    primed<=1;group_active<=0;'),
        ('primed<=0;has_music<=0;', 'legacy_playback<=0;primed<=0;has_music<=0;'),
    ])
    # The 2048x8 reply ROM still fits a single 18K BSRAM. Its 64-byte pages
    # permit the complete 41-byte 12-key MAP response without a new command.
    edit('tools/generate_hc05_replies.py', [
        ('def generate():', 'def generate(keys=7):'),
        ('rom = [0] * 1024', "templates = FORMATS.copy()\n    templates[19] = 'MAP,' + ','.join(['##'] * keys) + '\\r\\n'\n    rom = [0] * 2048"),
        ('enumerate(FORMATS)', 'enumerate(templates)'),
        ('len(template) <= 32', 'len(template) <= 64'),
        ('kind * 32 + ((len(template) - offset) & 31)', 'kind * 64 + ((len(template) - offset) & 63)'),
        ("path.write_text(expected, encoding='ascii')", "path.write_text(expected, encoding='ascii')\n        (path.parent / 'hc05_reply12.hex').write_text(generate(12), encoding='ascii')"),
    ])
    edit('tools/generate_hc05_decoder.py', [( '("MAP_SET", "MAP,", 8)', '("MAP_SET", "MAP,", None)' )])
    map_digits = ','.join(f'(note_map[{i*8+7}:{i*8}]<70 ? 4\'d6 : 4\'d7),(note_map[{i*8+7}:{i*8}]<70 ? note_map[{i*8+3}:{i*8}]-4\'d12 : note_map[{i*8+3}:{i*8}]-4\'d6)' for i in range(12))
    old_query = next(line for line in (P / 'src/hc05_keymap.v').read_text().splitlines() if 'CMD_MAP_QUERY: reply<=' in line)
    edit('src/hc05_keymap.v', [
        ('parameter integer CLK_HZ=50_000_000,', 'parameter integer CLK_HZ=50_000_000, CONTROL_KEYS=7,'),
        ('[55:0] note_map', '[CONTROL_KEYS*8-1:0] note_map'),
        ('[6:0] guide_keys', '[CONTROL_KEYS-1:0] guide_keys'),
        ('[6:0] spawn_keys', '[CONTROL_KEYS-1:0] spawn_keys'),
        ('output reg [2:0] bend_index', 'output reg [$clog2(CONTROL_KEYS)-1:0] bend_index'),
        ('localparam [55:0] DEFAULT_MAP=', "localparam [CONTROL_KEYS*8-1:0] DEFAULT_MAP=CONTROL_KEYS==12 ? {8'd71,8'd70,8'd69,8'd68,8'd67,8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60} : "),
        ('reply_rom [0:1023]', 'reply_rom [0:2047]'),
        ('initial $readmemh("src/hc05_reply.hex",reply_rom);', 'initial if(CONTROL_KEYS==12)$readmemh("src/hc05_reply12.hex",reply_rom);\n        else $readmemh("src/hc05_reply.hex",reply_rom);'),
        ('{reply_format,reply_remaining[4:0]}', '{reply_format,reply_remaining}'),
        ('downloadable_song #(', 'downloadable_song #(.CONTROL_KEYS(CONTROL_KEYS),'),
        (old_query, '                CMD_MAP_QUERY: if(CONTROL_KEYS==12)reply<={'+map_digits+",16'd0};\n"+old_query.replace("CMD_MAP_QUERY: reply<=", "else reply<=")),
        ("respond(5'd19,6'd26)", "respond(5'd19,CONTROL_KEYS==12 ? 6'd41 : 6'd26)"),
        ('end else if(decoded_command==CMD_MAP_SET && line[23:16]==",") begin', 'end else if(decoded_command==CMD_MAP_SET && CONTROL_KEYS==12) begin\n                            control_parse<=13;parse_numbers(4,2);\n                        end else if(decoded_command==CMD_MAP_SET && line_length==8 && line[23:16]==",") begin'),
        ('default:result(7);\n                                endcase', '13:if(value0<1 || value0>CONTROL_KEYS)respond(5\'d21,6\'d9);\n                                       else if(accumulator<60 || accumulator>72)respond(5\'d22,6\'d10);\n                                       else if(!edit_allowed)result(1);\n                                       else begin note_map[(value0[3:0]-4\'d1)*8 +:8]<=accumulator[7:0];result(0);end\n                                    default:result(7);\n                                endcase'),
        ('value0>7 || accumulator<bend_min', 'value0>CONTROL_KEYS || accumulator<bend_min'),
        ('bend_index<=value0[2:0]-1\'b1', 'bend_index<=value0[$clog2(CONTROL_KEYS)-1:0]-1\'b1'),
    ])
    # Display uses twelve 4-pixel lanes across x=8..55. Power-of-two lane
    # width avoids adding a constant divider on the saturated panel path.
    s = (P / 'src/hub75e_rhythm_display.v').read_text()
    for name in ['touch_keys','guide_keys','spawn_keys','head_memory','head_read_q','head_read_value','keys_s0','upper_notes','panel_heads','memory[0:63]','q;','upper_glyph','lower_glyph','note_rows','notes;','head_write_data']:
        s = s.replace('[6:0] '+name, '[CONTROL_KEYS-1:0] '+name)
    s = s.replace('reg [6:0] q;', 'reg [CONTROL_KEYS-1:0] q;')
    s = s.replace('parameter integer LEAD_MS = 1500,', 'parameter integer LEAD_MS = 1500, CONTROL_KEYS=7,')
    s = s.replace('reg [2:0] lane;', 'reg [3:0] lane;')
    s = s.replace("relative_x = x-6'd4;", "relative_x = x-(CONTROL_KEYS==12 ? 6'd8 : 6'd4);")
    s = s.replace('lane = relative_x[5:3];', "lane = CONTROL_KEYS==12 ? {1'b0,relative_x[5:2]} : {1'b0,relative_x[5:3]};")
    s = s.replace('lane_x = relative_x[2:0];', "lane_x = CONTROL_KEYS==12 ? {1'b0,relative_x[1:0]} : relative_x[2:0];")
    s = s.replace('x >= 4 && x < 60', 'x >= (CONTROL_KEYS==12 ? 8 : 4) && x < (CONTROL_KEYS==12 ? 56 : 60)')
    s = s.replace('lane_x >= 2 && lane_x < 7', 'lane_x >= (CONTROL_KEYS==12 ? 1 : 2) && lane_x < (CONTROL_KEYS==12 ? 3 : 7)')
    (P / 'src/hub75e_rhythm_display.v').write_text(s, encoding='utf-8')
    # top defaults to the legacy geometry for existing regression benches;
    # the unified delivery explicitly selects twelve.
    edit('src/top.v', [
        ('parameter ENABLE_DEMO_SCORE = 0,', 'parameter ENABLE_DEMO_SCORE = 0,\n    parameter integer CONTROL_KEYS=7,'),
        ('wire [527:0] perf_live_state,perf_state;', 'localparam TAKE_WORDS=33+(CONTROL_KEYS-7)*2;\n    wire [TAKE_WORDS*16-1:0] perf_live_state,perf_state;\n    wire perf_legacy;'),
        ('wire [6:0] audition_keys', 'wire [CONTROL_KEYS-1:0] audition_keys'),
        ("{9'd0,audition_keys}", "{{(16-CONTROL_KEYS){1'b0}},audition_keys}"),
        ('wire [255:0] touch_phase_increments', 'wire [(CONTROL_KEYS+1)*32-1:0] touch_phase_increments'),
        ('wire [55:0] touch_note_map', 'wire [CONTROL_KEYS*8-1:0] touch_note_map'),
        ('wire [223:0] touch_base_increments', 'wire [CONTROL_KEYS*32-1:0] touch_base_increments'),
        ('wire [6:0] song_guide_keys', 'wire [CONTROL_KEYS-1:0] song_guide_keys'),
        ('wire [6:0] guide_spawn_keys', 'wire [CONTROL_KEYS-1:0] guide_spawn_keys'),
        ('wire [2:0] bend_index', 'wire [$clog2(CONTROL_KEYS)-1:0] bend_index'),
        ("song_guide_keys : 7'd0", "song_guide_keys : {CONTROL_KEYS{1'b0}}"),
        ('hc05_keymap #(', 'hc05_keymap #(.CONTROL_KEYS(CONTROL_KEYS),'),
        ('midi_note_lut #(', 'midi_note_lut #(.CONTROL_KEYS(CONTROL_KEYS),'),
        ('fsr_pitch_scaler #(', 'fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),'),
        ('touch_tdm_synth #(', 'touch_tdm_synth #(.CONTROL_KEYS(CONTROL_KEYS),'),
        ('hub75e_rhythm_display #(', 'hub75e_rhythm_display #(.CONTROL_KEYS(CONTROL_KEYS),'),
        ('assign perf_live_state={', 'wire [527:0] legacy_live_state={'),
        ('wire synth_sensor_mul,', 'generate if(CONTROL_KEYS>7)begin: extended_take\n        assign perf_live_state={touch_phase_increments[224 +:(CONTROL_KEYS-7)*32],legacy_live_state};\n    end else assign perf_live_state=legacy_live_state;endgenerate\n    wire [CONTROL_KEYS*32-1:0] replay_steps;\n    generate if(CONTROL_KEYS>7)begin: extended_replay\n        assign replay_steps={perf_state[528 +:(CONTROL_KEYS-7)*32],perf_state[223:0]};\n    end else assign replay_steps=perf_state[223:0];endgenerate\n    wire synth_sensor_mul,'),
        ('.low_steps(perf_replay ? perf_state[223:0] : touch_phase_increments[223:0])', '.low_steps(perf_replay ? replay_steps : touch_phase_increments[CONTROL_KEYS*32-1:0]),.legacy_high_keys(perf_replay && perf_legacy)'),
        ('performance_take u_take(', 'performance_take #(.WORDS(TAKE_WORDS),.GATE_WORD(32),.LEGACY_WORDS(33)) u_take('),
        ('.play_state(perf_state),.play_valid(perf_replay)', '.play_state(perf_state),.play_valid(perf_replay),.legacy_playback(perf_legacy)'),
        ('assign perf_state=0;', 'assign perf_legacy=0;assign perf_state=0;'),
    ])
    # HC05 touch_keys belongs to the disabled legacy logger and stays seven;
    # the physical panel touch input is widened separately below.
    s=(P/'src/top.v').read_text()
    anchor=s.index('hub75e_rhythm_display #(')
    s=s[:anchor]+s[anchor:].replace('.touch_keys(touch_keys[6:0])', '.touch_keys(touch_keys[CONTROL_KEYS-1:0])')
    (P/'src/top.v').write_text(s,encoding='utf-8')
    edit('src/top_unified.v', [('top #(.ENABLE_FLASH_AUDIO(0)', 'top #(.CONTROL_KEYS(12),.ENABLE_FLASH_AUDIO(0)')])
    for script in ['generate_hc05_decoder.py','generate_hc05_replies.py']:
        subprocess.run(['python',str(P/'tools'/script)],check=True)
    # Dynamic init constants for all twelve slots, rather than zero-extended
    # seven-note defaults during the first audio frame.
    steps=[23012828,24381242,25831026,27367019,28994347,30718440,32545054,34480283,36530588,38702809,41004198,43442435]
    twelve="{"+','.join(f"32'd{x}" for x in reversed(steps))+"}"
    edit('src/fsr_pitch_scaler.v', [('parameter [CONTROL_KEYS*32-1:0] NOTE_INCREMENTS', 'parameter [CONTROL_KEYS*32-1:0] NOTE_INCREMENTS')])
    # Override the reset vectors at the top instances; normal operation is
    # sourced from the actual map ROM, independently of these initial values.
    edit('src/top.v', [('fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),', f'fsr_pitch_scaler #(.CONTROL_KEYS(CONTROL_KEYS),.NOTE_INCREMENTS(CONTROL_KEYS==12 ? {twelve} : {{32\'d32545054,32\'d30718440,32\'d28994347,32\'d27367019,32\'d25831026,32\'d24381242,32\'d23012828}}),')])
    print(P)

if __name__=='__main__':
    prepare()
