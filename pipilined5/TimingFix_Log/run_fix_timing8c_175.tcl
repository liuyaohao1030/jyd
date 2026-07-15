# Isolated FixTiming8C implementation run. This deliberately does not open
# digital_twin.xpr, so it does not modify an open Vivado GUI project.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".."]]
set rtl_dir [file join $root_dir "kldj.srcs2" "sources_1" "imports" "rtl"]
set out_dir [file join $script_dir "FixTiming8C_impl"]
set ip_dir [file join $root_dir "digital_twin" "digital_twin.srcs" "sources_1" "ip"]

file mkdir $out_dir
set_param general.maxThreads 8
create_project -in_memory -part xc7k325tffg900-2
set_property target_language Verilog [current_project]

read_verilog -sv [list \
    [file join $root_dir "new" "counter.sv"] \
    [file join $root_dir "new" "display_seg.sv"] \
    [file join $root_dir "new" "dram_driver.sv"] \
    [file join $root_dir "new" "perip_bridge.sv"] \
    [file join $root_dir "new" "seg7.sv"] \
    [file join $root_dir "new" "student_top.sv"] \
    [file join $root_dir "new" "twin_controller.sv"] \
    [file join $root_dir "new" "uart.sv"] \
    [file join $root_dir "new" "top.sv"]]

read_verilog [file join $rtl_dir "define.v"]
foreach pattern [list \
    [file join $rtl_dir "alu" "*.v"] \
    [file join $rtl_dir "stage" "*.v"] \
    [file join $rtl_dir "pipe" "*.v"] \
    [file join $rtl_dir "util" "*.v"] \
    [file join $rtl_dir "KLDJ_perf_counters.v"] \
    [file join $rtl_dir "KLDJ_top.v"]] {
    foreach source_file [glob -nocomplain $pattern] {
        read_verilog $source_file
    }
}

read_ip [file join $ip_dir "div_gen_u32_1" "div_gen_u32.xci"]
read_ip [file join $ip_dir "mult_gen_u33_1" "mult_gen_u33.xci"]
read_ip [file join $ip_dir "pll_1" "pll.xci"]
read_ip [file join $ip_dir "IROM" "IROM.xci"]
read_ip [file join $ip_dir "DRAM_TDP_1" "DRAM_TDP.xci"]
read_xdc [file join $root_dir "digital_twin" "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]

synth_design -top top -part xc7k325tffg900-2
write_checkpoint -force [file join $out_dir "post_synth.dcp"]
report_timing_summary -delay_type max -report_unconstrained -max_paths 20 \
    -file [file join $out_dir "timing_synth.rpt"]

opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
phys_opt_design -directive AggressiveExplore

write_checkpoint -force [file join $out_dir "post_route.dcp"]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $out_dir "timing_summary.rpt"]
report_timing -delay_type max -path_type full_clock_expanded -max_paths 60 \
    -nworst 1 -sort_by slack -input_pins -nets \
    -file [file join $out_dir "worst_paths.rpt"]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $out_dir "utilization_hier.rpt"]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $out_dir "high_fanout.rpt"]
report_design_analysis -congestion -file [file join $out_dir "congestion.rpt"]

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set fp [open [file join $out_dir "result.txt"] "w"]
puts $fp "WNS(ns): [get_property SLACK $worst_path]"
puts $fp "Worst startpoint: [get_property STARTPOINT_PIN $worst_path]"
puts $fp "Worst endpoint: [get_property ENDPOINT_PIN $worst_path]"
close $fp

puts "FIX_TIMING8C_WNS_NS=[get_property SLACK $worst_path]"
close_project
