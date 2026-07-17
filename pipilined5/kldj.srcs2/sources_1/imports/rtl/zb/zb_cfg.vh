// Compile-time configuration for the optional RV32 Zb plug-in.
//
// The recommended on-site configuration is the RTL-local selector below:
// edit this file only; do not set Vivado's verilog_define property.  With
// KLDJ_RTL_EXT_ENABLE commented, the IDU/EXU integration is preprocessed out
// and the base core is unchanged.
//
// The KLDJ_CFG_* command-line defines remain supported only for the local
// per-group regression scripts.  They are deliberately kept separate from
// the source-only flow so no Vivado-console setting is required on site.

`ifndef KLDJ_ZB_CFG_VH
`define KLDJ_ZB_CFG_VH

// Group IDs.
`define KLDJ_ZB_GROUP_NONE 3'd0
`define KLDJ_ZB_GROUP_ZBA  3'd1
`define KLDJ_ZB_GROUP_ZBB  3'd2
`define KLDJ_ZB_GROUP_ZBC  3'd3
`define KLDJ_ZB_GROUP_ZBS  3'd4
`define KLDJ_ZB_GROUP_ZBKB 3'd5
`define KLDJ_ZB_GROUP_ZBKX 3'd6

// A tagged EXU micro-op uses exu_op[17], leaving all existing micro-op values
// (currently below 18'h40) untouched.
`define KLDJ_EXU_ZB_TAG 18'h20000

// Operand-2 selection produced by the extension decoder.
`define KLDJ_ZB_OP2_RS2  2'd0
`define KLDJ_ZB_OP2_IMM5 2'd1
`define KLDJ_ZB_OP2_ZERO 2'd2

// Uop IDs.  They are unique across all groups so one optional numeric
// KLDJ_CFG_OP selector is sufficient.
`define KLDJ_ZB_OP_ALL          8'hff

`define KLDJ_ZB_OP_SH1ADD       8'h01
`define KLDJ_ZB_OP_SH2ADD       8'h02
`define KLDJ_ZB_OP_SH3ADD       8'h03

`define KLDJ_ZB_OP_ANDN         8'h10
`define KLDJ_ZB_OP_ORN          8'h11
`define KLDJ_ZB_OP_XNOR         8'h12
`define KLDJ_ZB_OP_CLZ          8'h13
`define KLDJ_ZB_OP_CTZ          8'h14
`define KLDJ_ZB_OP_CPOP         8'h15
`define KLDJ_ZB_OP_MAX          8'h16
`define KLDJ_ZB_OP_MAXU         8'h17
`define KLDJ_ZB_OP_MIN          8'h18
`define KLDJ_ZB_OP_MINU         8'h19
`define KLDJ_ZB_OP_SEXT_B       8'h1a
`define KLDJ_ZB_OP_SEXT_H       8'h1b
`define KLDJ_ZB_OP_ZEXT_H       8'h1c
`define KLDJ_ZB_OP_ROL          8'h1d
`define KLDJ_ZB_OP_ROR          8'h1e
`define KLDJ_ZB_OP_RORI         8'h1f
`define KLDJ_ZB_OP_ORC_B        8'h20
`define KLDJ_ZB_OP_REV8         8'h21

`define KLDJ_ZB_OP_CLMUL        8'h30
`define KLDJ_ZB_OP_CLMULH       8'h31
`define KLDJ_ZB_OP_CLMULR       8'h32

`define KLDJ_ZB_OP_BSET         8'h40
`define KLDJ_ZB_OP_BCLR         8'h41
`define KLDJ_ZB_OP_BINV         8'h42
`define KLDJ_ZB_OP_BEXT         8'h43
`define KLDJ_ZB_OP_BSETI        8'h44
`define KLDJ_ZB_OP_BCLRI        8'h45
`define KLDJ_ZB_OP_BINVI        8'h46
`define KLDJ_ZB_OP_BEXTI        8'h47

`define KLDJ_ZB_OP_BREV8        8'h50
`define KLDJ_ZB_OP_PACK         8'h51
`define KLDJ_ZB_OP_PACKH        8'h52
`define KLDJ_ZB_OP_ZIP          8'h53
`define KLDJ_ZB_OP_UNZIP        8'h54

`define KLDJ_ZB_OP_XPERM4       8'h60
`define KLDJ_ZB_OP_XPERM8       8'h61

// ============================================================================
// RTL-local selector -- this is the only block that needs editing on site.
// Do not add KLDJ_CFG_* in Vivado "Verilog Defines".  After changing this
// block, rerun synthesis/implementation so the preprocessor sees the new
// selection.
//
// Example: enable only Zbs bext in the RTL source itself:
//   `define KLDJ_RTL_EXT_ENABLE
//   `define KLDJ_RTL_EXT_GROUP `KLDJ_ZB_GROUP_ZBS
//   `define KLDJ_RTL_EXT_OP    `KLDJ_ZB_OP_BEXT
//
// Keep ENABLE commented for the base core.  GROUP=NONE and OP=ALL are safe
// defaults; they have no effect until ENABLE is uncommented.
// ============================================================================
// `define KLDJ_RTL_EXT_ENABLE    HERE
`define KLDJ_RTL_EXT_GROUP `KLDJ_ZB_GROUP_NONE
`define KLDJ_RTL_EXT_OP    `KLDJ_ZB_OP_ALL

// Convert command-line group defines into constants that RTL can consume.
`ifdef KLDJ_CFG_ZBA
  `define KLDJ_ZB_CFG_ZBA_ON 1
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_ZBA
  `define KLDJ_EXT_ENABLE
`else
  `define KLDJ_ZB_CFG_ZBA_ON 0
`endif

`ifdef KLDJ_CFG_ZBB
  `define KLDJ_ZB_CFG_ZBB_ON 1
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_ZBB
  `define KLDJ_EXT_ENABLE
`else
  `define KLDJ_ZB_CFG_ZBB_ON 0
`endif

`ifdef KLDJ_CFG_ZBC
  `define KLDJ_ZB_CFG_ZBC_ON 1
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_ZBC
  `define KLDJ_EXT_ENABLE
`else
  `define KLDJ_ZB_CFG_ZBC_ON 0
`endif

`ifdef KLDJ_CFG_ZBS
  `define KLDJ_ZB_CFG_ZBS_ON 1
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_ZBS
  `define KLDJ_EXT_ENABLE
`else
  `define KLDJ_ZB_CFG_ZBS_ON 0
`endif

`ifdef KLDJ_CFG_ZBKB
  `define KLDJ_ZB_CFG_ZBKB_ON 1
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_ZBKB
  `define KLDJ_EXT_ENABLE
`else
  `define KLDJ_ZB_CFG_ZBKB_ON 0
`endif

`ifdef KLDJ_CFG_ZBKX
  `define KLDJ_ZB_CFG_ZBKX_ON 1
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_ZBKX
  `define KLDJ_EXT_ENABLE
`else
  `define KLDJ_ZB_CFG_ZBKX_ON 0
`endif

// A source-only selection maps directly to the same internal constants as a
// command-line define.  If both forms are accidentally enabled, the decoder's
// simulation-time configuration-count check fails rather than choosing one
// silently.
`ifdef KLDJ_RTL_EXT_ENABLE
  `define KLDJ_ZB_CFG_RTL_ON 1
  `define KLDJ_EXT_ENABLE
  `ifndef KLDJ_ZB_GROUP_SEL
    `define KLDJ_ZB_GROUP_SEL `KLDJ_RTL_EXT_GROUP
  `endif
  `ifndef KLDJ_CFG_OP
    `define KLDJ_CFG_OP `KLDJ_RTL_EXT_OP
  `endif
`else
  `define KLDJ_ZB_CFG_RTL_ON 0
`endif

`ifndef KLDJ_ZB_GROUP_SEL
  `define KLDJ_ZB_GROUP_SEL `KLDJ_ZB_GROUP_NONE
`endif

`ifndef KLDJ_CFG_OP
  `define KLDJ_CFG_OP `KLDJ_ZB_OP_ALL
`endif

`define KLDJ_ZB_CONFIG_COUNT \
    (`KLDJ_ZB_CFG_ZBA_ON + `KLDJ_ZB_CFG_ZBB_ON + `KLDJ_ZB_CFG_ZBC_ON + \
     `KLDJ_ZB_CFG_ZBS_ON + `KLDJ_ZB_CFG_ZBKB_ON + `KLDJ_ZB_CFG_ZBKX_ON + \
     `KLDJ_ZB_CFG_RTL_ON)

`endif
