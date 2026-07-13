# 任务：仅在分支预测侧继续优化时序，并在时序稳定后加入RAS

## 工作区

仓库目录：

D:\Desktop\JYD\Source_code\BPU_FixTiming3\jyd\

目前目录是在：
D:\Desktop\JYD\Source_code\BPU_FixTiming3\jyd\pipilined5\

当前工作必须以 **FixTiming3版本** 为起点。开始前请先执行只读检查，确认当前Git分支和源码确实是FixTiming3，即merge_dualport_bpu.

## 严格修改范围

我的同事负责CPU流水线和整体架构，我只负责分支预测。

允许修改：

- `kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`
- 分支预测恢复控制和预测元数据接口
- 为BPU/RAS接入所必需的最小顶层连线
- BPU/RAS测试文件
- `TimingFix_Log/fix_timing.md`

未经我确认，不允许：

- 增加、删除或重新划分流水级
- 修改转发、暂停、访存、CSR、提交和异常架构
- 修改同事负责模块的功能语义
- 添加false path或multicycle path掩盖真实违例
- 改变时钟约束
- 使用同步BRAM读取而改变IF预测延迟

如果RAS必须修改IF/ID或ID/EX预测元数据，只允许增加必要的
`pred_source`、`pred_is_ras`或RAS预测目标字段，并先说明接口影响。

## 当前目标

- CPU功能已经通过仿真和上板验证。
- 目标主频为175 MHz，周期约5.714 ns。
- 先获得稳定的setup/hold余量，再加入RAS。
- 希望175 MHz下WNS至少有约+0.1 ns，而不是仅仅擦边通过。
- 暂时不要直接实现RAS，先阅读代码、日志和报告，给出BPU侧下一步方案。

## 必读源码

- `kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`
- `kldj.srcs2/sources_1/imports/rtl/pipe/ex_bpu_ctrl.v`
- `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v`
- `kldj.srcs2/sources_1/imports/rtl/pipe/pipe_if_id.v`
- `kldj.srcs2/sources_1/imports/rtl/pipe/pipe_id_ex.v`
- `kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_ifu.v`
- `kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_idu.v`
- `kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_exu.v`

外部顶层和板级代码位于 `new` 文件夹，只用于理解接口，除非我明确授权，否则不要修改。

## 必读日志与报告

完整优化日志：

`TimingFix_Log/fix_timing.md`

FixTiming3报告：

- `Timing_info/fix_timng3/150mhz/`
- `Timing_info/fix_timng3/175mhz/`

**如果需要其它报告请及时说明，这些报告都是用-directive为default跑出来的真实数据，而不是特殊的**-directive（没有使用AggresiveExlpore和DelayNet_high）

## 历史版本总结

### FixTiming3

主要修改：

- 当前BPU不预测JALR，也没有RAS。
- 删除EX恢复路径中当前无实际用途的32位预测目标比较：
  `target_check_needed`、`target_miss`。
- `ex_redirect`只由有效指令的方向失配触发。
- 保留预测目标流水接口，为以后RAS使用。
- 64项GShare/PHT和64项BTB保持不变。
- PHT和BTB使用异步读、同步写的distributed LUTRAM。
- BTB保存`{tag,target}`。
- JAL目标在IF阶段静态计算。
- 功能回归和上板运行正确。

时序结果：

- 150 MHz default：WNS=+0.142 ns，TNS=0，WHS约+0.077 ns。
- 175 MHz，Place=`ExtraNetDelay_high`、
  Route=`AggressiveExplore`：
  WNS=+0.009 ns，TNS=0，WHS=+0.082 ns，THS=0。
- 175 MHz虽然通过，但只有9 ps setup余量，不足以直接加入RAS。

### FixTiming4A实验

主要修改：

- 条件分支目标改为IF阶段用B-type立即数静态计算。
- BTB由64×56位`{tag,target}`改为64×24位tag-only。
- LUTRAM从80降至36。
- 没有修改流水级、stall、flush或提交架构。
- 功能仿真和上板功能正确。

时序结果：

- 150 MHz default：
  WNS=+0.361 ns，TNS=0，WHS=+0.074 ns。
- 175 MHz default：
  WNS=-0.324 ns，TNS=-16.745 ns，143个setup失败端点。
- 175 MHz特殊directive：
  WNS=-0.161 ns，TNS=-2.345 ns，WHS=+0.043 ns。
- 175 MHz下最差路径迁移到EX/MEM、ID/EX、LED/PC控制和高扇出布线路径，
  不再明显是BTB target路径。
- 因此FixTiming4A作为150 MHz版本更好，但作为175 MHz基线弱于FixTiming3。
- FixTiming4A已经单独保存，不要在当前FixTiming3基线上重复叠加它。

## 需要你完成的分析

1. 确认当前源码确实是FixTiming3。
2. 从175 MHz报告判断BPU是否仍在最差路径或前若干差路径中。
3. 区分BPU内部问题、预测到PC的组合路径和同事负责的系统级路径。
4. 提出只在BPU侧可实施的优化，按预期收益、功能风险和预测准确率代价排序。
5. 评估64项改32项的FixTiming4B是否值得做，但不要默认它一定改善WNS。
6. 明确哪些建议会改变CPU架构，并排除这些方案。
7. 在动代码前先给出分析、修改范围、验证方法和回退点，等待我确认。

## 后续RAS要求

只有175 MHz具有稳定余量后才加入RAS。

RAS方案必须：

- 不增加流水级
- 使用独立的预测来源元数据，如`pred_is_ras`或`pred_source`
- 只对RAS/间接预测重新启用预测目标失配检查
- 不把直接分支target重新放回BTB
- 正确处理call、return、嵌套调用、栈满/栈空、flush和误预测恢复
- 增加独立RAS测试和完整CPU回归
- 每次修改同步更新`TimingFix_Log/fix_timing.md`，完善日志，当然你也可以查看日志来看之前的工作

当前先不要修改代码，先阅读并给出证据充分的分析。