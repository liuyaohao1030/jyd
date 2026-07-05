#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SCRIPT_DIR/sources_1/imports/rtl"
TB_DIR="$SCRIPT_DIR/sim_1/imports/sim"
BUILD_DIR="$SCRIPT_DIR/build"

TEST="${1:-rv32i}"
MAX_SECONDS="${2:-60}"

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
    -h|--help|help)
        echo "Usage: $0 [rv32i|rv32m] [timeout_seconds]"
        echo "Examples:"
        echo "  $0 rv32i"
        echo "  $0 rv32m 120"
        exit 0
        ;;
    *)
        echo "Unknown test: $TEST"
        echo "Usage: $0 [rv32i|rv32m] [timeout_seconds]"
        exit 2
        ;;
esac

SIM_OUT="$BUILD_DIR/${TEST}.vvp"
SIM_LOG="$BUILD_DIR/${TEST}.log"

mkdir -p "$BUILD_DIR"

echo "=== Compile ${TEST} (${TOP}) ==="
iverilog -g2012 \
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
    "$TB_FILE"

echo "=== Simulate ${TEST} (timeout ${MAX_SECONDS}s) ==="
timeout "$MAX_SECONDS" vvp "$SIM_OUT" 2>&1 | tee "$SIM_LOG"

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
