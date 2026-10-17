"""Check the last 4096 settled mono samples from TEST32 (RTL or board I2S CSV).

CSV columns: time_ns,pcm. For board I2S captures export signed 16-bit mono samples
at measured LRCK, then use --sample-rate. This check is not analog-board proof
when its input comes from RTL simulation.
"""
import argparse
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--sample-rate", type=float, default=50_000_000 / 1024)
    parser.add_argument("--output", type=Path, default=Path("sim/build/test32_spectrum"))
    args = parser.parse_args()
    capture = np.loadtxt(args.capture, delimiter=",", skiprows=1, ndmin=2)
    if len(capture) < 4096:
        raise SystemExit("FAIL: need at least 4096 settled samples")
    samples = capture[-4096:, 1]
    amplitude = np.abs(np.fft.rfft(samples - samples.mean())) * 2 / len(samples)
    bins = 37 + 7 * np.arange(32)
    peaks = amplitude[bins]
    if np.any(peaks < 200) or np.max(np.abs(samples)) >= 32767:
        raise SystemExit(f"FAIL: missing audible test tones or clipping, min amplitude={peaks.min():.3f}")
    # Require each expected bin to be a separate local maximum, not a shoulder.
    if np.any(peaks < 10 * np.maximum(amplitude[bins - 1], amplitude[bins + 1])):
        raise SystemExit("FAIL: expected tones are not resolved independent peaks")
    frequencies = bins * args.sample_rate / len(samples)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    table = np.column_stack((np.arange(1, 33), bins, frequencies, peaks))
    np.savetxt(args.output.with_suffix(".csv"), table, delimiter=",", fmt=["%d", "%d", "%.6f", "%.3f"],
               header="voice,fft_bin,frequency_hz,amplitude_lsb", comments="")
    result = dict(source=str(args.capture), samples=4096, sample_rate=args.sample_rate,
                  independent_peaks=32, throughput=32 * args.sample_rate,
                  minimum_amplitude=float(peaks.min()), maximum_amplitude=float(peaks.max()),
                  maximum_absolute_sample=int(np.max(np.abs(samples))))
    args.output.with_suffix(".json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(12, 4), layout="constrained")
    hz = np.arange(len(amplitude)) * args.sample_rate / len(samples)
    ax.plot(hz, 20 * np.log10(np.maximum(amplitude, 0.01) / 32768), lw=0.8)
    ax.scatter(frequencies, 20 * np.log10(peaks / 32768), color="#d14a24", s=14, label="32 independent tones")
    ax.set(xlim=(0, 3300), ylim=(-110, -25), xlabel="Frequency (Hz)", ylabel="Amplitude (dBFS)",
           title=f"TEST32: external I2S decode, Fs={args.sample_rate:.3f} Hz, FFT=4096")
    ax.grid(alpha=0.2)
    ax.legend(loc="lower right")
    fig.savefig(args.output.with_suffix(".png"), dpi=160)
    plt.close(fig)
    print("PASS TEST32 spectrum:", json.dumps(result))


if __name__ == "__main__":
    main()
