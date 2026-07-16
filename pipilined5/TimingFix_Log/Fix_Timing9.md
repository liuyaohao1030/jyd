# FixTiming9: ID-stage generic forwarding predecode

## Goal

Close the remaining FixTiming8C 175 MHz setup violation without changing the
five-stage pipeline, the ordinary BTB JALR policy, the RAS status, or the
external bridge.  FixTiming8C has one failing endpoint (`WNS=-0.014 ns`):
`id_ex_rs1_addr_reg[2] -> IFU PC`.  Its 5.443 ns data path is routing
dominated (4.725 ns, 86.8%) and begins in the EX-stage forwarding-select cone.

## RTL changes

- `pipe/ctrl_forward_sel.v` now predecodes the forwarding source for every
  valid IF/ID rs1/rs2 operand.  The priority remains EX/MEM, then MEM/WB,
  then regfile; an ID/EX load remains ineligible for EX/MEM forwarding.
- `pipe/pipe_id_ex.v` captures the resulting selectors as
  `id_ex_rs1_fwd_sel` and `id_ex_rs2_fwd_sel`, reusing the existing ID/EX
  boundary and adding no stage or cycle.
- `pipe/ex_forward.v` no longer performs EX-stage address comparisons or
  producer-valid gating.  It muxes only from the registered selectors while
  preserving the existing load-use detector.
- `KLDJ_top.v` routes the generic selectors to both the generic EX operand
  muxes and the existing branch/JALR dedicated operand paths.
- BPU tables, JALR target calculation, predictor metadata, RAS state, memory
  bridge, clock constraints, and forwarding source priority are unchanged.

## Functional verification

All simulations use a fresh `TimingFix_Log/.fix9_sim_work` work area and
Vivado Simulator 2018.3.

| Test | Result |
| --- | --- |
| `ex_forward_tb` | 15 checks passed: regfile, EX/MEM, MEM/WB, store data, immediate operands, and load-use hazards |
| `ctrl_forward_sel_tb` | 8 checks passed: EX/MEM, MEM/WB, priority, load and x0 cases |
| `KLDJ_top_tb` | 29 passed, 0 failed |
| ID/EX selector equivalence assertion | passed for every non-stalled, single-cycle EX instruction; multi-cycle M operations intentionally retain the launch-time selection while older producers drain |
| `KLDJ_exu_jalr_tb` | 3 checks passed |
| `ex_bpu_ctrl_tb` | 43 checks passed |
| `bpu_tb` | passed (`GHR=1`) |
| `bpu_integration_tb` | passed (`updates=12`, `hits=4`, `GHR=63`) |
| JALR workload | 25,686 cycles; JALR 6136/4090/6144; RET 3068/2045/3072; redirects 2073; register signature `e5327a89`; DRAM signature `14a4c280` |
| `KLDJ_irom_v2_tb` | completed its 20,000-cycle run without RTL/testbench error; its performance outputs remain `Z` because the corresponding counter instance is intentionally not connected in the current `KLDJ_top.v` |

## 175 MHz implementation

`run_fix_timing9_175.tcl` uses the same in-memory, 2023.2-compatible flow and
directives as FixTiming8C: `place_design -directive Explore`, followed by two
`phys_opt_design -directive AggressiveExplore` passes and `route_design
-directive Explore`.  It writes the routed reports to both
`TimingFix_Log/FixTiming9_impl` and `Timing_info/fixtiming9`.

## Routed result

The script completed with Vivado 2023.2 on `xc7k325tffg900-2` at the existing
5.714 ns (175 MHz) clock constraint.

| Metric | FixTiming8C | FixTiming9 |
| --- | ---: | ---: |
| WNS | -0.014 ns | +0.090 ns |
| TNS | -0.014 ns | 0.000 ns |
| Failing setup endpoints | 1 | 0 |
| Hold/PW failing endpoints | 0 / 0 | 0 / 0 |

The former `id_ex_rs1_addr -> IFU PC` failure is absent.  The new worst setup
path is `id_ex_rs2_fwd_sel_reg[1] -> id_ex_rs2_to_data2_reg/CE`, with 5.231 ns
data delay (0.770 ns logic, 4.461 ns route), 9 logic levels, and +0.090 ns
slack.  The closely related DRAM BRAM-output to MEM/WB path is also met at
+0.093 ns.  The routed congestion report has no placer congestion windows
above level 5.

All user timing constraints are met.  The +0.090 ns margin closes FixTiming9,
but it is deliberately not treated as sufficient headroom for RAS.  Keep RAS
out of the next change until a separate margin-improvement round or a
small-RAS implementation has been evaluated against this routed baseline.
