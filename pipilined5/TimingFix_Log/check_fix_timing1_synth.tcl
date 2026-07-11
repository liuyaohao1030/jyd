set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]
set rtl_dir [file join $project_root kldj.srcs2 sources_1 imports rtl]
set output_dir [file join $script_dir Fix_timing1_synth]
set requested_part xc7k325tffg900-2
set target_part $requested_part

if {[llength [get_parts -quiet $requested_part]] == 0} {
    # The locally installed Vivado 2018.3 device set does not include Kintex-7.
    # Artix-7 uses the same 7-series distributed-RAM primitives, so it remains
    # a valid inference check. Full timing must still use the project tool/part.
    set target_part xc7a35tcpg236-1
    puts "WARNING: $requested_part is unavailable; using $target_part for LUTRAM inference only."
}

file mkdir $output_dir

read_verilog [file join $rtl_dir define.v]
read_verilog [file join $rtl_dir pipe bpu.v]
synth_design -top bpu -part $target_part -mode out_of_context -flatten_hierarchy none

create_clock -name bpu_clk -period 6.667 [get_ports clk]

report_utilization -hierarchical -hierarchical_depth 4 \
    -file [file join $output_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $output_dir timing_summary_synth.rpt]
report_high_fanout_nets -timing -load_types -max_nets 30 \
    -file [file join $output_dir high_fanout_synth.rpt]

set ram_cells [get_cells -hierarchical -filter {REF_NAME =~ RAM64*}]
set fp [open [file join $output_dir inferred_ram_cells.txt] w]
puts $fp "Inferred RAM primitive count: [llength $ram_cells]"
foreach ram_cell $ram_cells {
    puts $fp "[get_property NAME $ram_cell] [get_property REF_NAME $ram_cell]"
}
close $fp

write_checkpoint -force [file join $output_dir bpu_fix_timing1_synth.dcp]
