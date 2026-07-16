# FixTiming8D: ID-stage generic forwarding predecode

## Goal

Continue from the committed FixTiming8C RTL at 175 MHz without changing the
five-stage pipeline, JALR BTB prediction policy, RAS status, or external
bridge logic.

The routed FixTiming8C report has one setup violation (`WNS=-0.014 ns`). Its
worst path starts at `id_ex_rs1_addr_reg[2]` and ends at an IFU PC register.
The path is routing-dominated: `5.443 ns` data delay, of which `4.725 ns`
(86.8%) is routing. The first logic nodes are the EX-stage register-address
compare/forwarding-priority cone. A closely related path from the same source
to the DRAM BRAM enable has only `+0.004 ns` slack.

## RTL change

- `pipe/ctrl_forward_sel.v` is now used for every register operand while the
  consumer is in ID. Its existing timing model remains unchanged: current
  ID/EX and EX/MEM producers are compared against the IF/ID source addresses,
  so the registered select describes the producers visible in the consumer's
  following EX cycle.
- `pipe/pipe_id_ex.v` captures the two generic selections as
  `id_ex_rs1_fwd_sel` and `id_ex_rs2_fwd_sel`. Reset, redirect bubbles,
  load-use bubbles, and EX stalls retain the existing pipeline behavior.
- `pipe/ex_forward.v` removes the four EX-stage address-equality comparisons
  and their producer-valid gating. EX now uses only the registered 2-bit
  selections to choose regfile, EX/MEM, or MEM/WB data. Load-use detection is
  intentionally left unchanged.
- `KLDJ_top.v` uses these selected values for both generic operands and the
  existing dedicated branch/JALR operands. No extra cycle or forwarding source
  was added.

The expected timing benefit is removal of the `id_ex_rs*_addr -> equality /
priority -> operand mux` portion from EX recovery and memory-address paths.
Final timing closure must be determined from a new routed 175 MHz report.

## Verification

All simulations used a freshly compiled Vivado Simulator 2018.3 work area:
`TimingFix_Log/.fix8d_sim_work`.

| Test | Result |
| --- | --- |
| Full RTL compile | passed |
| New `ex_forward_tb` | 17 checks passed: regfile, EX/MEM, MEM/WB, store data, immediate operands, and load-use hazards |
| `ctrl_forward_sel_tb` | 8 checks passed |
| `KLDJ_top_tb` | 29 passed, 0 failed |
| `KLDJ_exu_jalr_tb` | 3 checks passed |
| `bpu_tb` | passed (`GHR=1`) |
| `ex_bpu_ctrl_tb` | 43 checks passed |

The dedicated JALR prediction workload is unchanged from FixTiming8C:

| Metric | FixTiming8D result |
| --- | ---: |
| Cycles | 25,686 |
| Instructions retired | 21,536 |
| IPC / CPI | 0.8384 / 1.1927 |
| JALR predicted / correct / total | 6136 / 4090 / 6144 |
| RET predicted / correct / total | 3068 / 2045 / 3072 |
| Redirects | 2073 |
| Register signature | `e5327a89` |
| DRAM signature | `14a4c280` |

## Implementation handoff

Run the normal project synthesis and implementation at the same 175 MHz
constraint. Compare against FixTiming8C:

1. WNS, TNS, and failing endpoints.
2. Whether the former `id_ex_rs1_addr -> IFU PC` family disappears from the
   first timing paths.
3. The BRAM-output to MEM/WB path, which was already close at `+0.012 ns` in
   FixTiming8C.
4. High-fanout reports for the new registered forwarding-select nets.

Do not add RAS until this version has a routed positive timing margin.
