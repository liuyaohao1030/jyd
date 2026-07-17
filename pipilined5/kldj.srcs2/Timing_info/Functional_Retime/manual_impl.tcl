# Manual implementation of the isolated functional-retime synthesis result.
# This bypasses the local Vivado run launcher only; it uses the same project,
# generated IP checkpoints, part, and XDC as the board project copy.

set project_xpr {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime/project/functional_retime.xpr}
set project_dir [file dirname $project_xpr]
set synth_dcp   [file join $project_dir functional_retime.runs synth_functional_retime top.dcp]
set ip_root     [file join $project_dir functional_retime.gen sources_1 ip]
set report_dir  {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime/reports}

foreach required [list \
    $project_xpr $synth_dcp \
    [file join $ip_root pll_1 pll.dcp] \
    [file join $ip_root IROM IROM.dcp] \
    [file join $ip_root DRAM_TDP_1 DRAM_TDP.dcp] \
    [file join $ip_root div_gen_u32_1 div_gen_u32.dcp] \
    [file join $ip_root mult_gen_u33_1 mult_gen_u33.dcp]] {
    if {![file exists $required]} { error "Required implementation input is missing: $required" }
}
file mkdir $report_dir

open_project $project_xpr
open_checkpoint $synth_dcp

# Stitch each OOC IP into the exact black-box hierarchy reported by the
# synthesized checkpoint before link_design applies project/IP constraints.
read_checkpoint -cell pll_inst [file join $ip_root pll_1 pll.dcp]
read_checkpoint -cell student_top_inst/Mem_IROM [file join $ip_root IROM IROM.dcp]
read_checkpoint -cell student_top_inst/bridge_inst/dram_driver_inst/u_dram_tdp \
    [file join $ip_root DRAM_TDP_1 DRAM_TDP.dcp]
read_checkpoint -cell student_top_inst/u_KLDJ_top/exu2/u_div_ip_wrapper/u_div_gen_u32 \
    [file join $ip_root div_gen_u32_1 div_gen_u32.dcp]
read_checkpoint -cell student_top_inst/u_KLDJ_top/exu2/u_mul_ip_wrapper/u_mult_gen_u33 \
    [file join $ip_root mult_gen_u33_1 mult_gen_u33.dcp]

if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {
    error "Unresolved black boxes remain after IP checkpoint stitching"
}

# open_checkpoint plus read_checkpoint -cell already yields a fully assembled
# design.  Read the board and PLL constraints explicitly rather than invoking
# project link_design (which expects HDL sources instead of this checkpoint).
read_xdc -no_add -cells pll_inst/inst [file join $ip_root pll_1 pll_board.xdc]
read_xdc -no_add -cells pll_inst/inst [file join $ip_root pll_1 pll.xdc]
read_xdc -no_add [file join $project_dir functional_retime.srcs constrs_1 new digital_twin.xdc]
report_clocks -file [file join $report_dir clocks_pre_impl.rpt]

opt_design
write_checkpoint -force [file join $report_dir post_opt.dcp]

place_design -directive ExtraNetDelay_high
phys_opt_design
write_checkpoint -force [file join $report_dir post_place_physopt.dcp]

route_design -directive AggressiveExplore
phys_opt_design
write_checkpoint -force [file join $report_dir post_route_physopt.dcp]

report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 100 -input_pins -file [file join $report_dir timing_summary_max.rpt]
report_timing_summary -delay_type min -report_unconstrained -check_timing_verbose \
    -max_paths 100 -input_pins -file [file join $report_dir timing_summary_min.rpt]
report_timing -delay_type max -sort_by slack -max_paths 100 -nworst 10 -input_pins -nets \
    -file [file join $report_dir setup_paths.rpt]
report_timing -delay_type min -sort_by slack -max_paths 100 -nworst 10 -input_pins -nets \
    -file [file join $report_dir hold_paths.rpt]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $report_dir high_fanout.rpt]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_route_status -file [file join $report_dir route_status.rpt]

set load_regs [get_cells -hier -quiet *mem_load_rdata_reg*]
puts "MEM_LOAD_RDATA_FF_COUNT=[llength $load_regs]"
if {[llength $load_regs] != 0} {
    redirect -file [file join $report_dir mem_load_rdata_cells.rpt] {
        report_property -all $load_regs
    }
    set load_d_pins [get_pins -quiet -of_objects $load_regs -filter {REF_PIN_NAME == D}]
    set load_q_pins [get_pins -quiet -of_objects $load_regs -filter {REF_PIN_NAME == Q}]
    report_timing -delay_type max -to $load_d_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bridge_response_capture_paths.rpt]
    report_timing -delay_type max -from $load_q_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bridge_response_consumer_paths.rpt]
}

set bram_addr_q_pins [get_pins -hier -quiet *bram_addr_r_reg*/Q]
if {[llength $bram_addr_q_pins] != 0} {
    report_timing -delay_type max -from $bram_addr_q_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bram_address_fanout_paths.rpt]
}

set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold  [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [get_property SLACK $worst_setup]
set whs [get_property SLACK $worst_hold]
puts "FUNCTIONAL_RETIME_WNS=$wns"
puts "FUNCTIONAL_RETIME_WHS=$whs"
puts "FUNCTIONAL_RETIME_REPORT_DIR=$report_dir"

close_project
if {$wns < 0 || $whs < 0} { exit 2 }
exit
