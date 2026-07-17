# Fresh, isolated implementation for the registered DRAM response fix.
#
# This script deliberately operates on the project copy under this directory;
# it never resets, changes, or writes the user's open board project/runs.
# It uses the same xc7k325tffg900-2 part, XDC, generated IP, and the current
# workspace RTL files referenced by the copied project.

set project_xpr {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime/project/functional_retime.xpr}
set report_dir  {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime/reports}
set dram_coe    {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/demo/dram.coe}
set irom_coe    {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/demo/irom-v2.coe}
set synth_run   synth_functional_retime
set impl_run    impl_functional_retime

foreach required [list $project_xpr $dram_coe $irom_coe] {
    if {![file exists $required]} {
        error "Required file is missing: $required"
    }
}
file mkdir $report_dir

open_project $project_xpr

# The copied project inherited a few stale, unused COE entries from the
# original project history.  Remove only entries whose file no longer exists;
# the two IPs below are then explicitly pointed at the demo images in this
# workspace.
foreach file_obj [get_files -quiet] {
    set file_name [get_property NAME $file_obj]
    if {![file exists $file_name]} {
        puts "Removing stale project file entry: $file_name"
        remove_files -quiet $file_obj
    }
}

set_property CONFIG.Coe_File $dram_coe [get_ips DRAM_TDP]
set_property CONFIG.coefficient_file $irom_coe [get_ips IROM]
generate_target all [get_ips DRAM_TDP]
generate_target all [get_ips IROM]

foreach ip [list DRAM_TDP IROM pll mult_gen_u33 div_gen_u32] {
    if {[get_property IS_LOCKED [get_ips $ip]]} {
        error "IP $ip is locked in the isolated project"
    }
}

# Complete the two OOC memory-IP checkpoints before starting top-level
# synthesis.  A copied project can have generated IP RTL but no IROM/DRAM
# checkpoint yet; the top run then fails before implementation.  PLL and M/D
# generator checkpoints are supplied through the copied IP cache.
set required_ip_runs [list IROM_synth_1 DRAM_TDP_synth_1]
set missing_ip_runs {}
foreach ip_run $required_ip_runs {
    if {[llength [get_runs -quiet $ip_run]] != 1} {
        error "Expected OOC IP run $ip_run is absent"
    }
}
if {![file exists [file join [file dirname $project_xpr] functional_retime.gen sources_1 ip IROM IROM.dcp]]} {
    lappend missing_ip_runs IROM_synth_1
}
if {![file exists [file join [file dirname $project_xpr] functional_retime.gen sources_1 ip DRAM_TDP_1 DRAM_TDP.dcp]]} {
    lappend missing_ip_runs DRAM_TDP_synth_1
}
if {[llength $missing_ip_runs] != 0} {
    puts "=== Building missing OOC memory-IP checkpoints ==="
    foreach ip_run $missing_ip_runs { reset_run $ip_run }
    launch_runs $missing_ip_runs -jobs 8
    wait_on_run $missing_ip_runs
}
foreach ip_run $required_ip_runs {
    puts "$ip_run status: [get_property STATUS [get_runs $ip_run]]"
}

if {[llength [get_runs -quiet $synth_run]] == 0} {
    create_run $synth_run -flow {Vivado Synthesis 2023}
} else {
    reset_run $synth_run
}
if {[llength [get_runs -quiet $impl_run]] == 0} {
    create_run $impl_run -parent_run $synth_run -flow {Vivado Implementation 2023}
} else {
    reset_run $impl_run
}

# Favor high-fanout BRAM address routing while retaining both pre- and
# post-route physical optimization.  The prior bitstream's WNS was dominated
# by bram_addr_r -> DRAM_TDP address routing, not by the new response register.
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high [get_runs $impl_run]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $impl_run]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs $impl_run]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $impl_run]

puts "=== Starting $synth_run ==="
launch_runs $synth_run -jobs 8
wait_on_run $synth_run
puts "$synth_run status: [get_property STATUS [get_runs $synth_run]]"

puts "=== Starting $impl_run through post-route physical optimization ==="
launch_runs $impl_run -to_step post_route_phys_opt_design -jobs 8
wait_on_run $impl_run
puts "$impl_run status: [get_property STATUS [get_runs $impl_run]]"

open_run $impl_run

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

# Confirm that the response boundary survived synthesis and inspect both sides
# of it separately.  There must be 32 flip-flops named mem_load_rdata_reg.
set load_regs [get_cells -hier -quiet *mem_load_rdata_reg*]
puts "mem_load_rdata register cells: [llength $load_regs]"
if {[llength $load_regs] != 0} {
    redirect -file [file join $report_dir mem_load_rdata_cells.rpt] {
        report_property -all $load_regs
    }
}
set load_d_pins [get_pins -quiet -of_objects $load_regs -filter {REF_PIN_NAME == D}]
set load_q_pins [get_pins -quiet -of_objects $load_regs -filter {REF_PIN_NAME == Q}]
if {[llength $load_d_pins] != 0} {
    report_timing -delay_type max -to $load_d_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bridge_response_capture_paths.rpt]
}
if {[llength $load_q_pins] != 0} {
    report_timing -delay_type max -from $load_q_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bridge_response_consumer_paths.rpt]
}

set bram_addr_q_pins [get_pins -hier -quiet *bram_addr_r_reg*/Q]
if {[llength $bram_addr_q_pins] != 0} {
    report_timing -delay_type max -from $bram_addr_q_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bram_address_fanout_paths.rpt]
}

write_checkpoint -force [file join $report_dir post_route_physopt.dcp]

set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold  [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [get_property SLACK $worst_setup]
set whs [get_property SLACK $worst_hold]
puts "FUNCTIONAL_RETIME_WNS=$wns"
puts "FUNCTIONAL_RETIME_WHS=$whs"
puts "FUNCTIONAL_RETIME_REPORT_DIR=$report_dir"

close_project
if {$wns < 0 || $whs < 0} {
    exit 2
}
exit
