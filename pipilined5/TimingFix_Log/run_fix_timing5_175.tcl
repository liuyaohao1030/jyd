set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".."]]
set project_file [file join $root_dir "digital_twin" "digital_twin.xpr"]
set out_dir [file join $script_dir "Fix_Timing5_impl"]

file mkdir $out_dir
set_param general.maxThreads 8

open_project $project_file
update_compile_order -fileset sources_1

synth_design -top top -part xc7k325tffg900-2
write_checkpoint -force [file join $out_dir "post_synth.dcp"]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $out_dir "utilization_synth.rpt"]
report_timing_summary -delay_type max -report_unconstrained -max_paths 20 \
    -file [file join $out_dir "timing_synth.rpt"]

opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
phys_opt_design -post_route -directive AggressiveExplore

write_checkpoint -force [file join $out_dir "post_route.dcp"]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -input_pins -file [file join $out_dir "timing_summary.rpt"]
report_timing -delay_type max -path_type full_clock_expanded -max_paths 60 \
    -nworst 1 -sort_by slack -input_pins -nets \
    -file [file join $out_dir "worst_paths.rpt"]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $out_dir "utilization_hier.rpt"]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $out_dir "high_fanout.rpt"]
report_design_analysis -congestion -file [file join $out_dir "congestion.rpt"]
report_methodology -file [file join $out_dir "methodology.rpt"]
report_route_status -file [file join $out_dir "route_status.rpt"]

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns [get_property SLACK $worst_path]
set fp [open [file join $out_dir "result.txt"] "w"]
puts $fp "WNS(ns): $wns"
puts $fp "Worst startpoint: [get_property STARTPOINT_PIN $worst_path]"
puts $fp "Worst endpoint: [get_property ENDPOINT_PIN $worst_path]"
close $fp

puts "FIX_TIMING5_WNS_NS=$wns"
close_project

if {$wns < 0.0} {
    error "Fix_Timing5 does not meet 175 MHz timing: WNS=$wns ns"
}

