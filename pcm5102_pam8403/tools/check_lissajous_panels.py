"""Compare externally reconstructed HUB pixels to independent sine geometry."""
import math
from pathlib import Path
from PIL import Image

build = Path(__file__).resolve().parents[1] / "sim/build"
cases = [
    ("xy_lissajous_panel", 1, 2, 0),
    ("xy_multiloop_panel", 2, 3, 0),
    ("xy_circle_panel", 1, 1, 90),
    ("xy_ellipse_panel", 1, 1, 45),
    ("xy_line_panel", 1, 1, 0),
]
for name, fx, fy, phase_degrees in cases:
    image = Image.open(build / f"{name}.ppm").convert("RGB")
    assert image.size == (64, 64)
    expected = set()
    for n in range(256):
        t = math.tau * n / 256
        x = 32 + round(14 * math.sin(fx * t))
        y = 16 - round(14 * math.sin(fy * t + math.radians(phase_degrees)))
        expected.add((x, y))
    actual = set()
    for y in range(32):
        for x in range(64):
            red, green, blue = image.getpixel((x, y))
            if red > 100 and green < 100 and blue > 150:
                actual.add((x, y))
    missing, extra = expected - actual, actual - expected
    assert not missing and not extra, f"{name}: missing={sorted(missing)}, extra={sorted(extra)}"
    print(f"PASS {name}: all {len(expected)} ideal quantized sine pixels, no missing/extra points")
print("PASS independent external HUB reference geometry")
