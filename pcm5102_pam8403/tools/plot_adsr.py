"""Plot captured RTL data. Requires matplotlib; no hardware measurements."""
from pathlib import Path
import csv
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager

project = Path(__file__).resolve().parents[1]
build = project / "sim" / "build"
font = Path("C:/Windows/Fonts/msyh.ttc")
if font.exists():
    font_manager.fontManager.addfont(str(font))
    plt.rcParams["font.family"] = font_manager.FontProperties(fname=str(font)).get_name()
plt.rcParams.update({"axes.unicode_minus": False, "font.size": 11})

with (build / "envelope_samples.csv").open() as stream:
    rows = list(csv.DictReader(stream))
# First complete key press/release in the unit test; sample-domain timestamps.
rows = rows[:1 + 98 + 3906 + 200 + 24414 + 1]
t = [int(r["sample_index"]) * 0.02048 for r in rows]
g = [int(r["gain"]) * 100 / 65535 for r in rows]
release_ms = (1 + 98 + 3906 + 200) * 0.02048

fig, ax = plt.subplots(figsize=(10, 4.4), layout="constrained")
ax.plot(t, g, color="#176b9e", linewidth=2.5)
ax.fill_between(t, g, color="#176b9e", alpha=0.10)
ax.axvline(release_ms, color="#b66a20", linestyle="--", linewidth=1)
ax.text(0.6, 106, "按下 S1", fontsize=10)
ax.text(release_ms + 2, 106, "松开 S1", fontsize=10, color="#9d5612")
ax.text(100, 98, "D：约 80ms 衰减到 60%")
ax.text(280, 42, "R：约 500ms 渐弱到零")
ax.annotate("S：按住维持 60%\n测试中维持 4.096ms", xy=(84, 60),
            xytext=(150, 77), arrowprops={"arrowstyle": "->", "color": "#555"}, fontsize=10)
ax.set(title="单声部 ADSR：RTL 采样域仿真", xlabel="音频采样对应时间（ms）", ylabel="包络幅度（%）")
ax.set(xlim=(0, t[-1] + 4), ylim=(0, 114))
ax.grid(alpha=0.18)
inset = ax.inset_axes([0.68, 0.57, 0.28, 0.31])
inset.plot(t[:105], g[:105], color="#176b9e", linewidth=2)
inset.set(title="A：2.007ms 渐强", xlim=(0, 2.15), ylim=(0, 103))
inset.tick_params(labelsize=8)
inset.grid(alpha=0.18)
fig.savefig(build / "adsr_envelope.png", dpi=180)
fig.savefig(build / "adsr_envelope.svg")
plt.close(fig)

with (build / "decoded_pcm_rtl.csv").open() as stream:
    pcm_rows = list(csv.DictReader(stream))
pcm_t = [int(r["time_ns"]) / 1e6 for r in pcm_rows]
pcm = [int(r["pcm"]) for r in pcm_rows]
fig, axes = plt.subplots(2, 1, figsize=(10, 6), layout="constrained")
for ax, limits, title in zip(axes, [(0, 670), (1.8, 8.5)],
                            ["外部 I2S 解码：起音、持续与释放", "起音局部：振幅逐样本增加"]):
    ax.plot(pcm_t, pcm, color="#176b9e", linewidth=0.7)
    ax.set(xlim=limits, ylim=(-2200, 2200), title=title, xlabel="仿真时间（ms）", ylabel="PCM 幅度")
    ax.grid(alpha=0.18)
fig.suptitle("S1 / S2 顶层 RTL 仿真（非上板实测）")
fig.savefig(build / "adsr_pcm.png", dpi=180)
plt.close(fig)
print("Saved sim/build/adsr_envelope.png, adsr_envelope.svg, adsr_pcm.png")
