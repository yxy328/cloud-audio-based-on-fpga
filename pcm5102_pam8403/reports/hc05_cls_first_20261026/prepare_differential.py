"""Compare every HC-05 output each cycle against the exact frozen RTL."""
from work import *

label = sys.argv[1]
root = HERE / label / PROJECT.name
reference = (HERE / 'baseline' / PROJECT.name / 'src/hc05_keymap.v').read_text(encoding='utf-8')
reference = reference.replace('module hc05_keymap #(', 'module hc05_keymap_first_reference #(', 1)
header = reference[:reference.index('\n);')]
outputs = []
for match in re.finditer(r'\boutput\s+(?:wire|reg)\s*(?:\[[^\]]+\])?\s*([\s\S]*?)(?=\binput\b|\boutput\b|\Z)', header):
    outputs.extend(re.findall(r'\b[A-Za-z_]\w*\b', match.group(1)))
assert len(outputs) == len(set(outputs)), outputs

tests = sys.argv[2:] or [
    'tb_command_protocol', 'tb_hc05_extensions', 'tb_hc05_control_races',
    'tb_fx_protocol', 'tb_hc05_keymap', 'tb_hc05_download', 'tb_hc05_take',
    'tb_hc05_adsr', 'tb_hc05_bend', 'tb_hc05_visual', 'tb_hc05_xy',
    'tb_performance_params', 'tb_hc05_audio_record']
generated = []
skipped = []
for test in tests:
    fixture = HERE / 'fixtures' / (test + '.v')
    if not fixture.exists():
        fixture = HERE / 'baseline' / PROJECT.name / 'sim' / (test + '.v')
    source = fixture.read_text(encoding='utf-8')
    tokens = tokenize(source)
    at = next((i for i, t in enumerate(tokens) if t[0] == 'hc05_keymap'), None)
    if at is None:
        skipped.append(test)
        continue
    start = tokens[at][1]
    at += 1
    if tokens[at][0] == '#':
        at = paren(tokens, at + 1)
    instance = tokens[at][0]
    params = source[start + len('hc05_keymap'):tokens[at][1]]
    open_port = at + 1
    after_ports = paren(tokens, open_port)
    assert tokens[after_ports][0] == ';'
    port_text = source[tokens[open_port][2]:tokens[after_ports - 1][1]]
    port_tokens = tokenize(port_text)
    replacements = []
    i = 0
    while i < len(port_tokens):
        if port_tokens[i][0] == '.' and i + 2 < len(port_tokens):
            name = port_tokens[i + 1][0]
            last = paren(port_tokens, i + 2)
            if name in outputs:
                replacements.append((port_tokens[i + 2][2], port_tokens[last - 1][1], ''))
            i = last
        else:
            i += 1
    for first, last, value in reversed(replacements):
        port_text = port_text[:first] + value + port_text[last:]
    instantiation = '\n    hc05_keymap_first_reference' + params + ' first_reference(' + port_text + ');\n'
    comparisons = '\n    // No scheduling change is allowed: compare all outputs on every cycle.\n'
    comparisons += f"    always @(negedge {instance}.clk) if({instance}.resetn === 1'b1) begin\n"
    comparisons += '        if({' + ','.join(instance + '.' + p for p in outputs) + '} !==\n'
    comparisons += '           {' + ','.join('first_reference.' + p for p in outputs) + '}) begin\n'
    for output in outputs:
        comparisons += (f'        if({instance}.{output} !== first_reference.{output})\n'
                        f'            $fatal(1,"First-pass equivalence: {test} output {output}");\n')
    comparisons += '        end\n    end\n'
    insert = tokens[after_ports][2]
    source = source[:insert] + instantiation + comparisons + source[insert:]
    # Mirror deliberate internal fault injections in the reference.
    pattern = rf'\b(?:force|release)\s+{instance}\.[^;]+;'
    source = re.sub(pattern, lambda m: m.group() + '\n            ' +
                    m.group().replace(instance + '.', 'first_reference.'), source)
    name = test + '_first_equiv'
    source = source.replace('module ' + test + ';', 'module ' + name + ';', 1)
    (root / 'sim' / (name + '.v')).write_text(source + '\n' + reference, encoding='utf-8', newline='\n')
    generated.append(name)
save(HERE / label / 'differential_tests.json', {'outputs_compared_each_cycle': outputs,
                                              'tests': generated,
                                              'top_level_fixtures_run_separately': skipped,
                                              'reference_sha256': sha(HERE / 'baseline' / PROJECT.name / 'src/hc05_keymap.v')})
print('Generated', len(generated), 'differential fixtures comparing', len(outputs), 'outputs per cycle')
