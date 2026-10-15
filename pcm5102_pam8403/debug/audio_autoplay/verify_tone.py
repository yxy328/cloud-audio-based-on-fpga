"""Check captured PCM against an independent sine/phase model."""
import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "audio_gao"))
from analyze_capture import analyze

MODULUS = 1 << 32
ADDRESS_WIDTH = 1 << 24
INC = 38_702_432


def allowed_initial_phases(addresses, sample_index):
    ranges = []
    for address in addresses:
        start = (address * ADDRESS_WIDTH - sample_index * INC) % MODULUS
        end = start + ADDRESS_WIDTH
        if end <= MODULUS:
            ranges.append((start, end))
        else:
            ranges.extend(((start, MODULUS), (0, end - MODULUS)))
    return ranges


def verify(path, shift):
    result = analyze(path)
    left = [word for word in result["decoded_words"] if word["channel"] == "L"]
    if len(left) < 50:
        raise ValueError("Need at least 50 decoded samples for this tone check")
    if any(b["time_ns"] - a["time_ns"] != 20480 for a, b in zip(left, left[1:])):
        raise ValueError("Discontinuous PCM sample timestamps")
    # Math model, without reading the RTL table or NCO register.
    pcm_by_address = [round(32767 * math.sin(2 * math.pi * a / 256)) >> shift for a in range(256)]
    possible = [(0, MODULUS)]
    for index, word in enumerate(left):
        addresses = [a for a, value in enumerate(pcm_by_address) if value == word["pcm"]]
        allowed = allowed_initial_phases(addresses, index)
        narrowed = []
        for start, end in possible:
            for lo, hi in allowed:
                overlap = (max(start, lo), min(end, hi))
                if overlap[0] < overlap[1]:
                    narrowed.append(overlap)
        possible = sorted(set(narrowed))
        if not possible:
            raise ValueError(f"PCM sample {index} ({word['pcm']}) disagrees with the sine/phase model")
    values = [word["pcm"] for word in left]
    if not min(values) < 0 < max(values):
        raise ValueError("Capture does not include both positive and negative samples")
    phase = possible[0][0]
    result["tone_check"] = {
        "volume_shift": shift,
        "phase_increment": INC,
        "nominal_sample_rate_hz": 50_000_000 / 1024,
        "nominal_tone_hz": INC * (50_000_000 / 1024) / MODULUS,
        "left_sample_count": len(left),
        "pcm_min": min(values),
        "pcm_max": max(values),
        "nonzero_left_samples": sum(value != 0 for value in values),
        "initial_phase_intervals_exclusive_end": possible,
        "model_example_initial_phase": phase,
        "exact_quantized_sequence_match": True,
        "note": "Frequency is computed from the validated phase model and nominal 50 MHz, not independently measured by GAO.",
    }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("--shift", type=int, default=4)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.capture, args.shift)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"key_counts": result["key_counts"], "bck_period_ns": result["bck_rising_period_ns"], "lrck_period_ns": result["lrck_full_period_ns"], "format_errors": result["format_errors"], "stereo_pairs": result["stereo_pairs"], "stereo_mismatches": result["stereo_mismatches"], "tone": result["tone_check"]}, ensure_ascii=False, indent=2))
