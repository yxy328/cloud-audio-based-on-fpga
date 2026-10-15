"""Plot current end-to-end I2S simulation CSV, not hardware measurements."""
import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--kind", choices=("rtl", "netlist"), default="rtl")
args = parser.parse_args()
build = Path(__file__).resolve().parents[1] / "sim" / "build"
data = np.loadtxt(build / f"decoded_pcm_{args.kind}.csv", delimiter=",", skiprows=1)
time_ms = data[:, 0] / 1e6
pcm = data[:, 1]
if len(pcm) < 4096 or not np.all(np.diff(data[:, 0]) == 20480):
    raise ValueError("Expected at least 4096 decoded samples at 48,828.125Hz")

font = Path("C:/Windows/Fonts/msyh.ttc")
if font.exists():
    font_manager.fontManager.addfont(str(font))
    plt.rcParams["font.family"] = font_manager.FontProperties(fname=str(font)).get_name()
plt.rcParams.update({"axes.unicode_minus": False, "font.size": 10})

length, hop, fs = 4096, 256, 48828.125
window = np.hanning(length)
starts = np.arange(0, len(pcm) - length + 1, hop)
frames = np.stack([pcm[start:start + length] * window for start in starts])
amplitudes = 2 * np.abs(np.fft.rfft(frames, axis=1)) / window.sum()
frequency = np.fft.rfftfreq(length, 1 / fs)
centers_ms = time_ms[starts] + (length - 1) * 0.02048 / 2
band = (frequency >= 350) & (frequency <= 970)
db = 20 * np.log10(np.maximum(amplitudes[:, band], 0.1))

fig, axes = plt.subplots(2, 1, figsize=(11, 7), layout="constrained",
                         gridspec_kw={"height_ratios": [1, 1.7]})
axes[0].plot(time_ms, pcm, linewidth=0.5, color="#176b9e")
axes[0].set(xlim=(0, time_ms[-1]), ylim=(-8500, 8500),
            title="混音 PCM：起音、单独释放与变调、整体释放", ylabel="数字幅度")
axes[0].grid(alpha=0.15)
mesh = axes[1].pcolormesh(centers_ms, frequency[band], db.T,
                          shading="auto", cmap="magma", vmin=-20, vmax=66,
                          rasterized=True)
axes[1].set(xlim=(0, time_ms[-1]), ylim=(350, 970),
            title="频谱随时间：C5 独立渐弱、恢复，再变为 D5；其余三个音继续",
            xlabel="仿真时间（ms）", ylabel="频率（Hz）")
axes[1].set_yticks([440, 523.2511306, 587.3295358, 659.2551138, 880],
                  ["A4 · 440", "C5 · 523.25", "D5 · 587.33", "E5 · 659.26", "A5 · 880"])
fig.colorbar(mesh, ax=axes[1], label="频率分量幅度（dB，参考 1 PCM 单位）")
fig.suptitle(f"四声部实时合成：外部 I2S 解码（{args.kind.upper()} 仿真，非模拟实测）", fontsize=13)
output = build / f"polyphony_{args.kind}"
fig.savefig(output.with_suffix(".png"), dpi=170)
fig.savefig(output.with_suffix(".svg"))
plt.close(fig)
print(f"Saved {output.with_suffix('.png')} and .svg; {len(pcm)} decoded samples")
