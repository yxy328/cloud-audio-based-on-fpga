"""Keep the old fixture intact; test the already-existing chromatic/fixed16 contract."""
from work import *

original = (HERE / 'baseline' / PROJECT.name / 'sim/tb_hc05_download.v').read_text(encoding='utf-8')
source = original.replace('module tb_hc05_download;', 'module tb_hc05_download_current;')
# The original fixture explicitly installs its natural_mapping before the
# chord test. Decimal 145 is 0x91: notes60/64/67, lanes0/2/4 => 0x15.
# Preserve that independent chord assertion. Reset below checks the current
# chromatic power-on default separately.
# Two milliseconds is a legal duration; retain the explicit rest and all
# UART validation/atomicity tests without spending 50ms on an idle hold.
source = source.replace('SONG_CHORD,0,145,50\\n",20', 'SONG_CHORD,0,145,2\\n",19')
source = source.replace('SONG_CHORD,1,0,50\\n",18', 'SONG_CHORD,1,0,2\\n",17')
first = source.index('        transact("REC_START\\n",10,{"OK"')
last = source.index('        $finish;', first)
source = source[:first] + '''        // Fixed16 already rejects this legacy seven-key event logger.
        transact("REC_START\\n",10,{"ERR,BUSY",8'd13,8'd10});
        if(rec_busy)$fatal(1,"Fixed16 unexpectedly enabled legacy logger");
        transact("MAP_RESET\\n",10,{"OK,MAP_RESET",8'd13,8'd10});
        transact("MAP?\\n",5,{"MAP,60,61,62,63,64,65,66",8'd13,8'd10});
        if(map!=={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60})
            $fatal(1,"Current chromatic reset map changed");
        $display("PASS current downloads: original score atomicity/retry/bounds, chromatic chord/rest, fixed16 legacy guard and MAP reset");
''' + source[last:]
(HERE / 'fixtures').mkdir(exist_ok=True)
fixture = HERE / 'fixtures/tb_hc05_download_current.v'
fixture.write_text(source, encoding='utf-8', newline='\n')
save(HERE / 'current_download_fixture.json', {
    'original_fixture_unchanged_sha256': sha(HERE / 'baseline' / PROJECT.name / 'sim/tb_hc05_download.v'),
    'reason': 'Historical fixture accepts legacy REC_START; frozen fixed16 production already rejects it',
    'changes': ['Original explicit diatonic mapping and chord0x15 assertion preserved', 'Legal chord/rest duration2ms',
                'Existing fixed16 legacy logger refusal', 'Existing chromatic default MAP'],
    'fixture_sha256': sha(fixture)})
for label in ('map_serial', 'reply_parallel'):
    saved = json.loads((HERE / label / 'differential_tests.json').read_text(encoding='utf-8'))
    subprocess.run([sys.executable, str(HERE / 'prepare_differential.py'), label,
                    'tb_hc05_download_current'], check=True)
    saved['tests'] = [t.replace('tb_hc05_download_first_equiv', 'tb_hc05_download_current_first_equiv')
                      for t in saved['tests']]
    saved['historical_fixture_excluded'] = 'tb_hc05_download: stale expectations predating this optimization'
    save(HERE / label / 'differential_tests.json', saved)
# Run this exact new contract fixture on the unchanged baseline too.
shutil.copy2(fixture, HERE / 'baseline' / PROJECT.name / 'sim' / fixture.name)
print('Prepared current-contract download fixture; original file is unchanged')
