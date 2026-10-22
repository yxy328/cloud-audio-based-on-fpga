"""Generate/check the one-port glyph and percentage ROM used by audio_scope."""
from pathlib import Path
import sys

ROWS = {
    "0":"111101101101111", "1":"010110010010111", "2":"110001010100111",
    "3":"110001010001110", "4":"101101111001001", "5":"111100110001110",
    "6":"011100111101111", "7":"111001010010010", "8":"111101111101111",
    "9":"111101111001110", "F":"111100110100100", "S":"011100010001110",
    "R":"110101110101101", "X":"101101010101101", "M":"101111111101101",
    "P":"110101110100100", "K":"101101110101101", "%":"101001010100101",
    "A":"010101111101101", "U":"101101101101111", "D":"110101101101110",
    "E":"111100110100111", ":":"000010000010000",
}
ROWS.update({"+":"000010111010000", "-":"000000111000000"})
values = [0] * 2048
for char, bits in ROWS.items():
    values[145+ord(char)] = int(bits, 2)
for digit in range(10):
    values[digit] = int(ROWS[str(digit)], 2)
for code in range(129):
    # Code is ceil(abs(PCM)/256). Use the bin center, rounded to an integer
    # percent, so the quantized display remains within one percentage point.
    percent = (code * 100 + 14) // 128
    values[16 + code] = ((percent // 100) << 8) | (((percent // 10) % 10) << 4) | percent % 10
for scale_index, extent in enumerate((32,16,8,4,2,1)):
    pixels=[[False]*64 for _ in range(64)]
    def text(value,x,y):
        for index,ch in enumerate(value):
            bits=ROWS.get(ch,"0"*15)
            for dy in range(5):
                for dx in range(3):
                    if bits[dy*3+dx]=='1':pixels[y+dy][x+index*4+dx]=True
    text('FSR',0,1);text('X'+str(1<<scale_index),52,1)
    for sign,y in (('+',9),('-',41)):
        value=sign+str(extent)+'K'
        text(value,15-(len(value)*4-1),y)
    text('MS',0,48);text('0',15,48);text('5',38,48);text('1',57,48);text('0',61,48)
    text('PK',0,58);text('%',20,58)
    for x in range(16,64):pixels[46][x]=True
    for x in (16,39,62):pixels[45][x]=True;pixels[47][x]=True
    for x in (32,40,48,56,63):pixels[63][x]=True
    for row in range(32):
        for group in range(8):
            word=0
            for bit in range(8):
                word |= int(pixels[row][group*8+bit])<<bit
                word |= int(pixels[row+32][group*8+bit])<<(8+bit)
            values[256+scale_index*256+row*8+group]=word
content = "".join(f"{value:04x}\n" for value in values)
path = Path(__file__).resolve().parents[1] / "src/scope_style.hex"
if "--check" in sys.argv:
    if path.read_text(encoding="ascii") != content:
        raise SystemExit("scope_style.hex is stale")
    print(f"PASS scope style ROM: {len(ROWS)} glyphs, 129 rounded percentages, six static scope layouts in one 2048x16 image")
else:
    path.write_text(content, encoding="ascii")
    print(path)
