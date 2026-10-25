apds_serial_place1 在 place1 下完整布线且时序通过；相对同策略基线净少 95 CLS、179 Logic。500 CLS 目标尚未达到，未接入生产。

| 构建 | Logic | CLS | Register | BSRAM | DSP | 未布线 | setup/hold WNS ns | 状态 |
|---|---:|---:|---:|---:|---:|---:|---|---|
| engine_share_base_20261024 | 21603 | 11326 | 10461 | 47 | 26.5 | 0 | +0.083/+0.152 | validated |
| baseline_place1 | 21603 | 11310 | 10461 | 47 | 26.5 | 0 | +0.010/+0.156 | validated |
| apds_serial_place1 | 21424 | 11215 | 10466 | 47 | 26.5 | 0 | +0.161/+0.197 | validated |
| flash_rotate_place1 | 21666 | 11234 | 10467 | 47 | 26.5 | 233 | 不可验收 | routing_failed |

- `baseline_place1`：相对本轮 place1 基线 Logic +0、CLS +0、Register +0、BSRAM +0、DSP +0；相对相同 RTL 的 place0 Logic +0、CLS -16、Register +0、BSRAM +0、DSP +0。
- `apds_serial_place1`：相对本轮 place1 基线 Logic -179、CLS -95、Register +5、BSRAM +0、DSP +0；相对相同 RTL 的 place0 Logic +0、CLS -49、Register +0、BSRAM +0、DSP +0。
- `flash_rotate_place1`：相对本轮 place1 基线 Logic +63、CLS -76、Register +6、BSRAM +0、DSP +0；相对相同 RTL 的 place0 Logic +0、CLS -8、Register +0、BSRAM +0、DSP +0。
