# Fix_Timing6: ordinary BTB-based JALR prediction

This round adds ordinary indirect-target prediction to the FixTiming5
GShare+BTB predictor. RAS is intentionally not included yet.

## RTL changes

- `pipe/bpu.v`: adds one indirect-type bit per BTB entry. A matching JALR
  entry predicts taken unconditionally from its BTB target. JALR updates write
  the BTB target/type but do not update PHT or GHR. Direct JAL and conditional
  branch training keeps the previous behavior.
- `pipe/pipe_if_id.v` and `pipe/pipe_id_ex.v`: carry the prediction-source bit
  through the pipeline. ID/EX also registers one-bit branch/JAL/JALR
  predecode controls so EX recovery and training do not decode the 18-bit
  operation code on the critical path.
- `pipe/ex_bpu_ctrl.v`: trains JALR targets and validates an adopted JALR
  prediction against the resolved EX target. A target mismatch redirects even
  when the direction is taken in both cases. The compare is gated by the
  registered JALR controls and compares bits `[31:1]`, since RV32I JALR clears
  bit 0. Ordinary direct predictions do not enter this target-compare path.
- `KLDJ_top.v`: wires the new metadata and update type through the existing
  IF/ID, ID/EX, BPU and EX control structure.

## Simulation verification

All tests were compiled and elaborated with Vivado Simulator 2023.2 using the
current RTL. The following passed:

- BPU unit test, including JALR type allocation, target replacement, and no
  GHR/PHT pollution.
- EX/BPU control test: 41 checks, including cold JALR, correct target, and
  target mismatch recovery.
- BPU/CPU integration: `updates=12`, `hits=4`, `GHR=63`.
- Full CPU regression: `29 PASSED, 0 FAILED`.
- RV32M wrapper regression.

## JALR workload A/B result

The dedicated workload is selected in `KLDJ_branch_perf_tb.sv` with the
testbench-only `JALR_BASELINE` plusarg. Architectural signatures are unchanged:

| Metric | Before | After |
| --- | ---: | ---: |
| Cycles | 33866 | 25686 |
| IPC / CPI | 0.6359 / 1.5725 | 0.8384 / 1.1927 |
| JALR predicted / correct / total | 0 / 0 / 6144 | 6136 / 4090 / 6144 |
| RET predicted / correct / total | 0 / 0 / 3072 | 3068 / 2045 / 3072 |
| Predictor misses / redirects | 6163 / 6163 | 2073 / 2073 |
| Register signature | `e5327a89` | `e5327a89` |
| DRAM signature | `14a4c280` | `14a4c280` |

The original `Program/irom-v2.txt` workload also retains its baseline behavior:

- Conditional prediction accuracy: `98.747%`.
- JAL correct/total: `2670/2670`.
- IPC: `0.7018`.
- Register signature: `a22530fe`.
- DRAM signature: `0cddf26c`.

## Implementation status

RTL simulation is complete. Synthesis, placement, routing, 175 MHz timing,
and on-board validation remain to be run by the user. The new EX target
compare is the timing item to inspect first; no timing-closure claim is made
until the routed report is available.
