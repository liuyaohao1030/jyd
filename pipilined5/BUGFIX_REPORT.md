# EX1/EX2拆分后程序跑飞问题修复报告

## 发现的关键Bug

### Bug 1: pipe_ex1_ex2.v的hold逻辑缺失 ⚠️ **严重**
**问题**: 当`ex2_stall`时（MUL/DIV多周期），第一个always块缺少显式的hold分支
**影响**: 多周期指令执行时，valid等控制信号可能被错误更新
**修复**: 在两个always块中都添加了`else if (ex2_stall)`分支进行显式hold

```verilog
// 修复前
end else if (!ex2_stall) begin
    // update
end
// else: 隐式hold（注释说明）

// 修复后
end else if (ex2_stall) begin
    // 显式hold，保持当前值
end else begin
    // update
end
```

### Bug 2: 性能计数器使用未定义信号 ⚠️ **严重**
**问题**: 第675行使用`load_use_stall`信号，但该信号已不存在
**影响**: 编译错误或综合时未连接信号
**修复**: 改为`ex1_dependency_stall`

```verilog
// 修复前
wire perf_event_load_use_stall = load_use_stall;

// 修复后
wire perf_event_load_use_stall = ex1_dependency_stall;
```

### Bug 3: 性能计数器使用错误的阶段信号 ⚠️ **中等**
**问题**: load/store计数器使用`id_ex_valid`和`ex_stall`，但这些信号在拆分后语义改变
**影响**: 性能统计不准确，可能引用未定义信号`ex_req_load/ex_req_store`
**修复**: 改为使用`ex1_ex2_valid`和`ex2_stall`

```verilog
// 修复前
wire perf_event_load  = id_ex_valid && !ex_stall && ex_req_load;
wire perf_event_store = id_ex_valid && !ex_stall && ex_req_store;

// 修复后
wire perf_event_load  = ex1_ex2_valid && !ex2_stall && ((ex1_ex2_exu_op >= 18'h1d) && (ex1_ex2_exu_op <= 18'h21));
wire perf_event_store = ex1_ex2_valid && !ex2_stall && ((ex1_ex2_exu_op >= 18'h22) && (ex1_ex2_exu_op <= 18'h24));
```

## 其他潜在问题检查

### ✅ EXU的valid信号连接
- 已正确改为`ex1_ex2_valid`
- 位置：KLDJ_top.v 第476行

### ✅ CSR的valid门控
- 已正确改为`ex1_ex2_valid`
- 位置：KLDJ_top.v 第552, 555, 557行

### ✅ 前递信号连接
- ex_forward从EX2/MEM前递：使用`ex2_mem_rd_addr`和`ex2_mem_exu_res`
- 位置：KLDJ_top.v 第409-411行

### ✅ BPU更新信号
- 已正确改为从`ex1_ex2_*`读取
- 位置：ex_bpu_ctrl.v

### ✅ 内存请求控制
- 已正确改为使用`ex1_ex2_valid`和`ex2_stall`
- 位置：ex_mem_req_ctrl.v

## 修复后的文件列表

1. **pipe_ex1_ex2.v** - 添加显式hold逻辑
2. **KLDJ_top.v** - 修复性能计数器信号

## 建议的测试步骤

1. **重新编译综合**
   ```bash
   # 检查是否有未定义信号
   vivado -mode batch -source build.tcl
   ```

2. **仿真测试**
   - 重点测试MUL/DIV指令（多周期stall场景）
   - 检查第一条指令是否能正确执行
   - 验证跳转和分支是否正确

3. **上板验证**
   - 观察第一个指令的执行
   - 使用ChipScope/ILA监测关键信号
   
## 关键信号监测建议

如果仍然跑飞，建议监测：
- `if_pc` - PC是否正常递增
- `id_ex_valid` - ID/EX寄存器valid
- `ex1_ex2_valid` - EX1/EX2寄存器valid
- `ex2_mem_valid` - EX2/MEM寄存器valid
- `ex_redirect` - 是否有错误的redirect
- `ex1_dependency_stall` - stall是否过于频繁
- `ex2_stall` - 多周期指令是否正常

