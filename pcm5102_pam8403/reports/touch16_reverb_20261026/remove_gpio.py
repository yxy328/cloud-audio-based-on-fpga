"""Remove explicitly preserved unused GPIO synchronizers in new candidates."""
from pathlib import Path
import importlib.util,shutil,json
here=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('experiment',here/'experiment.py')
exp=importlib.util.module_from_spec(spec);spec.loader.exec_module(exp)
clean=here/'fixed16_clean'
assert not clean.exists()
shutil.copytree(here/'fixed16',clean,ignore=shutil.ignore_patterns('impl','build','build.log','exit.json','sources.json'))
(clean/'pcm5102_pam8403/impl').mkdir()
for root in (clean,here/'fx_fixed16'):
    assert not (root/'build.log').exists()
    path=root/'pcm5102_pam8403/src/top.v'
    s=path.read_text(encoding='utf-8-sig')
    start=s.index('    // Reuse the shared reader with separate confirmation times for notes/mode.')
    end=s.index('    fsr_mode_select u_fsr_mode (',start)
    old=s[start:end]
    assert old.count('ttp229_gpio_input #(')==2
    new='''    // Fixed16 assessment: legacy parallel readers are absent, including
    // their syn_preserve synchronizers. Serial input remains unchanged.
    assign note_keys_raw=8'd0;
    assign note_keys=8'd0;
    assign mode_keys_raw=8'd0;
    assign mode_keys=8'd0;
    assign note_ready=1'b0;
    assign mode_ready=1'b0;
'''
    path.write_text(s[:start]+new+s[end:],encoding='utf-8')
    exp.write_json(root/'sources.json',exp.manifest(root))
exp.write_json(here/'gpio_removal.json',{
    'constant_mode_diagnostic':'fixed16',
    'complete_removal_candidates':['fixed16_clean','fx_fixed16'],
    'reason':'syn_preserve on two GPIO synchronizers retains 32 unused registers after mode constant propagation',
    'production_modified':False})
print('Created fixed16_clean; removed both preserved GPIO reader instances from clean and FX candidates')
