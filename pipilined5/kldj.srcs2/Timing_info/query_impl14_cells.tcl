open_checkpoint {D:/DESKTOP/JYD/Source_code/six_try/jyd/pipilined5/kldj.srcs2/Timing_info/Functional_Retime/project/functional_retime.runs/synth_functional_retime/top.dcp}
puts "=== mem_load / mem_dram cells ==="
foreach c [get_cells -hier -quiet -filter {NAME =~ *mem_load* || NAME =~ *mem_dram*}] {
    puts [get_property NAME $c]
}
puts "=== bridge registers ==="
foreach c [get_cells -hier -quiet -filter {NAME =~ student_top_inst/bridge_inst/*}] {
    set n [get_property NAME $c]
    if {[string match *rdata* $n] || [string match *rd_is* $n]} { puts $n }
}
puts "=== KLDJ MEM2 registers ==="
foreach c [get_cells -hier -quiet -filter {NAME =~ student_top_inst/u_KLDJ_top/u_pipe_mem1_mem2/*}] {
    puts [get_property NAME $c]
}
puts "=== merged response-register provenance ==="
foreach c [get_cells -hier -quiet -filter {NAME =~ *mem2_mem_rdata_reg*}] {
    puts "CELL=[get_property NAME $c] ORIG=[get_property ORIG_CELL_NAME $c]"
    set d [get_pins -quiet -of_objects $c -filter {REF_PIN_NAME == D}]
    foreach pin $d {
        set n [get_nets -quiet -of_objects $pin]
        puts "  DNET=[get_property NAME $n]"
        foreach p [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}] {
            puts "  DRIVER=[get_property NAME $p]"
        }
    }
}
close_design
