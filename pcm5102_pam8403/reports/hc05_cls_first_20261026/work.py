"""Isolated HC-05 optimization builds; never changes production RTL or outputs."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
REPO = PROJECT.parent
PRIOR = PROJECT / 'reports/performance_experience_20261026'
GOWIN = Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def manifest(root):
    entries = []
    for folder in ('pcm5102_pam8403/src', 'pmod_hub75e/src', 'build_inputs'):
        entries.extend({'Path': p.relative_to(root).as_posix(), 'SHA256': sha(p)}
                       for p in sorted((root / folder).rglob('*')) if p.is_file())
    for name in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj',
                 'pcm5102_pam8403/tools/build_unified.tcl'):
        entries.append({'Path': name, 'SHA256': sha(root / name)})
    return entries

def prepare():
    baseline = HERE / 'baseline'
    assert not baseline.exists(), 'Do not overwrite frozen inputs'
    expected = json.loads((PRIOR / 'base/sources.json').read_text(encoding='utf-8-sig'))
    production = [r for r in expected if not r['Path'].startswith('build_inputs/')]
    changes = [r['Path'] for r in production if sha(REPO / r['Path']) != r['SHA256']]
    assert not changes, changes
    for folder in ('src', 'tools', 'sim'):
        shutil.copytree(PROJECT / folder, baseline / PROJECT.name / folder,
                        ignore=shutil.ignore_patterns('build', '__pycache__'))
    shutil.copy2(PROJECT / 'PCM5102_UNIFIED.gprj', baseline / PROJECT.name / 'PCM5102_UNIFIED.gprj')
    shutil.copytree(REPO / 'pmod_hub75e/src', baseline / 'pmod_hub75e/src')
    shutil.copytree(PRIOR / 'base/build_inputs', baseline / 'build_inputs')
    save(baseline / 'sources.json', manifest(baseline))
    (HERE / 'baseline_reports').mkdir()
    for name in ('impl/pnr/PCM5102_UNIFIED.rpt.txt', 'impl/pnr/PCM5102_UNIFIED.timing_paths',
                 'impl/pnr/cmd.do', 'impl/pnr/device.cfg',
                 'impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml',
                 'impl/gwsynthesis/PCM5102_UNIFIED.prj'):
        shutil.copy2(PROJECT / name, HERE / 'baseline_reports' / Path(name).name)
    audit = json.loads((PRIOR / 'build_audit.json').read_text(encoding='utf-8-sig'))['base']
    save(HERE / 'freeze.json', {'production_inputs': production, 'production_drift': changes,
                              'gowin_sha256': sha(GOWIN), 'baseline_audit': audit,
                              'baseline_fs_sha256': sha(PROJECT / 'impl/pnr/PCM5102_UNIFIED.fs'),
                              'production_gprj_sha256': sha(PROJECT / 'PCM5102_UNIFIED.gprj')})
    print('Frozen', len(production), 'unchanged production files', flush=True)

def candidate(label):
    target = HERE / label
    assert not target.exists(), target
    shutil.copytree(HERE / 'baseline', target,
                    ignore=shutil.ignore_patterns('sources.json', '__pycache__', 'build'))
    return target

# A small statement parser preserves all existing branch bodies and guards.
# It only changes the mutually exclusive decoded-command dispatch to a case.
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_$][\w$]*|\S', re.S)

def tokenize(source):
    return [(m.group(), m.start(), m.end()) for m in TOKEN.finditer(source)
            if not m.group().startswith(('//', '/*'))]

def paren(tokens, at):
    assert tokens[at][0] == '('
    depth = 1
    at += 1
    while depth:
        depth += (tokens[at][0] == '(') - (tokens[at][0] == ')')
        at += 1
    return at

def statement(tokens, at):
    word = tokens[at][0]
    if word == 'if':
        end = statement(tokens, paren(tokens, at + 1))
        if tokens[end][0] == 'else':
            end = statement(tokens, end + 1)
        return end
    if word == 'begin':
        depth = 1
        at += 1
        while depth:
            depth += (tokens[at][0] == 'begin') - (tokens[at][0] == 'end')
            at += 1
        return at
    if word in ('case', 'casex', 'casez'):
        depth = 1
        at += 1
        while depth:
            depth += (tokens[at][0] in ('case', 'casex', 'casez')) - (tokens[at][0] == 'endcase')
            at += 1
        return at
    while tokens[at][0] != ';':
        at += 1
    return at + 1

def parallel_dispatch():
    target = candidate('parallel_dispatch')
    path = target / PROJECT.name / 'src/hc05_keymap.v'
    source = path.read_text(encoding='utf-8')
    start = source.index('if(decoded_command==CMD_PING)')
    tokens = tokenize(source)
    at = next(i for i, t in enumerate(tokens) if t[1] == start)
    branches = []
    command_ids = set()
    while tokens[at][0] == 'if':
        after_condition = paren(tokens, at + 1)
        condition = source[tokens[at + 1][2]:tokens[after_condition - 1][1]].strip()
        body_end = statement(tokens, after_condition)
        body = source[tokens[after_condition][1]:tokens[body_end - 1][2]]
        keys = list(dict.fromkeys(re.findall(r'decoded_command\s*==\s*(CMD_\w+)', condition)))
        assert keys, condition
        assert not command_ids.intersection(keys), keys
        command_ids.update(keys)
        simple = re.fullmatch(r'decoded_command\s*==\s*CMD_\w+', condition) is not None
        # Multi-command conditions and extra line-length/feature guards retain
        # the original expression, including the original error fallback.
        if simple:
            content = body
        else:
            content = 'begin\n                            if(' + condition + ') ' + body + '\n                            else result(7);\n                        end'
        branches.append('                        ' + ', '.join(keys) + ': ' + content)
        assert tokens[body_end][0] == 'else'
        at = body_end + 1
    fallback_end = statement(tokens, at)
    fallback = source[tokens[at][1]:tokens[fallback_end - 1][2]]
    assert fallback == 'result(7);', fallback
    replacement = ('begin\n                        // The dictionary emits one command ID. Distinct commands\n'
                   '                        // share a parallel dispatch rather than a priority chain.\n'
                   '                        case(decoded_command)\n' + '\n'.join(branches) +
                   '\n                        default: result(7);\n                        endcase\n                    end')
    source = source[:start] + replacement + source[tokens[fallback_end - 1][2]:]
    path.write_text(source, encoding='utf-8', newline='\n')
    save(target / 'change.json', {'changed_file': 'src/hc05_keymap.v',
                                'dispatch_branches': len(branches), 'command_ids': sorted(command_ids),
                                'source_sha256': sha(path)})
    print('Prepared parallel_dispatch:', len(branches), 'branches,', len(command_ids), 'command IDs')

def build(label):
    root = HERE / label
    assert not (root / 'build.log').exists(), 'Never overwrite build evidence'
    before = manifest(root)
    save(root / 'sources.json', before)
    with (root / 'build.log').open('w', encoding='utf-8') as log:
        result = subprocess.run([str(GOWIN), str(root / PROJECT.name / 'tools/build_unified.tcl')],
                                cwd=root / PROJECT.name, stdout=log, stderr=log)
    save(root / 'exit.json', {'returncode': result.returncode, 'inputs_unchanged': manifest(root) == before})
    print(label, 'finished, return code', result.returncode, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)

def map_serial():
    target = candidate('map_serial')
    path = target / PROJECT.name / 'src/hc05_keymap.v'
    source = path.read_text(encoding='utf-8')
    source = source.replace('    reg [111:0] reply;', '''    reg [111:0] reply;
    // Keep a binary MAP snapshot and reuse one decimal digit formatter.
    // The existing nibble shifter still consumes exactly one UART digit.
    reg map_reply_digit,map_reply_seventy;
    integer map_key;''')
    old = "    assign reply_byte=reply_template==8'hff ? hex_char(reply[111:108]) : reply_template;"
    new = '''    wire [3:0] map_reply_nibble=map_reply_digit ?
        reply[111:108]-(map_reply_seventy ? 4'd6 : 4'd12) :
        (reply[111:104]<8'd70 ? 4'd6 : 4'd7);
    assign reply_byte=reply_template==8'hff ?
        hex_char(reply_format==5'd19 ? map_reply_nibble : reply[111:108]) : reply_template;'''
    assert old in source
    source = source.replace(old, new)
    old = 'begin reply_format<=format;reply_remaining<=length;reply_char_ready<=0;state<=RESPOND;end'
    assert old in source
    source = source.replace(old, 'begin reply_format<=format;reply_remaining<=length;reply_char_ready<=0;\n            map_reply_digit<=0;map_reply_seventy<=0;state<=RESPOND;end')
    old = '            line<=0; line_length<=0; reply<=0;'
    assert old in source
    source = source.replace(old, '            map_reply_digit<=0;map_reply_seventy<=0;\n' + old)
    old = "                    if(reply_template==8'hff)reply<={reply[107:0],4'd0};"
    assert old in source
    source = source.replace(old, '''                    if(reply_template==8'hff)begin
                        reply<={reply[107:0],4'd0};
                        if(reply_format==5'd19)begin
                            map_reply_digit<=!map_reply_digit;
                            if(!map_reply_digit)map_reply_seventy<=reply[111:104]>=8'd70;
                        end
                    end''')
    lines = source.splitlines()
    old = next(line for line in lines if 'reply<={(note_map[7:0]<70' in line)
    new = '                            reply<={note_map[7:0],note_map[15:8],note_map[23:16],note_map[31:24],note_map[39:32],note_map[47:40],note_map[55:48],56\'d0};respond(5\'d19,6\'d26);'
    source = source.replace(old, new)
    old = "                                note_map[(line[26:24]-3'd1)*8 +: 8]<=requested_note;"
    assert old in source
    source = source.replace(old, '''                                // Fixed lanes avoid a variable-width write selector.
                                for(map_key=0;map_key<7;map_key=map_key+1)
                                    if(line[26:24]==map_key+1)
                                        note_map[map_key*8 +: 8]<=requested_note;''')
    path.write_text(source, encoding='utf-8', newline='\n')
    save(target / 'change.json', {'changed_file': 'src/hc05_keymap.v',
                                'changes': ['Shared MAP decimal formatter', 'Fixed-lane MAP write enables'],
                                'added_protocol_cycles': 0, 'source_sha256': sha(path)})
    print('Prepared map_serial: same binary MAP output and byte/cycle protocol')

def reply_parallel():
    target = candidate('reply_parallel')
    path = target / PROJECT.name / 'src/hc05_keymap.v'
    source = path.read_text(encoding='utf-8')
    first = source.index('                    EXECUTE: begin')
    last = source.index('                    DECIMAL_READ:state<=DECIMAL;', first)
    block = source[first:last]
    loads = list(re.finditer(r'\breply\s*<=([^;]+);', block))
    keys = ['CMD_EFFECT2_SET', 'CMD_VIB_SET', 'CMD_PITCH_SET',
            'CMD_CTRL_QUERY, CMD_CTRL2_QUERY', 'CMD_SERIAL_QUERY', 'CMD_CAL_QUERY',
            'CMD_ADC_QUERY', 'CMD_EFFECT_SET', 'CMD_HOLD_SET', 'CMD_POLY_SET',
            'CMD_TAKE_QUERY', 'CMD_AREC_QUERY_FLASH', 'CMD_AREC_QUERY_SHORT',
            'CMD_VIS_QUERY', 'CMD_VIZ_QUERY', 'CMD_MAP_QUERY', 'CMD_MAP_SET']
    assert len(loads) == len(keys), (len(loads), len(keys))
    expressions = dict(zip(keys, [m[1] for m in loads]))
    cases = []
    for key in keys:
        if key == 'CMD_AREC_QUERY_SHORT':
            continue
        if key == 'CMD_AREC_QUERY_FLASH':
            cases.append('                CMD_AREC_QUERY: if(ENABLE_FLASH_AUDIO) reply<=' +
                         expressions[key] + ';\n                    else reply<=' +
                         expressions['CMD_AREC_QUERY_SHORT'] + ';')
        else:
            cases.append('                ' + key + ': reply<=' + expressions[key] + ';')
    block = re.sub(r'\breply\s*<=[^;]+;', '', block)
    source = source[:first] + block + source[last:]
    source = source.replace(' reply<=0;', '', 1)
    old = "                    if(reply_template==8'hff)reply<={reply[107:0],4'd0};"
    assert old in source
    source = source.replace(old, '', 1)
    updater = '''    // Reply data has one writer and a small parallel source mux. The
    // command FSM still owns validation, commits, reply format and timing.
    // Speculative data captured for rejected/set commands is never consumed:
    // every dynamic reply snapshots its complete payload on its EXECUTE edge.
    always @(posedge clk)begin
        if(!resetn)reply<=0;
        else if(state==RESPOND)begin
            if(reply_char_ready && !select_log && !select_stream && !select_live &&
               tx_ready && reply_template==8'hff)reply<={reply[107:0],4'd0};
        end else if(state==EXECUTE)begin
            case(decoded_command)
''' + '\n'.join(cases) + '''
                default: begin end
            endcase
        end
    end
'''
    marker = '    always @(posedge clk) begin\n        if(!resetn) begin\n            note_map'
    assert marker in source
    source = source.replace(marker, updater + marker, 1)
    path.write_text(source, encoding='utf-8', newline='\n')
    save(target / 'change.json', {'changed_file': 'src/hc05_keymap.v',
                                'changes': ['Isolate complete reply snapshot mux from command validation'],
                                'payload_sources': len(keys), 'added_protocol_cycles': 0,
                                'source_sha256': sha(path)})
    print('Prepared reply_parallel:', len(keys), 'payload sources, unchanged command FSM')

def physical(label, place, route, fan):
    target = candidate(label)
    shutil.copy2(HERE / 'reply_parallel' / PROJECT.name / 'src/hc05_keymap.v',
                 target / PROJECT.name / 'src/hc05_keymap.v')
    path = target / PROJECT.name / 'tools/build_unified.tcl'
    source = path.read_text(encoding='utf-8')
    source = re.sub(r'(-place_option )\d+', lambda m: m[1]+str(place), source)
    source = re.sub(r'(-route_option )\d+', lambda m: m[1]+str(route), source)
    source = re.sub(r'(-route_maxfan )\d+', lambda m: m[1]+str(fan), source)
    path.write_text(source, encoding='utf-8', newline='\n')
    save(target / 'functional_reference.json', {
        'parent': 'reply_parallel', 'hc05_sha256': sha(target / PROJECT.name / 'src/hc05_keymap.v'),
        'reason': 'Identical RTL/ROM/constraints and synthesis settings; only physical options differ',
        'place_option': place, 'route_option': route, 'route_maxfan': fan})
    print('Prepared', label, place, route, fan, flush=True)

def audit(label):
    spec = importlib.util.spec_from_file_location('audit_fx_builds', PROJECT / 'tools/audit_fx_builds.py')
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    baseline = tool.sources(HERE / 'baseline')
    metrics = json.loads((HERE / 'freeze.json').read_text(encoding='utf-8'))['baseline_audit']['metrics']
    result = tool.audit(HERE / label, baseline, metrics)
    log = (HERE / label / 'build.log').read_text(encoding='utf-8', errors='replace')
    unplaced = re.search(r'(\d+) LUT\(s\).*?unPlaced', log)
    result['unplaced_LUT_equivalents'] = int(unplaced[1]) if unplaced else 0
    if unplaced:
        result['status'] = 'placement_failed'
        result['resource_numbers_are_partial'] = True
    result['gowin_sha256'] = sha(GOWIN)
    result['actual_build_file_hashes'] = {
        name: sha(HERE / label / PROJECT.name / name) for name in (
            'impl/gwsynthesis/PCM5102_UNIFIED.prj', 'impl/pnr/cmd.do', 'impl/pnr/device.cfg',
            'impl/pnr/PCM5102_UNIFIED.rpt.txt', 'impl/pnr/PCM5102_UNIFIED_tr_content.html',
            'impl/pnr/PCM5102_UNIFIED.timing_paths') if (HERE / label / PROJECT.name / name).exists()}
    save(HERE / label / 'audit.json', result)
    print(json.dumps({k: result[k] for k in ('status', 'metrics', 'delta_vs_baseline', 'unrouted_nets', 'timing')}, indent=2))

if __name__ == '__main__':
    if sys.argv[1] == 'prepare': prepare()
    elif sys.argv[1] == 'parallel': parallel_dispatch()
    elif sys.argv[1] == 'map': map_serial()
    elif sys.argv[1] == 'reply': reply_parallel()
    elif sys.argv[1] == 'physical': physical(sys.argv[2], *map(int, sys.argv[3:6]))
    elif sys.argv[1] == 'build': build(sys.argv[2])
    elif sys.argv[1] == 'audit': audit(sys.argv[2])
