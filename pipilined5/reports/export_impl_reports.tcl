# ============================================================
# Export Vivado implementation reports
# Usage:
#   1. Run implementation first.
#   2. In Vivado Tcl Console:
#        source D:/System/desktop/jyd-feature/pipilined5/reports/export_impl_reports.tcl
# ============================================================

# ----------------------------
# User config
# ----------------------------
set BASE_REPORT_DIR "D:/System/desktop/jyd-feature/pipilined5/reports"

# 每次修改这里，方便区分实验
# 例如：
#   p1_2a_ex_side_is_dram_150mhz
#   baseline_150mhz
#   jal_id_redirect_160mhz
set RUN_TAG "baseline_150mhz"

# 如果你主要关注某个 clock，可以填 clock 名字
# 不确定 clock 名字时，先留空，脚本会导出全局 timing
set TARGET_CLOCK "cpu_clk_out2"

# ----------------------------
# Create timestamped directory
# ----------------------------
set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set REPORT_DIR "${BASE_REPORT_DIR}/${timestamp}_${RUN_TAG}"

file mkdir $REPORT_DIR

puts "============================================================"
puts "Exporting implementation reports to:"
puts "  $REPORT_DIR"
puts "============================================================"

# ----------------------------
# Open implemented design if needed
# ----------------------------
if {[catch {current_design} cur_design] || $cur_design eq ""} {
    puts "No current design opened. Trying to open impl_1..."
    open_run impl_1
} else {
    puts "Current design: $cur_design"
}

# ----------------------------
# Basic run info
# ----------------------------
set info_file "${REPORT_DIR}/run_info.txt"
set fp [open $info_file "w"]

puts $fp "Report directory: $REPORT_DIR"
puts $fp "Timestamp       : $timestamp"
puts $fp "Run tag         : $RUN_TAG"
puts $fp "Vivado version  : [version]"
puts $fp ""
puts $fp "Current project : [current_project]"
puts $fp "Current design  : [current_design]"
puts $fp ""

catch {
    puts $fp "Current run     : [current_run]"
}
catch {
    puts $fp "Impl run status : [get_property STATUS [get_runs impl_1]]"
}
catch {
    puts $fp "Impl run WNS    : [get_property STATS.WNS [get_runs impl_1]]"
    puts $fp "Impl run TNS    : [get_property STATS.TNS [get_runs impl_1]]"
}
close $fp

# ----------------------------
# Timing summary
# ----------------------------
report_timing_summary \
    -delay_type max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -input_pins \
    -file "${REPORT_DIR}/timing_summary_max.rpt"

report_timing_summary \
    -delay_type min \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -input_pins \
    -file "${REPORT_DIR}/timing_summary_min.rpt"

# ----------------------------
# Full timing paths
# ----------------------------
report_timing \
    -delay_type max \
    -sort_by group \
    -max_paths 50 \
    -nworst 10 \
    -input_pins \
    -nets \
    -file "${REPORT_DIR}/timing_full_max.rpt"

report_timing \
    -delay_type min \
    -sort_by group \
    -max_paths 50 \
    -nworst 10 \
    -input_pins \
    -nets \
    -file "${REPORT_DIR}/timing_full_min.rpt"

# ----------------------------
# Clock-specific timing, optional
# ----------------------------
if {$TARGET_CLOCK ne ""} {
    set clk_obj [get_clocks -quiet $TARGET_CLOCK]
    if {[llength $clk_obj] > 0} {
        report_timing \
            -from [get_clocks $TARGET_CLOCK] \
            -to   [get_clocks $TARGET_CLOCK] \
            -delay_type max \
            -max_paths 50 \
            -nworst 10 \
            -input_pins \
            -nets \
            -file "${REPORT_DIR}/timing_${TARGET_CLOCK}_full_max.rpt"

        report_timing \
            -from [get_clocks $TARGET_CLOCK] \
            -to   [get_clocks $TARGET_CLOCK] \
            -delay_type min \
            -max_paths 50 \
            -nworst 10 \
            -input_pins \
            -nets \
            -file "${REPORT_DIR}/timing_${TARGET_CLOCK}_full_min.rpt"
    } else {
        puts "WARNING: TARGET_CLOCK '$TARGET_CLOCK' not found. Skip clock-specific timing."
    }
}

# ----------------------------
# Clock reports
# ----------------------------
report_clocks \
    -file "${REPORT_DIR}/clocks.rpt"

report_clock_interaction \
    -delay_type max \
    -file "${REPORT_DIR}/clock_interaction.rpt"

report_clock_utilization \
    -file "${REPORT_DIR}/clock_utilization.rpt"

# ----------------------------
# Utilization
# ----------------------------
report_utilization \
    -hierarchical \
    -file "${REPORT_DIR}/utilization_hier.rpt"

report_utilization \
    -file "${REPORT_DIR}/utilization_flat.rpt"

# ----------------------------
# High fanout / methodology / route
# ----------------------------
report_high_fanout_nets \
    -timing \
    -load_types \
    -max_nets 100 \
    -file "${REPORT_DIR}/high_fanout.rpt"

report_methodology \
    -file "${REPORT_DIR}/methodology.rpt"

report_route_status \
    -file "${REPORT_DIR}/route_status.rpt"

# ----------------------------
# DRC
# ----------------------------
report_drc \
    -file "${REPORT_DIR}/drc.rpt"

# ----------------------------
# Export checkpoints, optional but useful
# ----------------------------
write_checkpoint -force "${REPORT_DIR}/post_impl.dcp"

puts "============================================================"
puts "Reports exported successfully."
puts "Directory:"
puts "  $REPORT_DIR"
puts "============================================================"