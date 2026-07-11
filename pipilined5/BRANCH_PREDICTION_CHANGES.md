# 分支预测功能实现总结

## 概述
在原有五级流水线 RISC-V 处理器核心的基础上，成功添加了基于 **Gshare + BTB** 的分支预测机制，以及 **JAL 冷启动静态预测**功能。

## 新增文件

### 1. `kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`
- **分支预测单元 (Branch Prediction Unit)**
- 包含两个模块：
  - `bpu`: 顶层封装模块
  - `gshare_btb_core`: Gshare + BTB 核心实现
- **关键特性**：
  - 6位索引宽度 (64项)
  - Gshare 算法：PHT 索引 = BTB 索引 XOR 全局历史寄存器 (GHR)
  - 2位饱和计数器 (初始值 2'b01 - 弱不跳转)
  - BTB 包含：valid位、tag、目标地址
  - 在 EX 阶段更新 GHR 和 PHT

### 2. `kldj.srcs2/sources_1/imports/rtl/pipe/ex_bpu_ctrl.v`
- **EX 阶段 BPU 控制模块**
- **功能**：
  - 检测分支预测错误（方向错误或目标地址错误）
  - 生成重定向信号 `ex_redirect`
  - 计算正确的 PC (`ex_correct_pc`)
  - 生成 BPU 更新信号（仅针对分支和 JAL 指令）
  - 支持 ECALL/MRET 异常处理

### 3. `kldj.srcs2/sources_1/imports/rtl/pipe/ex_mem_req_ctrl.v`
- **EX 阶段内存请求控制模块**
- **功能**：
  - 将原来 KLDJ_top.v 中的内存请求逻辑独立为单独模块
  - 在 EX 阶段生成 BRAM 访问信号（地址、数据、写使能、字节使能）
  - 支持双端口 BRAM 接口

### 4. `kldj.srcs2/sources_1/imports/rtl/pipe/ex_forward.v`
- **EX 阶段数据前递模块**（恢复已删除的文件）
- **功能**：
  - EX/MEM → EX 前递
  - MEM/WB → EX 前递
  - Load-Use 冒险检测

## 修改的文件

### 1. `kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_ifu.v`
**修改内容**：
- 将原来的 `jump` 和 `jump_pc` 信号改为 `redirect` 和 `redirect_pc`
- 新增输入：`pred_taken` 和 `pred_target`（来自分支预测）
- **PC 更新逻辑**：
  ```verilog
  assign dnpc = pred_taken ? pred_target : snpc;
  ```
  - 优先使用重定向 PC（预测错误时）
  - 其次使用预测 PC（预测跳转时）
  - 默认使用顺序 PC (snpc = pc + 4)

### 2. `kldj.srcs2/sources_1/imports/rtl/pipe/pipe_if_id.v`
**修改内容**：
- 添加参数：`BPU_INDEX_WIDTH = 6`
- 新增预测信息的输入输出：
  - `if_pred_taken`: 预测是否跳转
  - `if_pred_target`: 预测目标地址
  - `if_pred_pht_idx`: PHT 索引（用于后续更新）
- **时序优化**：将 valid 和 pred_taken 单独打一拍，其他数据另外打一拍

### 3. `kldj.srcs2/sources_1/imports/rtl/pipe/pipe_id_ex.v`
**修改内容**：
- 添加参数：`BPU_INDEX_WIDTH = 6`
- 传递预测信息到 EX 阶段：
  - `id_ex_pred_taken`
  - `id_ex_pred_target`
  - `id_ex_pred_pht_idx`
- 在 `ex_redirect` 或 `load_use_stall` 时清除预测信息
- 在 `ex_stall` 时保持预测信息不变

### 4. `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v`
**主要修改**：

#### a. 参数定义
```verilog
localparam BPU_INDEX_WIDTH = 6;
```

#### b. IF 阶段信号
新增：
- BPU 预测信号：`bpu_pred_taken`, `bpu_pred_target`, `if_pred_pht_idx`, `if_btb_hit`
- JAL 静态预测信号：`if_static_jal`, `if_static_jal_imm`, `if_static_jal_target`
- 最终预测信号：`if_pred_taken`, `if_pred_target`

#### c. IF/ID 流水线寄存器信号
新增：`if_id_pred_taken`, `if_id_pred_target`, `if_id_pred_pht_idx`

#### d. ID/EX 流水线寄存器信号
新增：`id_ex_pred_taken`, `id_ex_pred_target`, `id_ex_pred_pht_idx`

#### e. EX 阶段信号
新增：
- `ex_actual_taken`: 实际是否跳转
- `ex_correct_pc`: 正确的 PC
- BPU 更新信号：`bpu_update_valid`, `bpu_update_pc`, `bpu_update_pht_idx`, `bpu_update_taken`, `bpu_update_target`

#### f. JAL 冷启动静态预测逻辑
```verilog
// IF-stage static JAL prediction
assign if_static_jal        = (if_inst[6:2] == `KLDJ_JAL) && (if_inst[1:0] == 2'b11);
assign if_static_jal_imm    = {{12{if_inst[31]}}, if_inst[19:12], if_inst[20], if_inst[30:21], 1'b0};
assign if_static_jal_target = if_pc + if_static_jal_imm;
assign if_pred_taken        = if_static_jal || bpu_pred_taken;
assign if_pred_target       = if_static_jal ? if_static_jal_target : bpu_pred_target;
```
**设计思想**：JAL 是无条件跳转，指令中编码的目标地址比可能过时的 BTB 更可靠，因此 JAL 的静态预测优先级高于 BPU 预测。

#### g. 模块实例化
1. **BPU 模块**
2. **IFU 模块**：连接预测信号
3. **IF/ID 流水线寄存器**：传递预测信息
4. **ID/EX 流水线寄存器**：传递预测信息
5. **ex_bpu_ctrl 模块**：生成重定向和 BPU 更新信号
6. **ex_mem_req_ctrl 模块**：替换原来的内存请求逻辑

#### h. 重定向逻辑简化
- 原来：`ex_redirect = id_ex_valid && (exu_jump_raw || is_ecall);`
- 现在：由 `ex_bpu_ctrl` 模块统一生成，考虑了预测错误的情况

#### i. 输出信号修改
```verilog
assign tb_ex_jump_pc = ex_redirect ? ex_correct_pc : `KLDJ_ZERO32;
```

## 工作原理

### 1. IF 阶段
1. **BPU 查表**：使用当前 PC 查询 BTB 和 PHT
   - BTB 索引 = PC[INDEX_WIDTH+1:2]
   - PHT 索引 = BTB 索引 XOR GHR
2. **JAL 检测**：检查指令是否为 JAL，如果是则计算静态目标
3. **预测决策**：
   - JAL 优先：if_pred_taken = if_static_jal || bpu_pred_taken
   - 目标优先：if_pred_target = if_static_jal ? if_static_jal_target : bpu_pred_target
4. **PC 更新**：dnpc = pred_taken ? pred_target : snpc

### 2. ID 阶段
- 预测信息随指令通过流水线传递

### 3. EX 阶段
1. **实际跳转计算**：EXU 计算实际跳转条件和目标
2. **预测验证**（ex_bpu_ctrl）：
   - **方向错误**：预测跳转但实际不跳，或预测不跳但实际跳
   - **目标错误**：预测跳转且实际跳转，但目标地址不一致
3. **重定向**：如果预测错误，flush IF 和 ID 阶段，PC 跳转到正确地址
4. **BPU 更新**：
   - 仅对分支指令和 JAL 指令更新
   - 更新 PHT（2位饱和计数器）
   - 如果实际跳转，更新 BTB（valid、tag、target）
   - 更新 GHR（移位寄存器）

### 4. 性能优化点
1. **静态 JAL 预测**：避免 BTB 冷启动问题
2. **Gshare 算法**：利用全局历史提高预测精度
3. **提前预测**：IF 阶段就完成预测，不引入额外 stall
4. **EX 阶段验证**：最小化预测错误的代价（2个周期的 bubble）

## 时序考虑

### 关键路径分析
1. **BPU 查表**：
   - BTB 查询：索引 → SRAM 读 → tag 比较 → hit 信号
   - PHT 查询：索引 XOR GHR → SRAM 读 → 取最高位
   - **时序**：需要在一个周期内完成，可能成为关键路径

2. **JAL 检测**：
   - 指令解码 → 立即数提取 → 加法器
   - **优化**：与 BPU 查表并行进行

3. **预测 MUX**：
   - JAL 优先级 MUX → 最终预测信号
   - **延迟**：1级 MUX

### 时序优化策略（参考实现）
1. **IF/ID 寄存器分离打拍**：
   - valid 和 pred_taken 单独打拍
   - 其他数据另外打拍
   - 避免关键路径过长

2. **ID/EX 寄存器分离打拍**：
   - 控制信号（valid, pred_taken, ren, wb_ctl, csr_op）单独打拍
   - 数据通路另外打拍
   - 在 load_use_stall 时只清零 exu_op 等控制信号

## 功能验证要点

### 1. 基本分支预测
- [ ] 分支指令首次执行（BTB miss，预测不跳）
- [ ] 分支指令多次执行（BTB hit，PHT 更新）
- [ ] 分支方向预测正确
- [ ] 分支方向预测错误（验证 flush 机制）

### 2. JAL 静态预测
- [ ] JAL 指令首次执行（不依赖 BTB）
- [ ] JAL 指令目标地址计算正确
- [ ] JAL 优先级高于 BPU 预测

### 3. 异常处理
- [ ] ECALL 触发重定向到 mtvec
- [ ] MRET 返回到 mepc
- [ ] 异常期间 BPU 不更新

### 4. 流水线冲突
- [ ] Load-Use stall 期间保持预测信息
- [ ] Mul/Div stall 期间保持预测信息
- [ ] 预测错误 flush 与 stall 的交互

### 5. 边界情况
- [ ] 连续分支指令
- [ ] 分支目标为分支指令
- [ ] 分支延迟槽（RISC-V 无延迟槽，但要确认）

## 综合与时序收敛建议

1. **如果 BPU 查表时序不收敛**：
   - 减小 INDEX_WIDTH（从 6 降到 5 或 4）
   - 在 IF 阶段流水化 BPU（增加一级）
   - 使用分布式 RAM 而不是块 RAM

2. **如果 JAL 检测路径不收敛**：
   - 在 IF/ID 寄存器后再进行 JAL 检测
   - 接受 JAL 的预测延迟 1 个周期

3. **资源使用**：
   - BPU：64项 × (1bit valid + 24bit tag + 32bit target + 2bit PHT) ≈ 3.7 Kb
   - GHR：6 bit 寄存器
   - 额外逻辑：比较器、加法器、MUX

## 文件清单

### 新增文件 (4个)
1. `kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`
2. `kldj.srcs2/sources_1/imports/rtl/pipe/ex_bpu_ctrl.v`
3. `kldj.srcs2/sources_1/imports/rtl/pipe/ex_mem_req_ctrl.v`
4. `kldj.srcs2/sources_1/imports/rtl/pipe/ex_forward.v`（恢复）

### 修改文件 (4个)
1. `kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_ifu.v`
2. `kldj.srcs2/sources_1/imports/rtl/pipe/pipe_if_id.v`
3. `kldj.srcs2/sources_1/imports/rtl/pipe/pipe_id_ex.v`
4. `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v`

### 备份文件
- `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v.backup`（原始顶层文件备份）

## 下一步工作

1. **仿真验证**：
   - 编写针对分支预测的 testbench
   - 运行现有的 CPU 测试用例，确保功能正确

2. **综合实现**：
   - 在 Vivado 中综合设计
   - 检查时序报告
   - 根据需要进行时序优化

3. **上板测试**：
   - 烧录到 FPGA
   - 运行实际程序
   - 测量性能提升

4. **性能分析**（可选）：
   - 添加性能计数器（预测准确率、BTB 命中率等）
   - 分析不同程序的预测效果

## 参考资料
- 参考实现：`kldj.srcs2/Gshare_refcode/`
- Gshare 算法原论文
- RISC-V 指令集手册
