"""Decode a Gowin GAO CSV using captured BCK edges, not internal TX state."""
import argparse
import csv
import json
from collections import Counter
from pathlib import Path


def analyze(path):
    rows = list(csv.reader(path.read_text(encoding="utf-8-sig").splitlines()))
    header_index = next(i for i, row in enumerate(rows) if row and row[0].strip().startswith("time unit:"))
    header = [field.strip() for field in rows[header_index]]
    if header[0] != "time unit: ns":
        raise ValueError("Export with a 20 ns clock period and ns units")
    names = ["key_s1", "i2s_bck", "i2s_lrck", "i2s_din"]
    indexes = [header.index(name) for name in names]
    samples = []
    for row in rows[header_index + 1:]:
        if len(row) < max(indexes) + 1:
            continue
        values = [row[index].strip() for index in indexes]
        if any(value not in ("0", "1") for value in values):
            continue  # GAO exports an initial unknown row; do not treat it as data.
        for name, index in zip(names, indexes):
            if row[index].strip() != row[index + 1].strip():
                raise ValueError(f"Bus and bit disagree for {name}")
        samples.append((int(row[0]), *(int(value) for value in values)))
    if len(samples) < 1025:
        raise ValueError("Capture is too short")
    ticks = Counter(samples[i][0] - samples[i - 1][0] for i in range(1, len(samples)))
    if set(ticks) != {20}:
        raise ValueError(f"Unexpected sampling period: {ticks}")
    rises, falls, lr_changes, din_changes = [], [], [], []
    for i in range(1, len(samples)):
        before, after = samples[i - 1], samples[i]
        if before[2] == 0 and after[2] == 1:
            rises.append(i)
        if before[2] == 1 and after[2] == 0:
            falls.append(i)
        if before[3] != after[3]:
            lr_changes.append(i)
        if before[4] != after[4]:
            din_changes.append(i)
    period_bck = Counter(samples[b][0] - samples[a][0] for a, b in zip(rises, rises[1:]))
    period_lrck = Counter(samples[b][0] - samples[a][0] for a, b in zip(lr_changes, lr_changes[2:]))
    fall_set = set(falls)
    words = []
    format_errors = []
    for start, end in zip(lr_changes, lr_changes[1:]):
        bits = [samples[i][4] for i in rises if start <= i < end]
        if len(bits) != 32:
            format_errors.append(f"Slot at {samples[start][0]} ns: {len(bits)} BCK rises")
            continue
        if bits[0] != 0 or any(bits[17:]):
            format_errors.append(f"Nonzero delay/padding at {samples[start][0]} ns")
        value = 0
        for bit in bits[1:17]:
            value = (value << 1) | bit
        if value & 0x8000:
            value -= 0x10000
        words.append({"time_ns": samples[start][0], "channel": "L" if samples[start][3] == 0 else "R", "key": samples[start][1], "pcm": value})
    pairs = [(left, right) for left, right in zip(words, words[1:]) if left["channel"] == "L" and right["channel"] == "R"]
    mismatches = [(left["time_ns"], left["pcm"], right["pcm"]) for left, right in pairs if left["pcm"] != right["pcm"]]
    result = {
        "file": str(path),
        "known_samples": len(samples),
        "capture_span_ns": samples[-1][0] - samples[0][0],
        "sample_period_ns": dict(ticks),
        "key_counts": dict(Counter(sample[1] for sample in samples)),
        "din_counts": dict(Counter(sample[4] for sample in samples)),
        "bck_rising_period_ns": dict(period_bck),
        "lrck_full_period_ns": dict(period_lrck),
        "lrck_changes_off_bck_fall": len(set(lr_changes) - fall_set),
        "din_changes_off_bck_fall": len(set(din_changes) - fall_set),
        "format_errors": format_errors,
        "decoded_words": words,
        "stereo_pairs": len(pairs),
        "stereo_mismatches": mismatches,
    }
    if set(period_bck) != {320} or set(period_lrck) != {20480}:
        raise ValueError(f"Unexpected I2S clocks: {result}")
    if result["lrck_changes_off_bck_fall"] or result["din_changes_off_bck_fall"] or format_errors or mismatches:
        raise ValueError(f"I2S check failed: {result}")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = analyze(args.capture)
    serialized = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)
