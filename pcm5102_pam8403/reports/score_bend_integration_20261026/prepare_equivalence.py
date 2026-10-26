"""Reuse the lexer-based wrapper to compare legacy UART outputs per cycle."""
from work import *

spec=importlib.util.spec_from_file_location('cls_work',CLS/'work.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
tokenize=helper.tokenize
paren=helper.paren
source=(CLS/'prepare_differential.py').read_text(encoding='utf-8')
source=source.replace('from work import *','')
source=source.replace("reference = reference.replace('module hc05_keymap #(',", "reference = reference.replace('.arg0(song_arg0),', \".arg3(16'd0),.score_min(16'd8192),.score_max(16'd32768),.arg0(song_arg0),\")\nreference = reference.replace('module hc05_keymap #(',")
source=source.replace("fixture = HERE / 'baseline' / PROJECT.name / 'sim' / (test + '.v')",
                      "fixture = root / 'sim' / (test + '.v')")
source=source.replace("name = test + '_first_equiv'", "name = test + '_score_equiv'")
source=source.replace('First-pass equivalence:', 'Score legacy equivalence:')
exec(compile(source,str(CLS/'prepare_differential.py'),'exec'))
