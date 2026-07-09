#!/bin/bash
##############################################################################
# sim_tdp.sh - Simulation script for True Dual Port BRAM
#
# Usage:
#   ./sim_tdp.sh unit      # Run DRAM_TDP unit test
#   ./sim_tdp.sh full      # Run full-system test with irom-v2
#   ./sim_tdp.sh clean     # Clean simulation files
#
# Prerequisites:
#   - Vivado loaded (xvlog, xelab, xsim in PATH)
#   - Source files in current directory
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Common source files
COMMON_SRCS=(
    "define.v"
    "DRAM_TDP.sv"
    "dram_driver.sv"
    "display_seg.sv"
    "seg7.sv"
    "counter.sv"
    "perip_bridge.sv"
)

# Full-system additional sources
FULL_SRCS=(
    "IROM_BHV.sv"
    "student_top.sv"
    "top.sv"
    "uart.sv"
    "twin_controller.sv"
)

clean() {
    echo "Cleaning simulation files..."
    rm -rf xsim.dir *.pb *.wdb *.vcd *.log xvlog.elab
    echo "Done."
}

compile_unit() {
    echo "=== Compiling DRAM_TDP unit test ==="
    xvlog -sv -work work \
        "DRAM_TDP.sv" \
        "tb_dram_tdp.sv" \
        2>&1 | tee xvlog_unit.log
}

elaborate_unit() {
    echo "=== Elaborating DRAM_TDP unit test ==="
    xelab -debug all -work work \
        tb_dram_tdp -s sim_unit \
        2>&1 | tee xelab_unit.log
}

run_unit() {
    echo "=== Running DRAM_TDP unit test ==="
    xsim sim_unit -runall \
        2>&1 | tee xsim_unit.log
}

compile_full() {
    echo "=== Compiling full-system test ==="
    # Copy hex file to working directory
    if [ -f "../kldj.srcs2/sim_1/imports/sim/irom_v2.hex" ]; then
        cp "../kldj.srcs2/sim_1/imports/sim/irom_v2.hex" .
    fi

    xvlog -sv -work work \
        "${COMMON_SRCS[@]}" \
        "${FULL_SRCS[@]}" \
        "tb_student_top_tdp.sv" \
        "KLDJ_top.v" \
        "KLDJ_perf_counters.v" \
        2>&1 | tee xvlog_full.log
}

elaborate_full() {
    echo "=== Elaborating full-system test ==="
    xelab -debug all -work work \
        tb_student_top_tdp -s sim_full \
        2>&1 | tee xelab_full.log
}

run_full() {
    echo "=== Running full-system test ==="
    xsim sim_full -runall \
        2>&1 | tee xsim_full.log
}

case "$1" in
    unit)
        compile_unit
        elaborate_unit
        run_unit
        ;;
    full)
        compile_full
        elaborate_full
        run_full
        ;;
    clean)
        clean
        ;;
    *)
        echo "Usage: $0 {unit|full|clean}"
        echo ""
        echo "  unit   - Run DRAM_TDP unit test (fast)"
        echo "  full   - Run full-system test with irom-v2"
        echo "  clean  - Clean simulation files"
        exit 1
        ;;
esac
