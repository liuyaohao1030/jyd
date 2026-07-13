# EX1/EX2拆分后程序跑飞 - 完整Bug报告

## 已修复的Bug

### ✅ Bug 1: pipe_ex1_ex2.v的hold逻辑缺失（严重）
**状态**: 已修复
**文件**: pipe_ex1_ex2.v
**修复**: 添加了显式的`else if (ex2_stall)`分支

### ✅ Bug 2: 性能计数器未定义信号（严重）
**状态**: 已修复
**文件**: KLDJ_top.v 第675行
**修复**: `load_use_stall` → `ex1_dependency_stall`

### ✅ Bug 3: 性能计数器错误信号（中等）
**状态**: 已修复
**文件**: KLDJ_top.v 第673-674行
**修复**: 使用正确的`ex1_ex2_valid`和`ex2_stall`

### ✅ Bug 4: 未使用信号清理
**状态**: 已修复
**文件**: KLDJ_top.v
**修复**: 删除未使用的`ex_req_*`信号

## 设计层面的问题（导致性能差但不会跑飞）

### ⚠️ Bug 5: 前递和冒险检测不匹配（设计问题）
**状态**: 设计如此，保守策略
**问题**: 
- ex1_hazard检测EX1依赖EX1/EX2的所有情况
- 但ex_forward只从EX2/MEM前递，不从EX1/EX2前递
- 结果：所有连续依赖都会stall 1拍

**影响**: 性能较差，但功能正确
**是否导致跑飞**: **不会**，只是慢

**为什么这样设计**:
- 避免EX2的组合逻辑（ALU）→ EX1前递，重新形成长路径
- 保守策略：宁可stall也不冒险

## 最可能导致程序跑飞的原因

### 🔴 怀疑Bug 6: ex1_hazard检测x0寄存器依赖
**问题**: ex1_hazard.v检查了`id_ex_rs1_addr != 5'd0`，但没有检查`ex1_ex2_rd_addr != 5'd0`

看第27-28行：
```verilog
wire ex1_ex2_rs1_depend = id_ex_rs1_ren && ex1_ex2_valid && ex1_ex2_wb_ctl &&
                          (id_ex_rs1_addr != 5'd0) && (id_ex_rs1_addr == ex1_ex2_rd_addr);
```

如果`ex1_ex2_rd_addr == 5'd0`（写x0），不应该触发依赖！

**修复**: 应该加上`(ex1_ex2_rd_addr != 5'd0)`

### 🔴 怀疑Bug 7: 前递逻辑没有检查x0
**问题**: ex_forward.v检查前递命中时，没有排除rd=x0的情况

看第46-47行：
```verilog
assign ex_mem_rs1_forward_hit = id_ex_rs1_ren && ex_mem_forward_valid &&
                                (id_ex_rs1_addr == ex_mem_rd_addr);
```

但`ex_mem_forward_valid`的定义（pipe_ex_mem.v第33-34行）：
```verilog
assign ex2_mem_forward_valid = ex2_mem_valid && ex2_mem_wb_ctl && !ex2_mem_load_op &&
                               (ex2_mem_rd_addr != 5'd0);
```

已经排除了x0，所以这个**没问题**。

### 🔴 怀疑Bug 8: 第一条指令如果写x0可能触发错误的stall
如果第一条指令是`addi x0, x0, 0`（NOP），第二条指令读x0，可能触发依赖检测？

**检查irom-v2.coe的前几条指令**！

## 立即需要修复的Bug

### Bug 6 修复：ex1_hazard.v增加rd != x0检查

```verilog
// 修复前
wire ex1_ex2_rs1_depend = id_ex_rs1_ren && ex1_ex2_valid && ex1_ex2_wb_ctl &&
                          (id_ex_rs1_addr != 5'd0) && (id_ex_rs1_addr == ex1_ex2_rd_addr);

// 修复后
wire ex1_ex2_rs1_depend = id_ex_rs1_ren && ex1_ex2_valid && ex1_ex2_wb_ctl &&
                          (id_ex_rs1_addr != 5'd0) && (ex1_ex2_rd_addr != 5'd0) && 
                          (id_ex_rs1_addr == ex1_ex2_rd_addr);
```

同样的修复应用到：
- ex1_ex2_rs2_depend
- ex2_mem_rs1_depend（虽然ex2_mem_wb_ctl已经考虑了load的情况）
- ex2_mem_rs2_depend

## 其他可能的问题

### 检查点1: redirect逻辑
如果第一条指令就触发redirect，会怎样？
- 检查ex_bpu_ctrl是否正确处理
- 检查redirect优先级

### 检查点2: frontend_stall传播
```verilog
assign frontend_stall = ex1_dependency_stall || ex2_stall;
```
如果frontend_stall一直为1，会导致IF/ID一直stall，程序无法推进。

### 检查点3: 复位后的第一个周期
复位后valid应该全0，第一条有效指令应该在第2个周期进入ID。

## 调试建议

### ILA监测信号（按优先级）
1. **if_pc[31:0]** - PC是否卡住
2. **if_id_valid** - 是否有指令进入ID
3. **id_ex_valid** - 是否有指令进入EX1
4. **ex1_ex2_valid** - 是否有指令进入EX2
5. **ex_redirect** - 是否有异常的redirect
6. **frontend_stall** - 是否一直stall
7. **ex1_dependency_stall** - 是否频繁stall
8. **ex2_stall** - MUL/DIV是否卡住

### 仿真建议
运行前5个周期的仿真，逐周期检查：
- 每个流水线寄存器的valid
- PC的值
- 每条指令的内容
- stall和redirect信号

## 总结

**最可能的Bug**: ex1_hazard没有检查`ex1_ex2_rd_addr != x0`
**立即修复**: 在ex1_hazard.v的4个依赖检测中都加上rd != x0的检查
**验证方法**: 重新综合并上板测试

