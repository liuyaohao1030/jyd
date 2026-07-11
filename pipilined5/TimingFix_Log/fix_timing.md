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
