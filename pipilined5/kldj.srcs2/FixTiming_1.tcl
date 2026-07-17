# FixTiming_1 implementation recipe.
#
# Run this from the Tcl Console of the already-open Vivado 2023.2
# digital_twin project:
#   source {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/FixTiming_1.tcl}
#
# It deliberately creates new runs and stops after post-route physical
# optimization.  It never resets or overwrites impl_9 and does not write a
# bitstream; inspect the generated reports before launching write_bitstream.

set fix_tag   FixTiming_1
set synth_run synth_${fix_tag}
set impl_run  impl_${fix_tag}
set report_dir {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/FixTiming_1}

if {[llength [get_runs -quiet $synth_run]] != 0 ||
    [llength [get_runs -quiet $impl_run]]  != 0} {
    error "${synth_run} or ${impl_run} already exists.  This script refuses to overwrite an existing run."
}

file mkdir $report_dir

# Keep the ordinary project sources/constraints and make a clean, independent
# synthesis/implementation pair for this RTL revision.
create_run $synth_run -flow {Vivado Synthesis 2023}
create_run $impl_run -parent_run $synth_run -flow {Vivado Implementation 2023}

# The dominant setup failures are BRAM-return nets.  Favor their placement and
# routing, and run both the existing pre-route and a new post-route phys-opt.
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high [get_runs $impl_run]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $impl_run]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs $impl_run]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $impl_run]

puts "\n=== ${fix_tag}: starting fresh synthesis ==="
launch_runs $synth_run -jobs 8
wait_on_run $synth_run
puts "${synth_run} status: [get_property STATUS [get_runs $synth_run]]"
puts "Check its runme.log for: ENABLE_MEM2_LOAD_FWD bound to: 1'b1"

puts "\n=== ${fix_tag}: implementing through post-route phys-opt (no bitstream) ==="
launch_runs $impl_run -to_step post_route_phys_opt_design -jobs 8
wait_on_run $impl_run
puts "${impl_run} status: [get_property STATUS [get_runs $impl_run]]"

open_run $impl_run
report_timing_summary -delay_type max -max_paths 100 -report_unconstrained \
    -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 100 \
    -file [file join $report_dir setup_paths.rpt]
report_timing -delay_type min -max_paths 100 \
    -file [file join $report_dir hold_paths.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_route_status -file [file join $report_dir route_status.rpt]

set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold  [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $worst_setup] != 0} {
    puts "${fix_tag} setup WNS: [get_property SLACK $worst_setup] ns"
}
if {[llength $worst_hold] != 0} {
    puts "${fix_tag} hold WHS:  [get_property SLACK $worst_hold] ns"
}
puts "${fix_tag} reports: $report_dir"
puts "Only if setup/hold both close (WNS/WHS >= 0, TNS/THS = 0), run:"
puts "  launch_runs $impl_run -to_step write_bitstream -jobs 8"
