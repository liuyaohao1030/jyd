# Fix_timing1

## 目标

在不修改五级流水线架构和 BPU 外部接口的前提下，优化 GShare + BTB 的 FPGA 存储实现，降低 BPU 对 150 MHz 全系统时序的压力。

本轮只处理 `kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`。不修改 IF/ID/EX/MEM/WB 流水线逻辑，不增加预测周期，也不在本轮寄存 BPU 更新请求。

## 修改前基线

数据来源：`Timing_info/150mhz` 中的 routed timing 和 high-fanout 报告。

| 项目 | 修改前 |
| --- | ---: |
| 目标频率 | 150 MHz |
| 时钟周期 | 6.667 ns |
| WNS | -0.663 ns |
| TNS | -32.862 ns |
| Setup 失败端点 | 98 |
| Hold 失败端点 | 0 |
| 最差数据路径延迟 | 7.018 ns |
| 最差路径逻辑延迟 | 1.576 ns |
| 最差路径布线延迟 | 5.442 ns（77.544%） |
| 最差路径逻辑级数 | 19 |
| BPU 复位网最高扇出 | 6213 |
| IFU PC 单比特最高扇出 | 1895 |

最差路径为 EX 分支恢复闭环：`EX/MEM valid -> forwarding -> branch compare -> mispredict detection -> IFU PC/CE`。该路径不直接经过 BPU 查询输出，但当前 BPU 的寄存器数组、全表复位和异步大规模选择网络会增加扇出、拥塞与布线延迟。

## 修改前实现问题

- PHT、BTB valid、BTB tag 和 BTB target 均使用寄存器数组。
- 复位时通过 `for` 循环清除所有 entry，产生数千个同步复位负载。
- BTB tag 和 target 分开存储，重复使用动态索引选择网络。
- 数组带逐项复位，不符合 Xilinx distributed RAM 的常用推断模板。
- 64 项 BPU 需要零周期查询，不适合直接替换为同步读 BRAM。

## 本轮实施方案

1. 将 BTB tag 与 target 打包为一个存储字。
2. 将 BTB 数据表改写为异步读、同步写的 distributed RAM 推断结构。
3. 将 PHT 改写为支持查询端和更新端读取的 distributed RAM 推断结构。
4. 新增独立的 `pht_valid`；保留独立的 `btb_valid`。
5. 复位时只清 `ghr`、`pht_valid` 和 `btb_valid`，不复位 PHT/BTB 数据阵列。
6. PHT entry 无效时等效为参数 `BHT_RESET_VALUE`，保持原有冷启动行为。
7. 保持现有端口、索引方法、饱和计数更新、BTB 更新条件和预测延迟不变。

## 修改记录

### 记录 1：建立基线

- 已建立本日志并记录 150 MHz 修改前数据。
- 修改范围已限定为 BPU 存储和复位实现。

### 记录 2：重构 PHT 和 BTB 存储

修改文件：`kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`

- 删除 PHT、BTB tag 和 BTB target 的逐项复位循环。
- 将 `btb_tag` 和 `btb_target` 合并为 `btb_data`，存储字格式为 `{tag, target}`。
- 为 PHT 和 BTB 数据阵列添加 `ram_style = "distributed"` 属性。
- 将 `pht_valid` 和 `btb_valid` 改为独立的 packed valid 向量。
- 复位只清 GHR 和两个 valid 向量，RAM 数据保留但不会在 valid 为 0 时生效。
- PHT 查询和更新读取在 entry 无效时使用 `BHT_RESET_VALUE`，保持原始复位后的计数器行为。
- 饱和计数更新改为先计算 `update_pht_next`，每次有效训练写入一个确定值，避免首次训练时读取未初始化 RAM。
- BPU 端口、索引宽度、组合预测延迟和 BTB 写入条件均未改变。

### 记录 3：更新单元测试观察点

修改文件：`kldj.srcs2/sim_1/imports/sim/bpu_tb.sv`

- 将测试中对旧 `btb_target` 数组的层次引用改为打包后的 `btb_data[entry][31:0]`。
- 修正测试对 wrapper 内部状态的层次路径，统一通过 `dut.u_gshare_btb_core` 观察 PHT、BTB 和 GHR。
- 同步修正 CPU 集成测试中 GHR 的 wrapper 层次观察路径。
- 增加运行时重新复位检查，确认 RAM 中即使保留旧数据，清零 valid 后也不会产生 BTB hit 或 taken prediction。
- 该修改只适配测试内部观察点，不改变设计接口或测试功能目标。

### 记录 4：建立独立综合检查

新增文件：`TimingFix_Log/check_fix_timing1_synth.tcl`

- 以 `bpu` 为顶层，对 `xc7k325tffg900-2` 执行 out-of-context 综合。
- 输出层次资源、综合后时序、高扇出、RAM primitive 清单和综合 DCP。
- 用于确认 RAM 是否真实推断，避免只根据 RTL 属性判断优化成功。
- 本机 Vivado 为 2018.3；脚本显式读取 `define.v`，兼容该版本不支持 `read_verilog -include_dirs` 的行为。
- 本机 2018.3 未安装目标 Kintex-7 器件库时，脚本回退到同属 7 系列、具有相同 distributed-RAM primitive 的 Artix-7，仅检查 RAM 推断；正式资源和时序结论仍必须使用工程的 `xc7k325tffg900-2` 与 Vivado 2023.2。

### 记录 5：RTL 与功能验证结果

- Vivado Simulator 2018.3 完整编译正式 RTL 成功。
- BPU 单元测试通过，覆盖冷启动、taken/not-taken 饱和计数、BTB tag/target、GShare 训练、tag 冲突和运行时重新复位。
- CPU 集成测试通过：条件分支更新 12 次，动态预测正确命中 4 次，最终 GHR 为 63。
- 运行时复位后，即使 LUTRAM 中保留旧数据，`pht_valid`/`btb_valid` 清零仍能阻止旧预测生效。

### 记录 6：LUTRAM 推断结果

独立综合工具：Vivado 2018.3；推断检查器件：`xc7a35tcpg236-1`。该器件仅用于验证与目标 Kintex-7 相同的 7 系列 LUTRAM 映射规则。

| 项目 | 独立综合结果 |
| --- | ---: |
| PHT | 64 x 2，`RAM64X1D x 2` |
| BTB tag+target | 64 x 56，`RAM64M x 19` |
| LUT as Memory | 80 |
| 普通逻辑 LUT | 235 |
| FDRE | 134 |
| reset 最高扇出 | 136 |
| lookup PC 最高扇出 | 106 |
| 6.667 ns BPU 内部综合 WNS | +2.205 ns |

134 个 FDRE 对应 64 位 `pht_valid`、64 位 `btb_valid` 和 6 位 GHR，说明 PHT/BTB 数据没有继续实现为大规模触发器阵列。

独立综合 WNS只覆盖 BPU 内部寄存器路径，不包含全系统 IF 查询输入/输出延迟、EX 恢复链和布局拥塞，不能替代 Vivado 2023.2 下的完整 routed timing。

## 验证状态

| 验证项 | 状态 | 结果 |
| --- | --- | --- |
| RTL 修改 | 已完成 | PHT/BTB 存储与复位已重构 |
| Verilog 编译 | 通过 | 正式 RTL 与两个 BPU 测试均成功编译 |
| 功能仿真 | 通过 | BPU 单元测试、CPU 集成测试通过 |
| LUTRAM 推断检查 | 通过 | PHT=`RAM64X1D x2`，BTB=`RAM64M x19` |
| 150 MHz 布局布线 | 未开始 | - |

## 移植注意事项

### 文件与接口

- 设计修改集中在 `rtl/pipe/bpu.v`，BPU 顶层端口没有变化。
- `INDEX_WIDTH` 必须与 IF/ID、ID/EX 中传递的 `pred_pht_idx` 宽度一致；当前为 6，即 64 项。
- `lookup_pht_idx` 必须随被预测指令进入流水线，并在该指令到达 EX 时作为 `update_pht_idx` 返回，不能使用 EX 时刻重新计算的 GHR 索引。
- 查询仍为异步组合输出，更新仍在时钟上升沿完成；移植时不能在 BPU 输出处随意增加寄存器，否则会改变取指时序。

### 复位语义

- 复位为同步高有效，取值由 `KLDJ_RSTABLE` 决定。
- 复位只清 GHR 和两个 valid 向量，不清 PHT/BTB RAM 数据，这是 LUTRAM 推断的必要条件。
- 无效 PHT entry 按 `BHT_RESET_VALUE` 参与首次训练；无效 BTB entry 必须保证 `btb_hit=0`。
- `pred_target` 在 BTB miss 时不保证为零，使用方必须以 `pred_taken`/`btb_hit` 判断其有效性；这与原设计中学习过同 index 后的行为一致。

### RAM 推断

- 必须保留异步读、同步写且 RAM 数据无 reset 的结构。
- `ram_style = "distributed"` 不能弥补不兼容的复位或写法，移植后必须检查综合日志的 Final Mapping Report。
- 目标结果应出现 `RAM64X1D`/`RAM64M` 或 Vivado 2023.2 中等价的 distributed-RAM primitive，并且 BPU 数据表不应重新变成数千个 FDRE。
- 不建议对 RAM 数据添加 `keep`/`dont_touch`，以免限制综合和物理优化。

### 查询与更新冲突

- 查询和更新可以在同一周期访问不同 entry。
- 同一时钟沿写入后，异步读口会反映新内容；不同 Vivado版本下仍应通过单元测试确认同地址行为。
- PHT 更新端读取旧计数器并计算饱和值；无效 entry 的首次 taken 更新应得到 `10`，首次 not-taken 更新应得到 `00`。

### 移植后验证

1. 运行 BPU 单元测试和 CPU 分支集成测试。
2. 检查 BPU 层次资源与 RAM primitive。
3. 检查 reset、lookup PC、update valid/PC 的高扇出。
4. 在目标 `xc7k325tffg900-2` 上重新执行完整综合、布局和布线。
5. 将新的 WNS、TNS、失败端点、最差路径、逻辑/布线延迟和高扇出数据追加到本日志。

# Fix_timing3

## 优化目标与基线

本轮从已经回退并确认功能正确的 FixTiming1 版本继续优化，不包含 FixTiming2 的更新请求寄存器方案。

FixTiming1 在 6.7 ns 约束下的布局布线结果：

| 项目 | FixTiming1 |
| --- | ---: |
| WNS | -0.501 ns |
| TNS | -18.963 ns |
| 失败端点 | 73 |
| 最差路径逻辑级数 | 19 |
| 最差路径数据延迟 | 7.051 ns |
| 逻辑延迟 | 1.594 ns |
| 布线延迟 | 5.457 ns（77.393%） |

最差路径经过转发、分支比较和 EX 恢复控制后到达 IFU PC，其中预测目标失配逻辑 `target_miss` 位于关键恢复链上。

## 修改原则

- 当前 BPU 只预测条件分支和 JAL，不预测 JALR，也尚未加入 RAS。
- 对当前可被预测的直接控制流，正确目标由指令立即数唯一确定；原实现已经明确排除其目标比较。
- 因而当前 `target_miss` 只服务于尚不存在的间接跳转预测，属于不可达功能路径，却仍会参与综合和布局布线。
- 本轮只移除该无效目标比较链，不修改 BPU 存储、预测延迟、流水级、更新逻辑、外部接口或时序约束。
- 保留 `id_ex_pred_target` 接口，供后续加入 RAS 时恢复目标校验；届时必须同时传递 `pred_is_ras` 或等价预测来源元数据，只对 RAS 预测执行目标比较。

## 记录 1：简化 EX 预测恢复判定

修改文件：`kldj.srcs2/sources_1/imports/rtl/pipe/ex_bpu_ctrl.v`

- 删除 `ex_is_direct_ctrl`、`target_check_needed` 和 `target_miss` 组合逻辑。
- `direction_miss` 仍为 `id_ex_pred_taken ^ ex_actual_redirect`。
- `ex_redirect` 改为仅由有效指令的方向失配触发：`id_ex_valid && direction_miss`。
- `ex_correct_pc`、异常返回、BPU 训练条件及全部模块端口保持不变。
- 对尚未预测的 JALR、ECALL 和 MRET，`id_ex_pred_taken=0` 且实际发生重定向，仍会通过方向失配正常恢复。

## 记录 2：定向与回归仿真

新增文件：`kldj.srcs2/sim_1/imports/sim/ex_bpu_ctrl_tb.sv`

- `ex_bpu_ctrl` 定向测试通过，共执行 34 个断言。
- 覆盖无效流水项、条件分支 taken/not-taken 方向错误、直接预测目标值不同、JAL、未预测 JALR、ECALL、MRET 和 BPU 训练接口。
- BPU 单元测试通过：`BPU UNIT TEST PASSED (GHR=0)`。
- CPU 分支集成测试通过：条件分支更新 12 次、动态预测正确命中 4 次、最终 GHR 为 63。
- 完整 CPU 回归通过：29 项通过、0 项失败；其中包含 JALR、ECALL/MRET、分支、CSR、数据转发、访存和 RV32M。
- 正式 RTL 全量编译和所有测试的 elaboration 均通过。

## 记录 3：独立综合结构检查

新增脚本：`TimingFix_Log/check_fix_timing3_synth.tcl`

- 本机 Vivado 2018.3 缺少目标 Kintex-7 器件库，因此使用 `xc7a35tcpg236-1` 做 `ex_bpu_ctrl` 的 out-of-context 结构检查。
- 综合成功，0 error、0 critical warning；模块使用 40 个逻辑 LUT，无触发器。
- `ex_redirect` 综合网表扇入共有 12 个对象，只依赖 `id_ex_valid`、`id_ex_pred_taken`、`exu_jump_raw`、`is_ecall` 和 `is_mret`。
- `id_ex_pred_target` 在 `ex_redirect` 扇入中的依赖数为 0，确认目标比较链已从恢复关键锥中消失。
- 综合会对保留的 32 位 `id_ex_pred_target` 报未连接端口 warning，这是为后续 RAS 保留接口的预期结果。
- 6.667 ns 虚拟 IO 约束下，该组合模块 OOC 最差 slack 为 +3.484 ns、最差逻辑级数为 2；此结果不包含整机转发、分支计算、IFU PC 和实际布局布线，不能替代正式 WNS。

## 后续加入 RAS 时的恢复逻辑

- RAS 预测必须增加 `pred_is_ras` 或通用 `pred_source` 元数据，并随预测指令经过 IF/ID、ID/EX 流水寄存器。
- 只有预测来源确实为 RAS（以后若预测普通 JALR，则为有效的间接目标预测）时，才允许比较 `id_ex_pred_target` 与 `ex_correct_pc`。
- 恢复条件应扩展为“方向失配，或者有效间接目标预测发生目标失配”，不能无条件把 32 位目标比较重新并入所有分支的恢复链。
- 加入 RAS 后必须重新补充返回地址命中/失配、嵌套调用、栈溢出/下溢和 flush 恢复测试，再重新测量关键路径。

## 验证状态

| 验证项 | 状态 | 结果 |
| --- | --- | --- |
| RTL 修改 | 已完成 | 移除当前不可达的预测目标比较链 |
| EX 恢复控制定向仿真 | 通过 | 34 个断言全部通过 |
| BPU 单元仿真 | 通过 | GShare、BTB、复位和训练行为通过 |
| BPU 集成仿真 | 通过 | updates=12，hits=4，GHR=63 |
| 完整 CPU 回归 | 通过 | 29 passed，0 failed |
| RTL 编译 | 通过 | 正式 RTL 全量编译和 elaboration 成功 |
| OOC 结构综合 | 通过 | `id_ex_pred_target` 对 `ex_redirect` 的依赖数为 0 |
| 150 MHz 布局布线 | 待执行 | 报告应保存至 `kldj.srcs2/Timing_info/fixtiming3` |

# Fix_timing4A

## 优化目标与基线

FixTiming3 已完成综合、布局布线和功能验证。6.7 ns 约束下 WNS 为 +0.142 ns、TNS 为 0，最差路径为 14 级，数据延迟 6.444 ns，其中布线延迟 5.392 ns（83.675%）。最差路径仍进入 IFU PC，并包含 BTB 数据查询与目标选择锥。

用户额外验证：在 175 MHz 下，将 Place Design directive 设为 `ExtraNetDelay_high`、Route Design directive 设为 `AggressiveExplore` 时，WNS 可达到约 +0.009 ns；该结果已经过时序但尚无足够裕量承受 RAS 目标选择逻辑。

## 修改原则

- 本轮只实施 FixTiming4A，不同时缩减表深度，也不处理更新侧高扇出。
- RISC-V 条件分支和 JAL 都是 PC-relative 直接控制流，目标由当前指令立即数唯一确定。
- JAL 已在 IF 阶段静态识别；本轮将条件分支目标也改为 IF 阶段静态计算。
- BTB 保留 tag、valid 和 PHT 方向预测，不再保存 32 位 target。
- GShare 历史长度、PHT/BTB 项数、预测周期、流水级和 EX 恢复策略保持不变。
- IF/ID、ID/EX 中的 `pred_target` 仍保留，供以后加入 RAS 或其他间接目标预测。

## 记录 1：静态条件分支目标与 tag-only BTB

修改文件：

- `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v`
- `kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`
- `kldj.srcs2/sim_1/imports/sim/bpu_tb.sv`
- `kldj.srcs2/sim_1/imports/sim/bpu_integration_tb.sv`

RTL 调整：

- IF 阶段新增 B-type opcode 识别、立即数拼接和 `if_pc + branch_imm` 目标计算。
- 条件分支只有在当前指令确认为 B-type 且 GShare/BTB 方向预测 taken 时才跳转。
- JAL 继续使用原有静态目标，JALR 仍不参与预测。
- BPU 的 BTB 数据阵列由 `{tag, target}` 改为 tag-only；taken 更新只写 tag 和 valid。
- 移除 BPU 模块的 `pred_target` 和 `update_target` 端口；EX 端保留的更新目标接口暂不参与 BPU 存储。

## 验证状态

| 验证项 | 状态 | 结果 |
| --- | --- | --- |
| RTL 修改 | 已完成 | 静态条件分支目标与 tag-only BTB 已实现 |
| BPU 单元仿真 | 通过 | PHT、GHR、tag 命中/冲突和运行时复位通过 |
| BPU 集成仿真 | 通过 | updates=12，hits=4，GHR=63；负偏移静态目标断言通过 |
| EX 恢复控制仿真 | 通过 | 34 个断言全部通过 |
| 完整 CPU 回归 | 通过 | 29 passed，0 failed |
| RTL 全量编译 | 通过 | 正式 RTL 和全部测试 elaboration 成功 |
| LUTRAM 推断检查 | 通过 | BTB=`RAM64M x8`，PHT=`RAM64X1D x2` |
| 150/175 MHz 布局布线 | 待执行 | 报告建议保存至 `Timing_info/150mhz/fixtiming4A` |

## 记录 2：功能验证结果

- BPU 单元测试通过，tag-only BTB 的分配、tag 冲突、PHT 饱和、GHR 训练和运行时复位行为正确。
- 分支集成测试通过，统计保持为更新 12 次、动态预测命中 4 次、最终 GHR=63。
- 集成测试新增 `0x80000008 -> 0x80000004` 的负偏移 B-type 静态目标断言，确认立即数拼接和加法结果正确。
- FixTiming3 的 EX 恢复控制定向测试保持 34 个断言全部通过。
- 完整 CPU 回归保持 29 项通过、0 项失败，覆盖分支、JAL、JALR、ECALL/MRET、CSR、访存、转发和 RV32M。

## 记录 3：LUTRAM 推断与资源结果

新增脚本：`TimingFix_Log/check_fix_timing4a_synth.tcl`

本机 Vivado 2018.3 使用 `xc7a35tcpg236-1` 做与 Kintex-7 同系列原语规则的独立推断检查；正式资源和时序仍以 Vivado 2023.2、`xc7k325tffg900-2` 全工程结果为准。

| 项目 | FixTiming3 BPU | FixTiming4A BPU |
| --- | ---: | ---: |
| BTB 数据格式 | 64 x 56 `{tag,target}` | 64 x 24 tag-only |
| BTB primitive | `RAM64M x19` | `RAM64M x8` |
| PHT primitive | `RAM64X1D x2` | `RAM64X1D x2` |
| LUTRAM | 80 | 36 |
| 普通逻辑 LUT | 235 | 235 |
| FDRE | 134 | 134 |
| BPU OOC WNS（6.667 ns） | +2.205 ns | +2.205 ns |

- LUTRAM 减少 44 个，来源仅为删除 BTB 的 32 位 target 字段。
- 普通逻辑 LUT、valid/GHR 寄存器和 BPU 内部 OOC WNS 保持不变，说明 GShare 方向预测结构未被改变。
- 第一次检查脚本按 `RAM64M x6` 预估打包数量，与 Vivado 实际 `x8` 不同；根据 Final Mapping Report 修正断言后重新运行，脚本以 0 error 完成并输出 DCP。
- OOC WNS 不包含新增的 IF 静态分支目标加法器、IFU PC 选择和全工程布线，不能用于预测最终 WNS；必须执行完整综合和实现。

## 移植注意事项

- 条件分支预测现在依赖 IF 阶段指令与 PC 同周期对应；移植时必须保持 `if_inst` 与 `if_pc` 对齐，这与已有静态 JAL 预测要求一致。
- BPU 的 `pred_taken` 只提供动态方向判断，顶层必须用当前指令的 B-type opcode 对其进行门控，不能让陈旧 BTB tag 使非分支指令跳转。
- 条件分支目标必须使用 B-type 立即数格式：`{inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` 并正确符号扩展。
- 以后加入 RAS 时，RAS target 应作为新的预测来源进入 `if_pred_target`，不能重新把直接分支 target 放回 BTB。
