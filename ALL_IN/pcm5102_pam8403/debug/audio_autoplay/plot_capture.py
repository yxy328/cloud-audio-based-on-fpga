"""Draw hardware capture data and its independently checked PCM model."""
import csv
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

base = Path(__file__).resolve().parent / "captures"
result = json.loads((base / "autoplay_analysis.json").read_text(encoding="utf-8"))
left = [word for word in result["decoded_words"] if word["channel"] == "L"]
tone = result["tone_check"]
phase = tone["model_example_initial_phase"]
modeled = [round(32767 * math.sin(2 * math.pi * (((phase + i * tone["phase_increment"]) % (1 << 32)) >> 24) / 256)) >> tone["volume_shift"] for i in range(len(left))]
table = list(csv.reader((base / "autoplay.csv").read_text(encoding="utf-8-sig").splitlines()))
header_index = next(i for i, row in enumerate(table) if row and row[0].startswith("time unit:"))
names = [cell.strip() for cell in table[header_index]]
columns = [names.index(name) for name in ("i2s_bck", "i2s_lrck", "i2s_din")]
start = left[0]["time_ns"]
detail = []
for row in table[header_index + 1:]:
    if len(row) <= max(columns) or any(row[col].strip() not in ("0", "1") for col in columns):
        continue
    time = int(row[0])
    if start <= time <= start + 20480:
        detail.append(((time - start) / 1000, *(int(row[col]) for col in columns)))

plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False})
fig = plt.figure(figsize=(12, 7.7), layout="constrained")
grid = fig.add_gridspec(4, 1, height_ratios=[2.8, 1, 1, 1])
ax = fig.add_subplot(grid[0])
time_ms = [(word["time_ns"] - start) / 1e6 for word in left]
ax.plot(time_ms, modeled, color="#e76f51", linewidth=1.4, label="Independent quantized sine model")
ax.scatter(time_ms, [word["pcm"] for word in left], s=18, color="#0077b6", zorder=3, label="Decoded hardware PCM (left)")
ax.axhline(0, color="#a6adb4", linewidth=0.8)
ax.set(title="FPGA hardware capture: continuous tone, digital gain 1/16", xlabel="Time from first decoded left sample (ms)", ylabel="Signed 16-bit PCM", ylim=(-2250, 2250))
ax.legend(loc="upper right", fontsize=9)
ax.grid(alpha=0.18)
ax.text(0.01, 0.03, f"{len(left)} PCM samples match exactly; {result['stereo_pairs']} stereo pairs match. Nominal tone: {tone['nominal_tone_hz']:.4f} Hz.", transform=ax.transAxes, fontsize=9)

for index, (label, color) in enumerate((("BCK / K2", "#0077b6"), ("LRCK / K1", "#5b6470"), ("DIN / L1", "#e76f51"))):
    axis = fig.add_subplot(grid[index + 1])
    axis.step([row[0] for row in detail], [row[index + 1] for row in detail], where="post", linewidth=1.1, color=color)
    axis.set_xlim(0, 20.48)
    axis.set_ylim(-0.2, 1.4)
    axis.set_yticks([0, 1])
    axis.set_ylabel(label)
    axis.axvline(10.24, color="#a6adb4", linestyle="--", linewidth=0.8)
    axis.axvspan(0, 0.32, color="#efcf7d", alpha=0.3)
    axis.axvspan(10.24, 10.56, color="#efcf7d", alpha=0.3)
    if index == 0:
        axis.set_title(f"First complete stereo frame: L = R = {left[0]['pcm']}; yellow = one-BCK delay", fontsize=10)
    if index < 2:
        axis.tick_params(labelbottom=False)
    else:
        axis.set_xlabel("Time from LRCK falling edge (us)")
    axis.grid(axis="x", alpha=0.15)
fig.savefig(base / "autoplay_waveform.png", dpi=150)
fig.savefig(base / "autoplay_waveform.svg")
print(base / "autoplay_waveform.png")
