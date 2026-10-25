"""Create an isolated song decoder experiment; never edit production RTL."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
BUILDS = PROJECT / 'sim/build/unified'
BASE = BUILDS / 'engine_share_base_20261024'
CAND = BUILDS / 'engine_merge_candidate_20261024_01'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hierarchy(folder):
    result = {}
    path = folder / 'pcm5102_pam8403/impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml'
    def visit(node, parent=''):
        name = parent + '/' + node.attrib['name']
        result[name] = {k: int(node.get(k, '0')) for k in
                       ('Lut', 'Alu', 'Register', 'Bsram', 'MULT27X36',
                        'MULTALU27X18', 'MULT12X12', 'MULTADDALU12X12')}
        for child in node:
            visit(child, name)
    visit(ET.parse(path).getroot())
    return result

baseline, merged = hierarchy(BASE), hierarchy(CAND)
rows = []
for name in baseline.keys() | merged.keys():
    b, c = baseline.get(name, {}), merged.get(name, {})
    rows.append({'path': name, 'baseline': b, 'merged': c,
                 'self_lut_alu_delta': sum(c.get(k, 0)-b.get(k, 0) for k in ('Lut', 'Alu'))})
rows.sort(key=lambda r: r['self_lut_alu_delta'], reverse=True)
checks = []
for file in ('take_nor_store.v', 'apds9960_ctrl.v', 'downloadable_song.v'):
    a = BASE / 'pcm5102_pam8403/src' / file
    b = CAND / 'pcm5102_pam8403/src' / file
    checks.append({'file': file, 'baseline_sha256': digest(a), 'merged_sha256': digest(b),
                   'same': digest(a) == digest(b)})
(HERE / 'hierarchy_audit.json').write_text(json.dumps({'rows': rows, 'unchanged_sources': checks}, indent=2), encoding='utf-8')

original = (PROJECT / 'src/downloadable_song.v').read_text(encoding='utf-8-sig')
start = original.index('    always @* begin\n        covered_mask=0;')
end = original.index('    wire [7:0] fetched_pitch=', start)
replacement = '''    // One fixed pitch equality matrix feeds both coverage and key selection.
    // No extra state, cycle, RAM or arithmetic unit is introduced.
    wire [12:0] map_match [0:6];
    wire [6:0] fetched_keys;
    genvar key_index, pitch_index;
    generate
        for(key_index=0; key_index<7; key_index=key_index+1) begin: key_decode
            for(pitch_index=0; pitch_index<13; pitch_index=pitch_index+1) begin: pitch_decode
                assign map_match[key_index][pitch_index] =
                    checked_map[key_index*8 +: 8] == (8'd60 + pitch_index);
            end
            assign fetched_keys[key_index] = |(fetched[28:16] & map_match[key_index]);
        end
    endgenerate
    always @* covered_mask = map_match[0] | map_match[1] | map_match[2] |
                            map_match[3] | map_match[4] | map_match[5] | map_match[6];
'''
candidate = original[:start] + replacement + original[end:]
# Remove the now-unused function; all behavior changes are in the decoder above.
a = candidate.index('    function [6:0] keys_for_mask;')
b = candidate.index('    function [7:0] first_pitch;', a)
candidate = candidate[:a] + candidate[b:]

for name, content in [('baseline', original), ('candidate', candidate)]:
    dest = HERE / name
    dest.mkdir(exist_ok=False)
    (dest / 'downloadable_song.v').write_text(content, encoding='utf-8')
    # The production top enables lookahead. Expose all other ports identically.
    synth = content.replace('parameter integer ENABLE_LOOKAHEAD=0,', 'parameter integer ENABLE_LOOKAHEAD=1,')
    (dest / 'synthesis.v').write_text(synth, encoding='utf-8')
    (dest / 'probe.gprj').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gowin-fpga-project>
<Project><Template>FPGA</Template><Version>5</Version>
<Device name="GW5A-25A" pn="GW5A-LV25MG121NC1/I0">gw5a25a-002</Device>
<FileList><File path="synthesis.v" type="file.verilog" enable="1"/></FileList></Project>
''', encoding='utf-8')
    (dest / 'build.tcl').write_text('''set here [file dirname [file normalize [info script]]]
cd $here
open_project [file join $here probe.gprj]
set_option -top_module downloadable_song -output_base_name score_probe
set_option -resource_sharing 1 -retiming 1 -global_freq 50 -enable_dsrm 1
run syn
''', encoding='utf-8')

(HERE / 'downloadable_song_reference.v').write_text(original.replace('module downloadable_song #(', 'module downloadable_song_reference #(', 1), encoding='utf-8')
tb = (PROJECT / 'sim/tb_downloadable_song.v').read_text(encoding='utf-8-sig')
marker = '    integer timeout, i, epoch=0'
ports = ['done', 'error', 'valid', 'playing', 'gate', 'current_note', 'guide_keys',
         'ms_tick', 'guide_reset', 'note_spawn', 'spawn_keys', 'spawn_delay_ms', 'current_mask', 'busy']
compare = '    downloadable_song_reference #(.CLK_HZ(20000),.ENABLE_LOOKAHEAD(1)) ref_dut(\n'
inputs = ['clk', 'resetn', 'request', 'operation', 'arg0', 'arg1', 'arg2', 'edit_allowed', 'note_map', 'toggle_play', 'restart', 'note_ready']
compare += '        ' + ','.join('.'+p+'('+p+')' for p in inputs) + ');\n'
compare += '    always @(negedge clk) if(resetn) begin\n'
compare += '        if({' + ','.join('dut.'+p for p in ports) + '} !==\n'
compare += '           {' + ','.join('ref_dut.'+p for p in ports) + '})\n'
compare += '            $fatal(1,"cycle-exact original/candidate mismatch");\n    end\n\n'
tb = tb.replace(marker, compare + marker, 1)
(HERE / 'tb_song_equivalence.v').write_text(tb, encoding='utf-8')
(HERE / 'input_hashes.json').write_text(json.dumps({
    'production_source': digest(PROJECT / 'src/downloadable_song.v'),
    'frozen_baseline_source': digest(BASE / 'pcm5102_pam8403/src/downloadable_song.v'),
    'candidate_source': digest(HERE / 'candidate/downloadable_song.v'),
    'test_source': digest(PROJECT / 'sim/tb_downloadable_song.v')}, indent=2), encoding='utf-8')
print(json.dumps({'unchanged_sources': checks, 'largest_deltas': rows[:7]}, indent=2))
