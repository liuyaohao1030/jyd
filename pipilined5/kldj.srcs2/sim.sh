#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SCRIPT_DIR/sources_1/imports/rtl"
TB_DIR="$SCRIPT_DIR/sim_1/imports/sim"
BUILD_DIR="$SCRIPT_DIR/build"
SIM_OUT="$BUILD_DIR/sim.vvp"

TOP="${TOP:-rv32i_supported_instr_tb}"
MAX_CYCLES="${1:-60}"

mkdir -p "$BUILD_DIR"

echo "=== Compile ==="
iverilog -g2012 \
    -I "$RTL_DIR" \
    -s "$TOP" \
    -o "$SIM_OUT" \
    "$RTL_DIR"/*.v \
    "$RTL_DIR"/alu/*.v \
    "$RTL_DIR"/pipe/*.v \
    "$RTL_DIR"/stage/*.v \
    "$RTL_DIR"/util/*.v \
    "$TB_DIR"/*.sv

echo "=== Simulate (timeout ${MAX_CYCLES}s) ==="
timeout "$MAX_CYCLES" vvp "$SIM_OUT" 2>&1 | tee "$BUILD_DIR/sim.log"

echo ""
echo "=== Result ==="
if grep -q "SUMMARY.*passed" "$BUILD_DIR/sim.log"; then
    echo "PASS"
    exit 0
elif grep -q "FAIL\|fatal\|timeout" "$BUILD_DIR/sim.log"; then
    echo "FAIL"
    exit 1
else
    echo "UNKNOWN"
    exit 2
fi
