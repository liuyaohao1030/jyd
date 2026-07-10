#!/bin/bash
# Run simulation from the sim directory
# This script handles the include path issues

set -e

SIM_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="/home/ccy/Documents/jydb/2/jyd2026/jyd/pipilined5/kldj.srcs2/sources_1/imports/rtl"
NEW_DIR="/home/ccy/Documents/jydb/2/jyd2026/jyd/pipilined5/new"

cd "$SIM_DIR"

# Compile
iverilog \
    -I"$RTL_DIR" \
    -g2012 \
    -o sim_out \
    "$RTL_DIR"/KLDJ_top.v \
    "$RTL_DIR"/KLDJ_perf_counters.v \
    "$RTL_DIR"/alu/KLDJ_alu.v \
    "$RTL_DIR"/alu/alu_add.v \
    "$RTL_DIR"/alu/alu_and.v \
    "$RTL_DIR"/alu/alu_div.v \
    "$RTL_DIR"/alu/alu_mul.v \
    "$RTL_DIR"/alu/alu_or.v \
    "$RTL_DIR"/alu/alu_shifter.v \
    "$RTL_DIR"/alu/alu_slt.v \
    "$RTL_DIR"/alu/alu_xor.v \
    "$RTL_DIR"/alu/div_ip_wrapper.v \
    "$RTL_DIR"/alu/mul_ip_wrapper.v \
    "$RTL_DIR"/pipe/ex_forward.v \
    "$RTL_DIR"/pipe/mem_stage_top.v \
    "$RTL_DIR"/pipe/pipe_ex_mem.v \
    "$RTL_DIR"/pipe/pipe_id_ex.v \
    "$RTL_DIR"/pipe/pipe_if_id.v \
    "$RTL_DIR"/pipe/pipe_mem_wb.v \
    "$RTL_DIR"/pipe/pipe_wb_commit.v \
    "$RTL_DIR"/stage/KLDJ_csr.v \
    "$RTL_DIR"/stage/KLDJ_exu.v \
    "$RTL_DIR"/stage/KLDJ_idu.v \
    "$RTL_DIR"/stage/KLDJ_ifu.v \
    "$RTL_DIR"/stage/KLDJ_lsu.v \
    "$RTL_DIR"/stage/KLDJ_regfile.v \
    "$RTL_DIR"/stage/KLDJ_wbu.v \
    "$RTL_DIR"/util/DataMemory.v \
    "$RTL_DIR"/util/MuxKeyInternal.v \
    "$RTL_DIR"/util/MuxKeyWithDefault.v \
    "$NEW_DIR"/student_top.sv \
    "$NEW_DIR"/perip_bridge.sv \
    "$NEW_DIR"/dram_driver.sv \
    "$NEW_DIR"/DRAM_TDP.sv \
    "$NEW_DIR"/IROM_BHV.sv \
    "$NEW_DIR"/display_seg.sv \
    "$NEW_DIR"/seg7.sv \
    "$NEW_DIR"/counter.sv \
    "$SIM_DIR"/tb_full_system.sv

echo "Compilation successful!"

# Run
./sim_out
