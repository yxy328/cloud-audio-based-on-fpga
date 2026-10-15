"""Compare decoded pin-level PCM and timestamps from the same RTL/netlist stimulus."""
import argparse
import csv
import hashlib
from pathlib import Path

build = Path(__file__).resolve().parents[1] / "sim" / "build"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--rtl", type=Path, default=build / "decoded_pcm_rtl_quick.csv")
parser.add_argument("--netlist", type=Path, default=build / "decoded_pcm_netlist_quick.csv")
args = parser.parse_args()

def read_pcm(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return [(int(row["time_ns"]), int(row["pcm"])) for row in csv.DictReader(stream)]

rtl, netlist = read_pcm(args.rtl), read_pcm(args.netlist)
if len(rtl) < 1000 or len(rtl) != len(netlist):
    raise SystemExit(f"FAIL: insufficient/mismatched sample counts: {len(rtl)} / {len(netlist)}")
for index, (expected, actual) in enumerate(zip(rtl, netlist)):
    if expected != actual:
        raise SystemExit(f"FAIL: decoded sample {index}: RTL {expected}, netlist {actual}")
hash_rtl = hashlib.sha256(args.rtl.read_bytes()).hexdigest().upper()
hash_netlist = hashlib.sha256(args.netlist.read_bytes()).hexdigest().upper()
print(f"PASS: all {len(rtl)} PCM samples and timestamps are identical")
print(f"RTL SHA256:     {hash_rtl}")
print(f"Netlist SHA256: {hash_netlist}")
