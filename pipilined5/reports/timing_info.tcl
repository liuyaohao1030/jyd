# 0. 定义绝对路径变量（注意：所有的反斜杠 \ 都已经替换成了正斜杠 /）
set out_dir "D:/Desktop/JYD/Source_code/BPU_FixTiming3/jyd/pipilined5/Timing_info/fixtiming9"

# 1. 创建该绝对路径下的所有文件夹（就算父文件夹不存在，它也会自动顺藤摸瓜建好）
file mkdir $out_dir

# 2. 导出时序汇总 (Design Timing Summary)
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose -max_paths 20 -file $out_dir/timing_summary.rpt

# 3. 导出包含 detailed nets 的最差详细路径 (Intra-Clock Paths 详情)
report_timing -delay_type max -path_type full_clock_expanded -max_paths 60 -nworst 1 -sort_by slack -input_pins -nets -file $out_dir/worst_paths.rpt

# 4. 导出高扇出网络报告
report_high_fanout_nets -timing -load_types -max_nets 100 -file $out_dir/high_fanout.rpt

# 5. 导出资源利用率报告
report_utilization -hierarchical -hierarchical_depth 6 -file $out_dir/utilization_hier.rpt

# 6. 导出拥塞分析报告
report_design_analysis -congestion -file $out_dir/congestion.rpt

puts "报告已成功生成到绝对路径: $out_dir"

# source D:/Desktop/JYD/Source_code/BPU_FixTiming3/jyd/pipilined5/reports/timing_info.tcl