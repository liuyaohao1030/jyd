# 1. 创建专门存放这次成功数据的文件夹
file mkdir Timing_info/Golden_175MHz

# 2. 导出基础的核心报告 (Summary, Max/Min, High Fanout, Util, Congestion)
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file Timing_info/Golden_175MHz/timing_summary_min_max.rpt
report_timing -delay_type max -path_type full_clock_expanded -max_paths 60 -sort_by slack -input_pins -nets -file Timing_info/Golden_175MHz/timing_full_max.rpt
report_timing -delay_type min -path_type full_clock_expanded -max_paths 60 -sort_by slack -input_pins -nets -file Timing_info/Golden_175MHz/timing_full_min.rpt
report_high_fanout_nets -timing -load_types -max_nets 100 -file Timing_info/Golden_175MHz/high_fanout.rpt
report_utilization -hierarchical -hierarchical_depth 6 -file Timing_info/Golden_175MHz/utilization_hier.rpt
report_design_analysis -congestion -file Timing_info/Golden_175MHz/congestion.rpt

# 3. 导出 BPU 相关的定向报告 (加了 catch 防闪退保护)
# (A) IFU PC -> BPU -> IFU PC
catch {report_timing -delay_type max -from [get_pins -hier *pc_reg*/C] -through [get_cells -hier *u_bpu*] -to [get_pins -hier *pc_reg*/D] -max_paths 100 -path_type full_clock_expanded -sort_by slack -input_pins -nets -file Timing_info/Golden_175MHz/timing_pc_bpu_pc.rpt}
# (B) EX Update -> BPU
catch {report_timing -delay_type max -from [get_cells -hier *ex*] -to [get_cells -hier *u_bpu*] -max_paths 100 -path_type full_clock_expanded -sort_by slack -input_pins -nets -file Timing_info/Golden_175MHz/timing_bpu_update.rpt}

# 4. 导出当前的 Run Info 和 Directives (综合/实现策略)
set f [open "Timing_info/Golden_175MHz/run_info.txt" w]
puts $f "Implementation Strategy: [get_property STRATEGY [current_run]]"
puts $f "Opt Design Directive: [get_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE [current_run]]"
puts $f "Place Design Directive: [get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [current_run]]"
puts $f "Phys Opt Directive: [get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE [current_run]]"
puts $f "Route Design Directive: [get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE [current_run]]"
close $f

# 5. 导出设计检查点 (post_impl.dcp) - 这文件可能有点大(几十MB)
write_checkpoint -force Timing_info/Golden_175MHz/post_impl.dcp