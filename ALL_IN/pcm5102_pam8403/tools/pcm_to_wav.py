"""Export simulated integer PCM CSV to a computer listening reference."""
import argparse
from array import array
import csv
import sys
import wave

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("input")
parser.add_argument("output")
parser.add_argument("--source-rate", type=float, default=48828.125)
parser.add_argument("--output-rate", type=int, default=48000)
parser.add_argument("--normalize", action="store_true", help="Fixed whole-clip gain for computer listening")
args = parser.parse_args()
with open(args.input, newline="", encoding="utf-8") as stream:
    values = [int(row["pcm"]) for row in csv.DictReader(stream)]
if len(values)<2 or args.source_rate<=0 or args.output_rate<=0:
    raise SystemExit("Invalid input length or sample rate")
if any(value< -32768 or value>32767 for value in values):
    raise SystemExit("Input PCM exceeds signed 16-bit range")
peak = max(abs(value) for value in values)
gain = (0.65*32767/peak) if args.normalize and peak else 1.0
output = array("h")
length = round(len(values)*args.output_rate/args.source_rate)
for index in range(length):
    position = index*args.source_rate/args.output_rate
    left = min(int(position), len(values)-1)
    right = min(left+1, len(values)-1)
    fraction = position-left
    value = round((values[left]*(1-fraction)+values[right]*fraction)*gain)
    output.append(max(-32768,min(32767,value)))
if sys.byteorder!="little":
    output.byteswap()
with wave.open(args.output,"wb") as result:
    result.setnchannels(1)
    result.setsampwidth(2)
    result.setframerate(args.output_rate)
    result.writeframes(output.tobytes())
print(f"Saved {args.output}: {length/args.output_rate:.3f}s, mono 16-bit/{args.output_rate}Hz, fixed preview gain={gain:.4f}")
