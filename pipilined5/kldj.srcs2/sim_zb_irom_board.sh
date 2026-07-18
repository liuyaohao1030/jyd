#!/usr/bin/env bash
# Simulate a generated Zb board-test COE through the student_top-equivalent
# CPU/peripheral path.  This script intentionally never supplies KLDJ_CFG_*:
# the selected RTL-local configuration in rtl/zb/zb_cfg.vh is what is tested.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SCRIPT_DIR/sources_1/imports/rtl"
TB_FILE="$SCRIPT_DIR/sim_1/imports/sim/KLDJ_zb_irom_board_tb.sv"
GENERATOR="$SCRIPT_DIR/demo/zb_irom/gen_irom_zb_variants.py"

GROUP="${1:-}"
MAX_SECONDS="${2:-60}"

case "$GROUP" in
    zba)  GROUP_ID=1 ;;
    zbb)  GROUP_ID=2 ;;
    zbc)  GROUP_ID=3 ;;
    zbs)  GROUP_ID=4 ;;
    zbkb) GROUP_ID=5 ;;
    zbkx) GROUP_ID=6 ;;
    *)
        echo "Usage: $0 {zba|zbb|zbc|zbs|zbkb|zbkx} [timeout_seconds]" >&2
        echo "The source-local selector in rtl/zb/zb_cfg.vh must enable exactly that group with OP=ALL." >&2
        exit 2
        ;;
esac

python3 "$GENERATOR" --group "$GROUP"

IROM_COE="$SCRIPT_DIR/demo/zb_irom/irom-v2-${GROUP}.coe"
BUILD_DIR="$SCRIPT_DIR/build/zb_irom"
SIM_OUT="$BUILD_DIR/${GROUP}.vvp"
SIM_LOG="$BUILD_DIR/${GROUP}.log"
mkdir -p "$BUILD_DIR"

echo "=== Compile board-path IROM Zb test: $GROUP ==="
iverilog -g2012 \
    -s KLDJ_zb_irom_board_tb \
    -P "KLDJ_zb_irom_board_tb.IMAGE_GROUP=${GROUP_ID}" \
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
    "$SCRIPT_DIR/../new/seg7.sv" \
    "$SCRIPT_DIR/../new/display_seg.sv" \
    "$SCRIPT_DIR/../new/counter.sv" \
    "$SCRIPT_DIR/../new/DRAM_TDP.sv" \
    "$SCRIPT_DIR/../new/dram_driver.sv" \
    "$SCRIPT_DIR/../new/perip_bridge.sv" \
    "$TB_FILE"

echo "=== Simulate board-path IROM Zb test: $GROUP (timeout ${MAX_SECONDS}s) ==="
timeout "$MAX_SECONDS" vvp "$SIM_OUT" "+IROM_COE=$IROM_COE" 2>&1 | tee "$SIM_LOG"

if grep -q "IROM_ZB_BOARD_PASS group=${GROUP_ID}" "$SIM_LOG"; then
    echo "=== Result: PASS ($GROUP) ==="
else
    echo "=== Result: FAIL ($GROUP) ===" >&2
    exit 1
fi
