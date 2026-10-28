"""Generate the synchronous rhythm judgement, score, statistics and font ROMs."""
from pathlib import Path
import argparse
ROOT=Path(__file__).resolve().parents[1]/'src'
DIGITS=['111101101101111','010110010010111','111001111100111','111001111001111',
        '101101111001001','111100111001111','111100111101111','111001001001001',
        '111101111101111','111101111001111']
def tables():
    font=[]
    for digit in range(16):
        for y in range(8):
            for x in range(4):font.append(DIGITS[digit][(y-1)*3+x] if digit<10 and 1<=y<=5 and x<3 else '0')
    judge=[]
    for window in (80,120,160,200):
        for offset in range(512):
            signed=offset if offset<256 else offset-512
            judge.append((1 if abs(signed)<=window else 0)|(2 if abs(signed)<=window//2 else 0))
    return {'rhythm_font.hex':'\n'.join(font)+'\n',
        'rhythm_judge.hex':''.join(f'{value:x}\n' for value in judge),
        'rhythm_points.hex':''.join(f'{thousands:03d}\n' for thousands in range(512)),
        'rhythm_stats.hex':''.join(f'{count:03d}\n' for count in range(512))}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    for name,content in tables().items():
        path=ROOT/name
        if args.check:assert path.read_text(encoding='ascii')==content,f'Stale rhythm ROM: {name}'
        else:path.write_text(content,encoding='ascii')
    print('PASS rhythm ROMs: signed windows, BCD score/statistics, 3x5 digit font')
