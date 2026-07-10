# Makefile for full system simulation with iverilog
#
# Usage:
#   make compile  - compile all sources
#   make sim      - run simulation
#   make wave     - open wave viewer (if available)
#   make clean    - clean generated files

# Directories
RTL_DIR   = /home/ccy/Documents/jydb/2/jyd2026/jyd/pipilined5/kldj.srcs2/sources_1/imports/rtl
NEW_DIR   = /home/ccy/Documents/jydb/2/jyd2026/jyd/pipilined5/new
SIM_DIR   = .

# Include paths (for `include directives in RTL files)
INCFLAGS  = -I$(RTL_DIR) -I$(RTL_DIR)/alu -I$(RTL_DIR)/pipe -I$(RTL_DIR)/stage -I$(RTL_DIR)/util

# Source files - CPU core
CPU_SRCS = \
    $(RTL_DIR)/KLDJ_top.v \
    $(RTL_DIR)/KLDJ_perf_counters.v \
    $(RTL_DIR)/alu/KLDJ_alu.v \
    $(RTL_DIR)/alu/alu_add.v \
    $(RTL_DIR)/alu/alu_and.v \
    $(RTL_DIR)/alu/alu_div.v \
    $(RTL_DIR)/alu/alu_mul.v \
    $(RTL_DIR)/alu/alu_or.v \
    $(RTL_DIR)/alu/alu_shifter.v \
    $(RTL_DIR)/alu/alu_slt.v \
    $(RTL_DIR)/alu/alu_xor.v \
    $(RTL_DIR)/alu/div_ip_wrapper.v \
    $(RTL_DIR)/alu/mul_ip_wrapper.v \
    $(RTL_DIR)/pipe/ex_forward.v \
    $(RTL_DIR)/pipe/mem_stage_top.v \
    $(RTL_DIR)/pipe/pipe_ex_mem.v \
    $(RTL_DIR)/pipe/pipe_id_ex.v \
    $(RTL_DIR)/pipe/pipe_if_id.v \
    $(RTL_DIR)/pipe/pipe_mem_wb.v \
    $(RTL_DIR)/pipe/pipe_wb_commit.v \
    $(RTL_DIR)/stage/KLDJ_csr.v \
    $(RTL_DIR)/stage/KLDJ_exu.v \
    $(RTL_DIR)/stage/KLDJ_idu.v \
    $(RTL_DIR)/stage/KLDJ_ifu.v \
    $(RTL_DIR)/stage/KLDJ_lsu.v \
    $(RTL_DIR)/stage/KLDJ_regfile.v \
    $(RTL_DIR)/stage/KLDJ_wbu.v \
    $(RTL_DIR)/util/DataMemory.v \
    $(RTL_DIR)/util/MuxKeyInternal.v \
    $(RTL_DIR)/util/MuxKeyWithDefault.v

# Source files - System (new directory)
SYS_SRCS = \
    $(NEW_DIR)/student_top.sv \
    $(NEW_DIR)/perip_bridge.sv \
    $(NEW_DIR)/dram_driver.sv \
    $(NEW_DIR)/DRAM_TDP.sv \
    $(NEW_DIR)/IROM_BHV.sv \
    $(NEW_DIR)/display_seg.sv \
    $(NEW_DIR)/seg7.sv \
    $(NEW_DIR)/counter.sv

# Testbench
TB_SRCS = $(SIM_DIR)/tb_full_system.sv

# All sources
ALL_SRCS = $(CPU_SRCS) $(SYS_SRCS) $(TB_SRCS)

# Output
OUT = sim_out
VCD = tb_full_system.vcd

.PHONY: all compile sim wave clean

all: sim

compile: $(OUT)

$(OUT): $(ALL_SRCS)
	iverilog $(INCFLAGS) -g2012 -o $(OUT) $(ALL_SRCS)

sim: $(OUT)
	./$(OUT)

wave: $(VCD)
	gtkwave $(VCD) &

clean:
	rm -f $(OUT) $(VCD) *.vvp
