# Read-only post-route evidence collection.  This script never calls opt/place/
# route/write_bitstream and only writes text reports beside the isolated run.

set root {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime}
set dcp [file join $root reports post_route_physopt.dcp]
set report_dir [file join $root reports]
if {![file exists $dcp]} { error "Post-route checkpoint is missing: $dcp" }

proc property_or_na {obj property_name} {
    if {[catch {get_property $property_name $obj} value]} { return "N/A" }
    return $value
}

open_checkpoint $dcp

# Avoid Tcl redirect: emit the evidence file directly, one cell per line.
set load_regs [lsort [get_cells -hier -quiet *mem_load_rdata_reg*]]
set fp [open [file join $report_dir mem_load_rdata_cells.rpt] w]
puts $fp "MEM_LOAD_RDATA_FF_COUNT=[llength $load_regs]"
foreach cell $load_regs {
    puts $fp [format "%s | REF_NAME=%s | LOC=%s | BEL=%s" \
        [get_property NAME $cell] \
        [property_or_na $cell REF_NAME] \
        [property_or_na $cell LOC] \
        [property_or_na $cell BEL]]
}
close $fp

set load_d_pins [get_pins -quiet -of_objects $load_regs -filter {REF_PIN_NAME == D}]
set load_q_pins [get_pins -quiet -of_objects $load_regs -filter {REF_PIN_NAME == Q}]
puts "MEM_LOAD_RDATA_D_PIN_COUNT=[llength $load_d_pins]"
puts "MEM_LOAD_RDATA_Q_PIN_COUNT=[llength $load_q_pins]"
if {[llength $load_d_pins] != 0} {
    report_timing -delay_type max -to $load_d_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bridge_response_capture_paths.rpt]
}
if {[llength $load_q_pins] != 0} {
    report_timing -delay_type max -from $load_q_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bridge_response_consumer_paths.rpt]
}

set bram_addr_q_pins [get_pins -hier -quiet *bram_addr_r_reg*/Q]
puts "BRAM_ADDR_Q_PIN_COUNT=[llength $bram_addr_q_pins]"
if {[llength $bram_addr_q_pins] != 0} {
    report_timing -delay_type max -from $bram_addr_q_pins -max_paths 50 -input_pins -nets \
        -file [file join $report_dir bram_address_fanout_paths.rpt]
}
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $report_dir high_fanout_post_route_query.rpt]

set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold  [get_timing_paths -quiet -delay_type min -max_paths 1]
puts "POST_ROUTE_QUERY_WNS=[get_property SLACK $worst_setup]"
puts "POST_ROUTE_QUERY_WHS=[get_property SLACK $worst_hold]"
close_design
exit
