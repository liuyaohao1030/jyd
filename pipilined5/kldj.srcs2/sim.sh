#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SCRIPT_DIR/sources_1/imports/rtl"
TB_DIR="$SCRIPT_DIR/sim_1/imports/sim"
BUILD_DIR="$SCRIPT_DIR/build"

TEST="${1:-rv32i}"
MAX_SECONDS="${2:-60}"
EXTRA_FILES=()
IVERILOG_DEFINES=()

case "$TEST" in
    rv32i|i|KLDJ_top_tb)
        TEST="rv32i"
        TOP="KLDJ_top_tb"
        TB_FILE="$TB_DIR/KLDJ_top_tb.sv"
        PASS_PATTERN="ALL TESTS PASSED"
        ;;
    rv32m|m|rv32m_supported_instr_tb)
        TEST="rv32m"
        TOP="rv32m_supported_instr_tb"
        TB_FILE="$TB_DIR/rv32m_supported_instr_tb.sv"
        PASS_PATTERN="rv32m supported pipeline test passed"
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
    load-dep-mem2|load_dep_mem2)
        TEST="load-dep-mem2"
        TOP="KLDJ_load_dep_tb"
        TB_FILE="$TB_DIR/KLDJ_load_dep_tb.sv"
        IVERILOG_DEFINES=(-DSIX_MEM2_LOAD_FWD)
        PASS_PATTERN="LOAD_DEP_REGRESSION_PASS"
        ;;
    control-dep|control_dep|KLDJ_control_dep_tb)
        TEST="control-dep"
        TOP="KLDJ_control_dep_tb"
        TB_FILE="$TB_DIR/KLDJ_control_dep_tb.sv"
        PASS_PATTERN="CONTROL_DEP_INTERLOCK_PASS"
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
    -h|--help|help)
        echo "Usage: $0 [rv32i|rv32m|irom-v2|load-dep|load-dep-mem2|control-dep|bpu|bpu-integration|ex-bpu-ctrl|ras|ras-integration|dram-driver] [timeout_seconds]"
        echo "Examples:"
        echo "  $0 rv32i"
        echo "  $0 rv32m 120"
        exit 0
        ;;
    *)
        echo "Unknown test: $TEST"
        echo "Usage: $0 [rv32i|rv32m|irom-v2|load-dep|load-dep-mem2|control-dep|bpu|bpu-integration|ex-bpu-ctrl|ras|ras-integration|dram-driver] [timeout_seconds]"
        exit 2
        ;;
esac

SIM_OUT="$BUILD_DIR/${TEST}.vvp"
SIM_LOG="$BUILD_DIR/${TEST}.log"

mkdir -p "$BUILD_DIR"

echo "=== Compile ${TEST} (${TOP}) ==="
iverilog -g2012 \
    "${IVERILOG_DEFINES[@]}" \
    -s "$TOP" \
    -I "$RTL_DIR" \
    -I "$RTL_DIR/alu" \
    -I "$RTL_DIR/pipe" \
    -I "$RTL_DIR/stage" \
    -I "$RTL_DIR/util" \
    -o "$SIM_OUT" \
    "$RTL_DIR"/*.v \
    "$RTL_DIR"/alu/*.v \
    "$RTL_DIR"/pipe/*.v \
    "$RTL_DIR"/stage/*.v \
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
