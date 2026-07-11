set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]
set rtl_dir [file join $project_root kldj.srcs2 sources_1 imports rtl]
set output_dir [file join $script_dir Fix_timing3_synth]
set requested_part xc7k325tffg900-2
set target_part $requested_part

if {[llength [get_parts -quiet $requested_part]] == 0} {
    # This check only verifies the recovery cone structure. Routed timing must
    # still be measured with the project Vivado version and target device.
    set target_part xc7a35tcpg236-1
    puts "WARNING: $requested_part is unavailable; using $target_part for structural synthesis only."
}

file mkdir $output_dir

read_verilog [file join $rtl_dir define.v]
read_verilog [file join $rtl_dir pipe ex_bpu_ctrl.v]
synth_design -top ex_bpu_ctrl -part $target_part -mode out_of_context -flatten_hierarchy none

create_clock -name virtual_clk -period 6.667
set_input_delay 0 -clock virtual_clk [get_ports -filter {DIRECTION == IN}]
set_output_delay 0 -clock virtual_clk [get_ports -filter {DIRECTION == OUT}]

report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $output_dir timing_summary_synth.rpt]
report_timing -delay_type max -max_paths 20 \
    -file [file join $output_dir timing_paths_synth.rpt]

set redirect_fanin [all_fanin -flat -to [get_ports ex_redirect]]
set target_dependencies {}
set fp [open [file join $output_dir redirect_fanin.txt] w]
puts $fp "ex_redirect flat fanin objects: [llength $redirect_fanin]"
foreach obj $redirect_fanin {
    set obj_name [get_property NAME $obj]
    puts $fp $obj_name
    if {[string match *id_ex_pred_target* $obj_name]} {
        lappend target_dependencies $obj_name
    }
}
puts $fp "id_ex_pred_target dependencies: [llength $target_dependencies]"
close $fp

if {[llength $target_dependencies] != 0} {
    error "id_ex_pred_target still appears in the ex_redirect fanin cone"
}

write_checkpoint -force [file join $output_dir ex_bpu_ctrl_fix_timing3_synth.dcp]
