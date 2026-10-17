"""Compare the RTL's complex transform with an independent NumPy FFT."""
import csv
import math
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parents[1]
constants = [int(word, 16) for word in (root / "src/fft256_init.hex").read_text().split()]
assert len(constants) == 1024
for k in range(128):
    expected_pair = [round(32767 * math.cos(2 * math.pi * k / 256)) & 65535,
                     round(-32767 * math.sin(2 * math.pi * k / 256)) & 65535]
    assert constants[512 + 2*k:514 + 2*k] == expected_pair
print("PASS all 128 complex twiddle constants")
rows = list(csv.DictReader((root / "sim/build/audio_spectrum_numeric.csv").open()))
assert len(rows) == 1024, len(rows)
for scenario in range(4):
    data = [r for r in rows if int(r["scenario"]) == scenario]
    assert [int(r["index"]) for r in data] == list(range(256))
    samples = np.array([int(r["input"]) for r in data], dtype=float)
    actual = np.array([complex(int(r["real"]), int(r["imag"])) for r in data])
    expected = np.fft.fft(samples) / 256
    error = max(np.max(np.abs(actual.real - expected.real)), np.max(np.abs(actual.imag - expected.imag)))
    assert error < 9, (scenario, error)
    print(f"PASS scenario {scenario}: all 256 complex bins, max component error {error:.4f} LSB")
print("PASS independent FFT numerical check")
