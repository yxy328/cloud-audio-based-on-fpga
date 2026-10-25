"""Audit frozen full-project Gowin builds; a resource table alone is not a pass."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BUILDS = PROJECT / "sim/build/unified"
METRICS = ("Logic", "CLS", "Register", "BSRAM", "DSP")


def read_text(path: Path) -> str:
    data = path.read_bytes()
    encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    return data.decode(encoding, errors="replace")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def sources(snapshot: Path) -> dict:
    manifest = snapshot / "sources.json"
    if not manifest.exists():
        return {"manifest_present": False, "entries": {}, "corrupt": []}
    entries = {row["Path"].replace("\\", "/"): row["SHA256"].upper()
               for row in json.loads(manifest.read_text(encoding="utf-8-sig"))}
    corrupt = [name for name, expected in entries.items()
               if not (snapshot / name).is_file() or digest(snapshot / name) != expected]
    return {"manifest_present": True, "entries": entries, "corrupt": corrupt}


def timing(path: Path) -> dict | None:
    if not path.exists():
        return None
    content = path.read_text(encoding="utf-8", errors="replace")
    result = {}
    for kind in ("Setup", "Hold"):
        match = re.search(rf"Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)", content)
        result[f"{kind.lower()}_violated_endpoints"] = int(match[1]) if match else None
        section = re.search(rf'name="{kind}_Slack_Table".*?<table.*?</table>', content, re.S)
        rows = []
        if section:
            for row in re.findall(r"<tr>(.*?)</tr>", section[0], re.S):
                cells = [html.unescape(re.sub(r"<[^>]+>", "", value)).strip()
                         for value in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
                if len(cells) >= 4:
                    rows.append({"slack_ns": float(cells[1]), "from": cells[2], "to": cells[3]})
        result[f"{kind.lower()}_worst_path"] = min(rows, key=lambda r: r["slack_ns"]) if rows else None
        result[f"{kind.lower()}_reported_violating_paths"] = [r for r in rows if r["slack_ns"] < 0]
    # Gowin's HTML max_common_paths=1 table can omit violated paths. The raw
    # timing_paths file and endpoint summary must also be checked.
    raw_path = path.with_name("PCM5102_UNIFIED.timing_paths")
    raw = {"setup": [], "hold": []}
    if raw_path.exists():
        for block in re.split(r"(?m)^=====\s*$", read_text(raw_path)):
            fields = [line.strip() for line in block.splitlines() if line.strip()]
            if len(fields) < 9 or fields[0].lower() not in raw:
                continue
            nodes = [line for line in fields[5:] if "/" in line]
            raw[fields[0].lower()].append({"slack_ns": float(fields[1]),
                "from_cell": nodes[0] if nodes else None,
                "to_cell": nodes[-1] if nodes else None})
    for kind, paths in raw.items():
        result[f"{kind}_raw_worst_path"] = min(paths, key=lambda r: r["slack_ns"]) if paths else None
        result[f"{kind}_raw_violating_paths"] = [r for r in paths if r["slack_ns"] < 0]
    return result


def audit(snapshot: Path, baseline_sources: dict, baseline_metrics: dict) -> dict:
    project = snapshot / "pcm5102_pam8403"
    pnr = project / "impl/pnr"
    report = pnr / "PCM5102_UNIFIED.rpt.txt"
    log_path = next((path for path in (pnr / "PCM5102_UNIFIED.log", snapshot / "pnr.log", snapshot / "build.log")
                     if path.exists()), snapshot / "build.log")
    log = read_text(log_path) if log_path.exists() else ""
    report_text = report.read_text(encoding="utf-8", errors="replace") if report.exists() else ""
    metrics = {}
    for name in METRICS:
        match = re.search(rf"^\s*{name}\s+\|\s*([\d.]+)/([\d.]+)", report_text, re.M)
        if match:
            metrics[name] = {"used": float(match[1]), "capacity": float(match[2])}
    unrouted = re.findall(r"total (\d+) unrouted nets", report_text)
    bitstream = pnr / "PCM5102_UNIFIED.fs"
    report_is_local = str(project / "impl/gwsynthesis").replace("\\", "/").lower() in report_text.replace("\\", "/").lower()
    completed = bitstream.is_file() and report_is_local
    source_info = sources(snapshot)
    expected = baseline_sources["entries"]
    actual = source_info["entries"]
    changes = [name for name in sorted(set(expected) | set(actual)) if expected.get(name) != actual.get(name)]
    script = next((project / "tools" / name for name in ("pnr_only.tcl", "resume_pnr.tcl", "build_unified.tcl")
                   if (project / "tools" / name).exists()), None)
    flags = script.read_text(encoding="utf-8-sig") if script else ""
    if (pnr / "cmd.do").exists():
        flags = read_text(pnr / "cmd.do")
    strategy = {name: int(matches[-1]) if (matches := re.findall(rf"-{name} (\d+)", flags)) else None
                for name in ("place_option", "route_option", "route_maxfan")}
    timing_info = timing(pnr / "PCM5102_UNIFIED_tr_content.html")
    errors = re.findall(r"^.*\bERROR\s*\([^\n]+", log, re.M)
    status = "incomplete"
    if not report.exists() and re.search(r"\brun syn\b", flags) and "GowinSynthesis finish" in log:
        status = "synthesis_only"
    if unrouted:
        status = "routing_failed"
    elif completed:
        status = "timing_unverified"
        if (timing_info and len(metrics) == len(METRICS) and
            all(timing_info[f"{kind}_violated_endpoints"] == 0 and
                not timing_info[f"{kind}_raw_violating_paths"] for kind in ("setup", "hold"))):
            status = "validated"
        elif timing_info and any((timing_info[f"{kind}_violated_endpoints"] or 0) > 0 for kind in ("setup", "hold")):
            status = "timing_failed"
    elif errors and not report_text and "GowinSynthesis finish" not in log:
        status = "build_failed"
    if source_info["corrupt"]:
        status = "snapshot_integrity_failed"
    elif status == "validated" and not source_info["manifest_present"]:
        status = "snapshot_integrity_unverified"
    return {
        "label": snapshot.name, "status": status, "strategy": strategy,
        "metrics": metrics,
        "delta_vs_baseline": {name: metrics[name]["used"] - baseline_metrics[name]["used"]
                              for name in METRICS if name in metrics and name in baseline_metrics},
        "unrouted_nets": max(map(int, unrouted)) if unrouted else (0 if completed else None),
        "bitstream_present": bitstream.is_file(),
        "bitstream_sha256": digest(bitstream) if bitstream.is_file() else None,
        "timing": timing_info, "changed_inputs_vs_baseline": changes,
        "changed_input_hashes": {name: {"baseline": expected.get(name), "candidate": actual.get(name)} for name in changes},
        "source_manifest": str(snapshot / "sources.json"),
        "source_manifest_sha256": digest(snapshot / "sources.json") if source_info["manifest_present"] else None,
        "downloadable_song_sha256": actual.get("pcm5102_pam8403/src/downloadable_song.v"),
        "snapshot_corrupt_inputs": source_info["corrupt"], "errors": errors,
        "pnr_log": str(log_path),
        "resource_report": str(report), "timing_content": str(pnr / "PCM5102_UNIFIED_tr_content.html"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="fx_base_20261024")
    parser.add_argument("--output", type=Path, default=PROJECT / "reports/fx_preflight_20261024")
    parser.add_argument("--labels", nargs="*")
    args = parser.parse_args()
    base_path = BUILDS / args.baseline
    base_sources = sources(base_path)
    base = audit(base_path, base_sources, {})
    candidates = [BUILDS / label for label in args.labels] if args.labels else sorted(BUILDS.glob("fx_dedup*"))
    results = [base] + [audit(path, base_sources, base["metrics"]) for path in candidates]
    workspace_differences = [name for name, expected in base_sources["entries"].items()
                             if not (PROJECT.parent / name).is_file() or digest(PROJECT.parent / name) != expected]
    payload = {
        "checked_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "baseline": args.baseline, "workspace_changed_inputs_vs_baseline": workspace_differences,
        "builds": results,
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "build_audit.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# FX frozen-build audit", "", f"Baseline: `{args.baseline}`; resources in order Logic / CLS / Register / BSRAM / DSP.", "",
             "| Build | Strategy place/route/fanout | Status | Used resources | Delta | Unrouted | Setup / hold WNS (ns) |", "|---|---|---|---|---|---|---|"]
    for result in results:
        strategy = "/".join(str(result["strategy"][key]) for key in ("place_option", "route_option", "route_maxfan"))
        used = " / ".join(f'{result["metrics"][name]["used"]:g}' if name in result["metrics"] else "?" for name in METRICS)
        delta = " / ".join(f'{result["delta_vs_baseline"][name]:+g}' if name in result["delta_vs_baseline"] else "-" for name in METRICS)
        timing_info = result["timing"] or {}
        wns = " / ".join(str((timing_info.get(f"{kind}_raw_worst_path") or timing_info[f"{kind}_worst_path"])["slack_ns"])
                         if timing_info.get(f"{kind}_worst_path") else "?" for kind in ("setup", "hold"))
        lines.append(f'| {result["label"]} | {strategy} | {result["status"]} | {used} | {delta} | {result["unrouted_nets"]} | {wns} |')
    lines += ["", "Only `validated` builds satisfy routing and setup/hold checks. Failed-route resource deltas are diagnostic, not delivered capacity.", "",
              "Each candidate's manifest, exact input differences, bitstream SHA256, endpoint counts and worst paths are recorded in `build_audit.json`."]
    (args.output / "build_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
