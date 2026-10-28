"""Reject a routed image whose score font was dropped or misinitialized."""
from pathlib import Path
import argparse
import re


def check(netlist, font):
    words = font.read_text(encoding='ascii').split()
    assert len(words) == 512 and set(words) == {'0', '1'}, 'Expected 512 binary font bits'
    source = netlist.read_text(encoding='utf-8')
    names = re.findall(r'^pROM\s+(\S+)', source, re.M)
    names = [name for name in names if 'hud_font' in name]
    assert len(names) == 1, f'Expected one retained HUD font ROM, found {len(names)}: score digits may be blank'
    name = re.escape(names[0])
    match = re.search(r'defparam\s+'+name+r'\s*\.BIT_WIDTH\s*=\s*(\d+);', source)
    assert match, 'HUD font port width missing'
    width = int(match.group(1))
    assert width in (1, 4), f'Unexpected font port width {width}'
    init = dict(re.findall(r'defparam\s+'+name+r"\s*\.INIT_RAM_([0-9A-F]{2})\s*=\s*256'h([0-9A-Fa-f]+);", source))
    chunks = 512*width//256
    assert all(f'{i:02X}' in init for i in range(chunks)), 'HUD font initialization missing'
    value = sum(int(init[f'{i:02X}'], 16) << (i*256) for i in range(chunks))
    errors = [i for i, bit in enumerate(words) if (value >> (i*width) & ((1 << width)-1)) != int(bit)]
    assert not errors, f'HUD font has {len(errors)} wrong addresses; first={errors[:8]}'
    print(f'PASS routed HUD font: all512 addresses, {sum(map(int, words))} lit pixels, retained BIT_WIDTH={width} ROM')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--netlist', type=Path, required=True)
    parser.add_argument('--font', type=Path, required=True)
    args = parser.parse_args()
    check(args.netlist, args.font)
