"""Static reply templates; FF consumes one nibble through the shared hex encoder."""
import argparse
from pathlib import Path

FORMATS = [
    'OK\r\n', 'ERR,BUSY\r\n', 'ERR,RANGE\r\n', 'ERR,STATE\r\n',
    'ERR,MISSING\r\n', 'ERR,MAP\r\n', 'ERR,CMD\r\n', 'ERR,UART\r\n',
    'ERR,LENGTH\r\n', 'PONG\r\n', 'CTRL,#,#,#,#,#,##,#\r\n',
    'SERIAL,#\r\n', 'CAL,###,###\r\n', 'ADC,###,#\r\n',
    'TAKE,##,#,######,###,######\r\n', 'AREC,#,#,#,#,#,#,####,######\r\n',
    'AREC,#,#,#\r\n', 'VIS,#,#,#,#,#,#,#\r\n', 'V,' + '#' * 28 + '\r\n',
    'MAP,' + ','.join(['##'] * 7) + '\r\n', 'OK,MAP_RESET\r\n',
    'ERR,KEY\r\n', 'ERR,NOTE\r\n', 'OK,MAP,#,##\r\n',
    'HOLD,#\r\n', 'POLY,##\r\n', 'CTRL2,#,#,#,#,#,##,#,##,##\r\n',
    'PITCH,####,####,####,####\r\n',
    'VIB,####,####,###,####\r\n',
    'EFFECT2,#\r\n',
    'EFFECT3,#,##,###,#,##,###\r\n',
    'SONGBEND,1\r\n',
]


def generate():
    assert len(FORMATS) <= 32
    rom = [0] * 1024
    for kind, template in enumerate(FORMATS):
        assert len(template) <= 32
        for offset, character in enumerate(template):
            rom[kind * 32 + ((len(template) - offset) & 31)] = 255 if character == '#' else ord(character)
    return ''.join(f'{value:02x}\n' for value in rom)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / 'src/hc05_reply.hex'
    expected = generate()
    if args.check:
        assert path.read_text(encoding='ascii') == expected, 'Stale HC-05 reply ROM'
        print('HC-05 reply templates match generated ROM')
    else:
        path.write_text(expected, encoding='ascii')
