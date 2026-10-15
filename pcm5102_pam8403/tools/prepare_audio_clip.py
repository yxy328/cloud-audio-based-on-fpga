"""Convert a short local audio excerpt to the FPGA PCM_* text protocol.

Requires numpy and soundfile. Dependencies can be installed without changing
the system Python: python -m pip install --target sim/build/audio_deps soundfile
The local dependency directory above is discovered automatically.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import wave

PROJECT = Path(__file__).resolve().parent.parent
LOCAL_DEPS = PROJECT / "sim" / "build" / "audio_deps"
if LOCAL_DEPS.is_dir():
    sys.path.insert(0, str(LOCAL_DEPS))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--start", type=float, default=0.0, help="Source start in seconds")
    parser.add_argument("--seconds", type=float, default=4.0, help="At most 4.096 seconds")
    parser.add_argument("--peak", type=float, default=0.6, help="Output peak, between 0 and 1")
    parser.add_argument("--output", type=Path, default=PROJECT / "audio_clips" / "settlement_4s")
    args = parser.parse_args()
    if not math.isfinite(args.start) or args.start < 0:
        parser.error("--start must be finite and non-negative")
    if not math.isfinite(args.seconds) or not 0 < args.seconds <= 4.096:
        parser.error("--seconds must be between 0 and 4.096")
    if not math.isfinite(args.peak) or not 0 < args.peak <= 1:
        parser.error("--peak must be between 0 and 1")
    try:
        import numpy as np
        import soundfile as sf
    except ImportError as exc:
        raise SystemExit(
            "Install local dependencies using this Python interpreter:\n"
            f'"{sys.executable}" -m pip install --target "{LOCAL_DEPS}" soundfile'
        ) from exc

    source = args.input.resolve()
    info = sf.info(str(source))
    target_rate = 8000
    start_frame = round(args.start * info.samplerate)
    count = min(32768, round(args.seconds * target_rate))
    if start_frame >= info.frames or count < 1:
        parser.error("Selected excerpt is empty or starts after the source ends")

    # Read guard samples around the excerpt for a windowed-sinc anti-alias
    # filter. Unlike direct decimation this removes frequencies above 4 kHz.
    half = max(32, math.ceil(16 * info.samplerate / target_rate))
    lo = max(0, start_frame-half)
    hi = min(info.frames, start_frame+math.ceil(count*info.samplerate/target_rate)+half+2)
    audio, _ = sf.read(str(source), start=lo, stop=hi, dtype="float64", always_2d=True)
    mono = np.mean(audio, axis=1)
    available_count = math.floor((info.frames-start_frame)*target_rate/info.samplerate)
    count = min(count, available_count)
    if count < 1:
        parser.error("Less than one output sample remains in the source")
    if info.samplerate > target_rate:
        n = np.arange(-half, half+1, dtype=np.float64)
        cutoff = 0.45 * target_rate / info.samplerate
        taps = 2*cutoff*np.sinc(2*cutoff*n)*np.hamming(len(n))
        taps /= np.sum(taps)
        mono = np.convolve(np.pad(mono, (half,half), mode="edge"), taps, mode="valid")
    positions = start_frame-lo + np.arange(count)*info.samplerate/target_rate
    excerpt = np.interp(positions, np.arange(len(mono)), mono)
    peak_before = float(np.max(np.abs(excerpt)))
    if peak_before > 0:
        excerpt *= args.peak/peak_before
    signed8 = np.clip(np.rint(excerpt*127), -128, 127).astype(np.int8)
    transport = signed8.view(np.uint8).tobytes()
    checksum = sum(transport) & 0xFFFF
    stem = args.output.resolve()
    stem.parent.mkdir(parents=True, exist_ok=True)
    commands = [f"PCM_BEGIN,{len(transport)},{checksum}"]
    commands.extend(f"PCM_DATA,{offset},{transport[offset:offset+16].hex().upper()}"
                    for offset in range(0, len(transport), 16))
    commands.extend(["PCM_END", "PCM_PLAY"])
    txt_path = stem.with_suffix(".txt")
    txt_path.write_text("\n".join(commands)+"\n", encoding="ascii")
    raw_path = stem.with_suffix(".s8")
    raw_path.write_bytes(transport)
    hex_path = stem.with_suffix(".hex")
    hex_path.write_text("".join(f"{value:02X}\n" for value in transport), encoding="ascii")
    wav_path = stem.with_suffix(".wav")
    with wave.open(str(wav_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(target_rate)
        # Match FPGA expansion: signed8 is shifted left by eight bits.
        wav.writeframes((signed8.astype(np.int16)*256).astype("<i2").tobytes())
    metadata = {
        "source": str(source), "source_format": info.format,
        "source_samplerate": info.samplerate, "source_channels": info.channels,
        "source_duration_seconds": info.frames/info.samplerate,
        "start_seconds": args.start, "duration_seconds": len(transport)/target_rate,
        "samples": len(transport), "sample_rate": target_rate,
        "encoding": "signed 8-bit mono; wire bytes are two's-complement HEX",
        "peak_target": args.peak, "source_excerpt_peak": peak_before,
        "checksum_sum16_unsigned_bytes": checksum,
        "pcm_sha256": hashlib.sha256(transport).hexdigest(),
        "command_lines": len(commands), "command_bytes": txt_path.stat().st_size,
        "uart_9600_minimum_seconds_without_ack": txt_path.stat().st_size*10/9600,
        "files": {"commands": str(txt_path), "pcm": str(raw_path),
                  "readmemh": str(hex_path), "preview": str(wav_path)},
        "send_policy": "Send one line, wait for OK, then send the next; retry whole PCM_DATA line on timeout.",
    }
    stem.with_suffix(".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
