"""Regenerate the original 3x5 status-panel glyphs embedded in Verilog."""
from pathlib import Path

PATTERNS = {
    '0': ('111', '101', '101', '101', '111'),
    '1': ('010', '110', '010', '010', '111'),
    '2': ('111', '001', '111', '100', '111'),
    '3': ('111', '001', '111', '001', '111'),
    '4': ('101', '101', '111', '001', '001'),
    '5': ('111', '100', '111', '001', '111'),
    '6': ('111', '100', '111', '101', '111'),
    '7': ('111', '001', '010', '010', '010'),
    '8': ('111', '101', '111', '101', '111'),
    '9': ('111', '101', '111', '001', '111'),
    'A': ('010', '101', '111', '101', '101'),
    'B': ('110', '101', '110', '101', '110'),
    'C': ('111', '100', '100', '100', '111'),
    'D': ('110', '101', '101', '101', '110'),
    'E': ('111', '100', '110', '100', '111'),
    'F': ('111', '100', '110', '100', '100'),
    'K': ('101', '101', '110', '101', '101'),
    'H': ('101', '101', '111', '101', '101'),
    'T': ('111', '010', '010', '010', '010'),
    'R': ('110', '101', '110', '101', '101'),
    'V': ('101', '101', '101', '101', '010'),
    'P': ('110', '101', '110', '100', '100'),
    'W': ('101', '101', '111', '111', '101'),
    '!': ('010', '010', '010', '000', '010'),
    ' ': ('000',) * 5,
    'I': ('111', '010', '010', '010', '111'),
    'S': ('111', '100', '111', '001', '111'),
    '.': ('000', '000', '000', '000', '010'),
}
GLYPHS = [str(n) for n in range(17)] + list('ABCDEFKHTRVPW! IS.')
assert len(GLYPHS) == 35


def main():
    target = Path(__file__).resolve().parents[1] / 'src/hub75e_status.v'
    lines = ['    // FONT_INITIALIZATION_BEGIN', '    initial begin']
    for index in range(64):
        label = GLYPHS[index] if index < len(GLYPHS) else ' '
        rows = [0] * 8
        for column, char in enumerate(label):
            offset = 2 if len(label) == 1 else column * 4
            for y, bits in enumerate(PATTERNS[char], 1):
                rows[y] |= int(bits, 2) << (5 - offset)
        assignments = ' '.join(f"font[{index*8+y}]=8'h{value:02x};" for y, value in enumerate(rows))
        lines.append(f'        {assignments} // {index}: {label}')
    lines.extend(['    end', '    // FONT_INITIALIZATION_END'])
    source = target.read_text(encoding='utf-8')
    if '    // FONT_INITIALIZATION_BEGIN' in source:
        start = source.index('    // FONT_INITIALIZATION_BEGIN')
        end = source.index('    // FONT_INITIALIZATION_END') + len('    // FONT_INITIALIZATION_END')
    else:
        start = source.index('    // FONT_INITIALIZATION')
        end = start + len('    // FONT_INITIALIZATION')
    target.write_text(source[:start] + '\n'.join(lines) + source[end:], encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
