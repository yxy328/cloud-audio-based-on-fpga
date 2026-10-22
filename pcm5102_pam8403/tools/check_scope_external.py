"""Compare a complete external RGB5/PWM frame with an independent raster model."""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
tokens=(root/'sim/build/scope_external_panel.ppm').read_text().split()
assert tokens[:4]==['P3','64','64','31']
actual=list(map(int,tokens[4:]))
rom=[int(x,16) for x in (root/'src/scope_style.hex').read_text().split()]
expected=[]
color=(16,0,31)
for y in range(64):
    row=y%32
    for x in range(64):
        c=(0,0,0)
        if x>=16 and 8<=y<=45:
            if y==27 and x%4==0 or x in (16,39,63) and y%8==3:c=(0,2,2)
            # 11 initial +1024 samples, then -1024: first/second/last
            # stored bins distinguish stale synchronous address prefetch.
            top=23 if x in (16,17) else 31
            bottom=23 if x==16 else 31
            if top<=y<=bottom:c=color
        digit=26<=row<=30 and 8<=x<20
        if not digit:
            word=rom[1024+row*8+x//8]
            if word>>(x%8+(8 if y>=32 else 0))&1:
                c=(9,12,12) if y<32 else (0,4,3) if row==14 else (11,15,14)
        if y<32 and 12<=x<=14 and 25<=row<=29 and (x!=13 or row in (25,29)):c=(9,12,12)
        if y>=32 and digit:
            cell=x//4
            value={2:15,3:0,4:3}[cell]
            index=14-(row-26)*3-x%4
            if x%4!=3 and rom[value]>>index&1:c=(11,15,14)
        if y>=32 and 27<=row<=29 and x==32:c=color
        expected.extend(c)
assert len(actual)==len(expected)==12288
bad=[(i//3%64,i//192,i%3,a,e) for i,(a,e) in enumerate(zip(actual,expected)) if a!=e]
assert not bad, f'{len(bad)} external RGB5 mismatches, first={bad[:5]}'
print('PASS external scope: 4096 pixels / 12288 RGB5 channels, all 32 PWM phases, static axes/header, dynamic PK digits, first/last capture columns and fixed meter')
