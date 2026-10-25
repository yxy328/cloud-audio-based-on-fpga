# FX frozen-build audit

Baseline: `fx_base_20261024`; resources in order Logic / CLS / Register / BSRAM / DSP.

| Build | Strategy place/route/fanout | Status | Used resources | Delta | Unrouted | Setup / hold WNS (ns) |
|---|---|---|---|---|---|---|
| fx_base_20261024 | 3/0/23 | validated | 21963 / 11300 / 10442 / 47 / 26.5 | - / - / - / - / - | 0 | 0.036 / 0.151 |
| fx_dedup_20261024 | 3/0/23 | routing_failed | 21600 / 11210 / 10461 / 47 / 26.5 | -363 / -90 / +19 / +0 / +0 | 277 | ? / ? |
| fx_dedup_p0r1f23 | 0/1/23 | routing_failed | 21603 / 11326 / 10461 / 47 / 26.5 | -360 / +26 / +19 / +0 / +0 | 4210 | ? / ? |
| fx_dedup_p1r1f32 | 1/1/32 | routing_failed | 21603 / 11310 / 10461 / 47 / 26.5 | -360 / +10 / +19 / +0 / +0 | 3185 | ? / ? |
| fx_dedup_p2r0f32 | 2/0/32 | timing_failed | 21607 / 11266 / 10461 / 47 / 26.5 | -356 / -34 / +19 / +0 / +0 | 0 | -0.499 / 0.144 |
| fx_dedup_p3r0f21 | 3/0/21 | routing_failed | 21600 / 11210 / 10461 / 47 / 26.5 | -363 / -90 / +19 / +0 / +0 | 277 | ? / ? |
| fx_dedup_p3r0f32 | 3/0/32 | routing_failed | 21600 / 11210 / 10461 / 47 / 26.5 | -363 / -90 / +19 / +0 / +0 | 277 | ? / ? |
| fx_dedup_p4r2f23 | 4/2/23 | routing_failed | 21600 / 11439 / 10461 / 47 / 26.5 | -363 / +139 / +19 / +0 / +0 | 72 | ? / ? |
| fx_dedup_syn | 3/0/23 | synthesis_only | ? / ? / ? / ? / ? | - / - / - / - / - | None | ? / ? |
| fx_dedup_t_p0r0f23 | 0/0/23 | validated | 21603 / 11326 / 10461 / 47 / 26.5 | -360 / +26 / +19 / +0 / +0 | 0 | 0.083 / 0.152 |
| fx_dedup_t_p1r0f32 | 1/0/32 | validated | 21603 / 11310 / 10461 / 47 / 26.5 | -360 / +10 / +19 / +0 / +0 | 0 | 0.01 / 0.156 |
| fx_dedup_t_p2r0f50 | 2/0/50 | timing_failed | 21607 / 11266 / 10461 / 47 / 26.5 | -356 / -34 / +19 / +0 / +0 | 0 | -0.499 / 0.144 |
| fx_dedup_t_p2r1f32 | 2/1/32 | routing_failed | 21607 / 11266 / 10461 / 47 / 26.5 | -356 / -34 / +19 / +0 / +0 | 2835 | ? / ? |
| fx_dedup_t_p2r2f32 | 2/2/32 | timing_failed | 21607 / 11266 / 10461 / 47 / 26.5 | -356 / -34 / +19 / +0 / +0 | 0 | -2.375 / 0.147 |

Only `validated` builds satisfy routing and setup/hold checks. Failed-route resource deltas are diagnostic, not delivered capacity.

Each candidate's manifest, exact input differences, bitstream SHA256, endpoint counts and worst paths are recorded in `build_audit.json`.
