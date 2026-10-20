"""Expand the existing integer quarter-wave lookup without rounding changes."""
import argparse
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
source = (root / 'src/sine_lookup.v').read_text(encoding='utf-8')
quarter = {int(i): int(v) for i, v in re.findall(
    r"7'd(\d+):\s*quarter_sine\s*=\s*16'sd(\d+);", source)}
if set(quarter) != set(range(65)):
    raise SystemExit('Expected exactly 65 quarter-wave entries')
values = []
for address in range(256):
    index = 64 - (address & 63) if address & 64 else address & 63
    value = quarter[index] * (-1 if address & 128 else 1)
    values.append(f'{value & 0xffff:04x}\n')
expected = ''.join(values)
target = root / 'src/tdm_sine256.hex'
if args.check:
    if target.read_text(encoding='ascii').lower() != expected:
        raise SystemExit('TDM sine ROM differs from the integer reference')
    print('PASS TDM sine ROM: all 256 entries match the integer reference')
else:
    target.write_text(expected, encoding='ascii', newline='\n')
