# Generate a board-test bitstream only from the already verified post-route DCP.
# This script does not synthesize, place, or route, and does not program hardware.

set root {D:/Desktop/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime}
set dcp [file join $root reports post_route_physopt.dcp]
set bit [file join $root reports functional_retime_200m_fix.bit]
set drc [file join $root reports bitstream_drc.rpt]

if {![file exists $dcp]} {
    error "Verified post-route checkpoint is missing: $dcp"
}

open_checkpoint $dcp

set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold  [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [get_property SLACK $worst_setup]
set whs [get_property SLACK $worst_hold]
puts "BITGEN_INPUT_WNS=$wns"
puts "BITGEN_INPUT_WHS=$whs"
if {$wns < 0 || $whs < 0} {
    error "Refusing bitstream generation from a timing-violating checkpoint"
}

if {[file exists $bit]} {
    error "Refusing to overwrite an existing board-test bitstream: $bit"
}

report_drc -ruledecks {bitstream_checks} -file $drc
write_bitstream $bit
puts "BITSTREAM=$bit"
close_design
exit
