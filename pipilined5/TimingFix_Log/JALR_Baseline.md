# JALR Baseline (before JALR RTL changes)

This baseline uses the current FixTiming5 RTL without ordinary JALR prediction
and without RAS. The existing `KLDJ_branch_perf_tb.sv` is reused; the
testbench-only `JALR_BASELINE` switch selects the dedicated images.

## Workload

The generator is `Program/build_jalr_baseline.ps1`. It produces:

- `Program/jalr_baseline_irom.txt`
- `Program/jalr_baseline_dram.txt`
- `Program/jalr_baseline.lst`

The workload keeps the generic terminal instruction at `0x80000014` and has
three control-flow phases:

1. 1024 calls through one stable indirect target, with one stable return PC.
2. 1024 calls through one JALR PC alternating between two targets.
3. 1024 calls from two JALR PCs into one shared function, so the shared RET
   alternates between two return addresses.

Conditional branches and direct JAL instructions are present in every phase.
The program checks its architectural results and writes four words to DRAM:

```text
dram[0] = 00000400
dram[1] = 00001400
dram[2] = 00000400
dram[3] = 4a4c5001
```

## Run selection

After compiling the RTL and `KLDJ_branch_perf_tb.sv` into an xsim snapshot,
run the dedicated image with the no-value plusarg below:

```text
xsim KLDJ_branch_perf_tb_jalr_baseline_sim -testplusarg JALR_BASELINE -runall
```

Without `JALR_BASELINE`, the testbench keeps its normal `Program/irom-v2.txt`
and `Program/dram.txt` defaults. The explicit `IROM_COE` and `DRAM_COE`
value-plusargs remain supported for simulators that accept value plusargs on
the command line.

## FixTiming5 result

The run was compiled and elaborated with Vivado Simulator 2023.2 from the
current RTL, then executed twice. Both runs produced the same values:

| Metric | Baseline |
| --- | ---: |
| Cycles | 33866 |
| Instructions retired | 21536 |
| IPC / CPI | 0.6359 / 1.5725 |
| Conditional branches | 5123 (taken 4093) |
| Conditional prediction accuracy | 99.629% |
| JAL correct / total | 1027 / 1027 |
| JALR predicted / correct / total | 0 / 0 / 6144 |
| RET predicted / correct / total | 0 / 0 / 3072 |
| Predictor misses / redirects | 6163 / 6163 |
| Predictor MPKI / redirect MPKI | 286.172 / 286.172 |
| Register signature | `e5327a89` |
| DRAM signature | `14a4c280` |

This is the pre-change comparison point. After ordinary JALR prediction is
added, the architectural signatures must remain unchanged while JALR
prediction misses and total redirects decrease. Conditional-branch accuracy
must be checked against this same workload as well as the original program.
