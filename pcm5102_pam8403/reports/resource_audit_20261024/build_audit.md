# FX frozen-build audit

Baseline: `engine_share_base_20261024`; resources in order Logic / CLS / Register / BSRAM / DSP.

| Build | Strategy place/route/fanout | Status | Used resources | Delta | Unrouted | Setup / hold WNS (ns) |
|---|---|---|---|---|---|---|
| engine_share_base_20261024 | 0/0/23 | validated | 21603 / 11326 / 10461 / 47 / 26.5 | - / - / - / - / - | 0 | 0.083 / 0.152 |
| resource_apds_width17_20261024 | 0/0/23 | routing_failed | 21452 / 11264 / 10459 / 47 / 24.5 | -151 / -62 / -2 / +0 / -2 | 460 | ? / ? |

Only `validated` builds satisfy routing and setup/hold checks. Failed-route resource deltas are diagnostic, not delivered capacity.

Each candidate's manifest, exact input differences, bitstream SHA256, endpoint counts and worst paths are recorded in `build_audit.json`.
