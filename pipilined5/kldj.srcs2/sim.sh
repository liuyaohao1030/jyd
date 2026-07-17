#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SCRIPT_DIR/sources_1/imports/rtl"
TB_DIR="$SCRIPT_DIR/sim_1/imports/sim"
BUILD_DIR="$SCRIPT_DIR/build"

TEST="${1:-rv32i}"
MAX_SECONDS="${2:-60}"
EXTRA_FILES=()
DEFINES=()
RTL_LOCAL_CONFIG=0

case "$TEST" in
    rv32i|i|KLDJ_top_tb)
        TEST="rv32i"
        TOP="KLDJ_top_tb"
        TB_FILE="$TB_DIR/KLDJ_top_tb.sv"
        PASS_PATTERN="ALL TESTS PASSED"
        ;;
    rv32m|m|m-ext|m_ext|m_ext_ip_wrapper_tb)
        TEST="rv32m"
        TOP="m_ext_ip_wrapper_tb"
        TB_FILE="$TB_DIR/m_ext_ip_wrapper_tb.sv"
        PASS_PATTERN="m_ext_ip_wrapper_tb passed"
        ;;
    irom-v2|iromv2|perf)
        TEST="irom-v2"
        TOP="KLDJ_irom_v2_tb"
        TB_FILE="$TB_DIR/KLDJ_irom_v2_tb.sv"
        PASS_PATTERN="Done."
        ;;
    load-dep|load_dep|KLDJ_load_dep_tb)
        TEST="load-dep"
        TOP="KLDJ_load_dep_tb"
        TB_FILE="$TB_DIR/KLDJ_load_dep_tb.sv"
        PASS_PATTERN="LOAD_DEP_REGRESSION_PASS"
        ;;
    ex2-ctrl|ex2_ctrl|KLDJ_ex2_ctrl_tb)
        TEST="ex2-ctrl"
        TOP="KLDJ_ex2_ctrl_tb"
        TB_FILE="$TB_DIR/KLDJ_ex2_ctrl_tb.sv"
        PASS_PATTERN="EX2_CTRL_PIPELINE_PASS"
        ;;
    bpu|bpu_tb)
        TEST="bpu"
        TOP="bpu_tb"
        TB_FILE="$TB_DIR/bpu_tb.sv"
        PASS_PATTERN="BPU UNIT TEST PASSED"
        ;;
    bpu-integration|bpu_integration|bpu_integration_tb)
        TEST="bpu-integration"
        TOP="bpu_integration_tb"
        TB_FILE="$TB_DIR/bpu_integration_tb.sv"
        PASS_PATTERN="BPU INTEGRATION TEST PASSED"
        ;;
    ex-bpu-ctrl|ex_bpu_ctrl|ex_bpu_ctrl_tb)
        TEST="ex-bpu-ctrl"
        TOP="ex_bpu_ctrl_tb"
        TB_FILE="$TB_DIR/ex_bpu_ctrl_tb.sv"
        PASS_PATTERN="PASS: ex_bpu_ctrl_tb"
        ;;
    ras|ras_tb)
        TEST="ras"
        TOP="ras_tb"
        TB_FILE="$TB_DIR/ras_tb.sv"
        PASS_PATTERN="RAS UNIT TEST PASSED"
        ;;
    ras-integration|ras_integration|ras_integration_tb)
        TEST="ras-integration"
        TOP="ras_integration_tb"
        TB_FILE="$TB_DIR/ras_integration_tb.sv"
        PASS_PATTERN="RAS INTEGRATION TEST PASSED"
        ;;
    dram|dram-driver|dram_driver_tb)
        TEST="dram-driver"
        TOP="dram_driver_tb"
        TB_FILE="$TB_DIR/dram_driver_tb.sv"
        EXTRA_FILES=(
            "$SCRIPT_DIR/../new/DRAM_TDP.sv"
            "$SCRIPT_DIR/../new/dram_driver.sv"
        )
        PASS_PATTERN="DRAM DRIVER TEST PASSED"
        ;;
    zba)
        TEST="zba"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_ZBA_PASS"
        DEFINES=(-DKLDJ_CFG_ZBA)
        ;;
    zbb)
        TEST="zbb"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_ZBB_PASS"
        DEFINES=(-DKLDJ_CFG_ZBB)
        ;;
    zbc)
        TEST="zbc"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_ZBC_PASS"
        DEFINES=(-DKLDJ_CFG_ZBC)
        ;;
    zbs)
        TEST="zbs"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_ZBS_PASS"
        DEFINES=(-DKLDJ_CFG_ZBS)
        ;;
    zbkb)
        TEST="zbkb"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_ZBKB_PASS"
        DEFINES=(-DKLDJ_CFG_ZBKB)
        ;;
    zbkx)
        TEST="zbkx"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_ZBKX_PASS"
        DEFINES=(-DKLDJ_CFG_ZBKX)
        ;;
    rtl-zb|rtl_zb|zb-rtl)
        TEST="rtl-zb"
        TOP="KLDJ_zb_tb"
        TB_FILE="$TB_DIR/KLDJ_zb_tb.sv"
        PASS_PATTERN="ZB_RTL_PASS"
        RTL_LOCAL_CONFIG=1
        ;;
    zb-all|zball)
        for group in zba zbb zbc zbs zbkb zbkx; do
            "$SCRIPT_DIR/sim.sh" "$group" "$MAX_SECONDS"
        done
        exit 0
        ;;
    -h|--help|help)
        echo "Usage: $0 [rv32i|rv32m|irom-v2|load-dep|ex2-ctrl|bpu|bpu-integration|ex-bpu-ctrl|ras|ras-integration|dram-driver|zba|zbb|zbc|zbs|zbkb|zbkx|rtl-zb|zb-all] [timeout_seconds]"
        echo "Examples:"
        echo "  $0 rv32i"
        echo "  $0 rv32m 120"
        echo "  $0 rtl-zb 60  # read the source-only selector in rtl/zb/zb_cfg.vh"
        exit 0
        ;;
    *)
        echo "Unknown test: $TEST"
        echo "Usage: $0 [rv32i|rv32m|irom-v2|load-dep|ex2-ctrl|bpu|bpu-integration|ex-bpu-ctrl|ras|ras-integration|dram-driver|zba|zbb|zbc|zbs|zbkb|zbkx|rtl-zb|zb-all] [timeout_seconds]"
        exit 2
        ;;
esac

# Optional one-instruction build.  Example:
#   ZB_OP="8'h43" bash ./sim.sh zbs
# The Zb testbench automatically emits only the chosen instruction vector.
if [[ -n "${ZB_OP:-}" ]]; then
    if [[ "$RTL_LOCAL_CONFIG" == "1" ]]; then
        echo "rtl-zb reads KLDJ_RTL_EXT_OP from rtl/zb/zb_cfg.vh; do not set ZB_OP."
        exit 2
    fi
    DEFINES+=("-DKLDJ_CFG_OP=${ZB_OP}")
fi

SIM_OUT="$BUILD_DIR/${TEST}.vvp"
SIM_LOG="$BUILD_DIR/${TEST}.log"

mkdir -p "$BUILD_DIR"

echo "=== Compile ${TEST} (${TOP}) ==="
iverilog -g2012 \
    -s "$TOP" \
    "${DEFINES[@]}" \
    -I "$RTL_DIR" \
    -I "$RTL_DIR/alu" \
    -I "$RTL_DIR/pipe" \
    -I "$RTL_DIR/stage" \
    -I "$RTL_DIR/zb" \
    -I "$RTL_DIR/util" \
    -o "$SIM_OUT" \
    "$RTL_DIR"/*.v \
    "$RTL_DIR"/alu/*.v \
    "$RTL_DIR"/pipe/*.v \
    "$RTL_DIR"/stage/*.v \
    "$RTL_DIR"/zb/*.v \
    "$RTL_DIR"/util/*.v \
    "${EXTRA_FILES[@]}" \
    "$TB_FILE"

echo "=== Simulate ${TEST} (timeout ${MAX_SECONDS}s) ==="
(
    cd "$TB_DIR"
    timeout "$MAX_SECONDS" vvp "$SIM_OUT"
) 2>&1 | tee "$SIM_LOG"

echo ""
echo "=== Result ==="
if grep -q "$PASS_PATTERN" "$SIM_LOG"; then
    echo "PASS"
    exit 0
elif grep -Eiq "SOME TESTS FAILED|fatal|timeout|failed" "$SIM_LOG"; then
    echo "FAIL"
    exit 1
else
    echo "UNKNOWN"
    exit 2
fi
