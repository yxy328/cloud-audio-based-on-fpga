# FX frozen-build audit

Baseline: `engine_share_base_20261024`; resources in order Logic / CLS / Register / BSRAM / DSP.

| Build | Strategy place/route/fanout | Status | Used resources | Delta | Unrouted | Setup / hold WNS (ns) |
|---|---|---|---|---|---|---|
| engine_share_base_20261024 | 0/0/23 | validated | 21603 / 11326 / 10461 / 47 / 26.5 | - / - / - / - / - | 0 | 0.083 / 0.152 |
| engine_merge_candidate_20261024_01 | 0/0/23 | routing_failed | 22312 / 11392 / 10410 / 46 / 24.5 | +709 / +66 / -51 / -1 / -2 | 217 | ? / ? |
| engine_merge_candidate_20261024_p1r0f32 | 1/0/32 | routing_failed | 22312 / 11369 / 10410 / 46 / 24.5 | +709 / +43 / -51 / -1 / -2 | 228 | ? / ? |
| engine_merge_default_off_20261024_02 | 0/0/23 | validated | 21603 / 11326 / 10461 / 47 / 26.5 | +0 / +0 / +0 / +0 / +0 | 0 | 0.083 / 0.152 |
| engine_merge_place3_probe_20261024 | 3/0/23 | routing_failed | 21600 / 11205 / 10461 / 47 / 26.5 | -3 / -121 / +0 / +0 / +0 | 247 | ? / ? |

Only `validated` builds satisfy routing and setup/hold checks. Failed-route resource deltas are diagnostic, not delivered capacity.

Each candidate's manifest, exact input differences, bitstream SHA256, endpoint counts and worst paths are recorded in `build_audit.json`.
