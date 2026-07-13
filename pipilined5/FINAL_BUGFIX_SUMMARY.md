# EX1/EX2拆分Bug修复完整总结

## 已修复的所有Bug

### ✅ Bug 1: pipe_ex1_ex2.v的hold逻辑缺失（严重）
**文件**: `pipe_ex1_ex2.v`
**问题**: MUL/DIV多周期时，控制信号没有显式hold逻辑
**修复**: 在两个always块中都添加了`else if (ex2_stall)`分支

### ✅ Bug 2: 性能计数器未定义信号（严重）
**文件**: `KLDJ_top.v` 第675行
**问题**: 使用不存在的`load_use_stall`信号
**修复**: 改为`ex1_dependency_stall`

### ✅ Bug 3: 性能计数器load/store信号错误（中等）
**文件**: `KLDJ_top.v` 第673-674行
**问题**: 使用`id_ex_valid`和`ex_stall`以及未定义的`ex_req_load/store`
**修复**: 改为使用`ex1_ex2_valid`、`ex2_stall`和直接的exu_op判断

### ✅ Bug 4: 未使用的信号定义清理
**文件**: `KLDJ_top.v` 第190-196行
**问题**: 定义了`ex_req_load`等信号但从未赋值
**修复**: 已删除这些未使用的信号定义

## 关键修改对比

### pipe_ex1_ex2.v
```verilog
// 修复前 - 隐式hold
end else if (!ex2_stall) begin
    ex1_ex2_valid <= id_ex_valid;
    ...
end
// else: 注释说明hold

// 修复后 - 显式hold
end else if (ex2_stall) begin
    // hold when ex2_stall (keep current values)
end else begin
    ex1_ex2_valid <= id_ex_valid;
    ...
end
```

### KLDJ_top.v性能计数器
```verilog
// 修复前
wire perf_event_load_use_stall = load_use_stall;  // ❌ 未定义
wire perf_event_load  = id_ex_valid && !ex_stall && ex_req_load;  // ❌ 错误阶段
wire perf_event_store = id_ex_valid && !ex_stall && ex_req_store; // ❌ 错误阶段

// 修复后
wire perf_event_load_use_stall = ex1_dependency_stall;  // ✅
wire perf_event_load  = ex1_ex2_valid && !ex2_stall && 
                        ((ex1_ex2_exu_op >= 18'h1d) && (ex1_ex2_exu_op <= 18'h21));  // ✅
wire perf_event_store = ex1_ex2_valid && !ex2_stall && 
                        ((ex1_ex2_exu_op >= 18'h22) && (ex1_ex2_exu_op <= 18'h24));  // ✅
```

## 验证清单

### 编译验证
- [ ] Vivado综合无警告/错误
- [ ] 检查是否有latch警告
- [ ] 时序约束满足

### 功能验证
- [ ] 第一条指令正确执行（PC=0x80000000的指令）
- [ ] 简单ALU指令序列正确
- [ ] 分支跳转正确
- [ ] Load/Store正确
- [ ] MUL/DIV多周期指令正确

### 上板测试
- [ ] 程序不再跑飞
- [ ] 计数器正常工作
- [ ] 性能符合预期

## 如果仍然有问题，检查以下内容

1. **PC初始化**: 确认PC从0x80000000开始
2. **复位逻辑**: 确认reset信号正确
3. **指令存储器**: 确认irom-v2.coe正确加载
4. **redirect信号**: 使用ILA监测是否有异常redirect
5. **valid传播**: 监测valid信号是否正确传播通过6级流水线

## 建议的ILA监测信号

```tcl
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets core_clk]

# 关键信号
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets if_pc[*]]

set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets id_ex_valid]

set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets ex1_ex2_valid]

set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets ex2_mem_valid]

set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets ex_redirect]

set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets ex1_dependency_stall]

set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets ex2_stall]
```

## 修改文件列表

1. ✅ **pipe_ex1_ex2.v** - 添加显式hold逻辑
2. ✅ **KLDJ_top.v** - 修复性能计数器信号和清理未使用信号

## 预期行为

### 正常执行流程
```
周期1: IF取指, ID=NOP, EX1=NOP, EX2=NOP, MEM=NOP, WB=NOP
周期2: IF取指, ID=第1条指令, EX1=NOP, EX2=NOP, MEM=NOP, WB=NOP
周期3: IF取指, ID=第2条指令, EX1=第1条指令, EX2=NOP, MEM=NOP, WB=NOP
...
```

### 多周期指令（MUL/DIV）
```
MUL开始执行:
周期N:   EX1=后续指令, EX2=MUL(开始), ex2_stall=1
周期N+1: EX1=hold,     EX2=MUL(继续), ex2_stall=1
周期N+2: EX1=hold,     EX2=MUL(完成), ex2_stall=0
周期N+3: EX1=后续指令推进, EX2=下一条指令
```

## 重要提醒

所有修复都已完成，现在应该：
1. 重新综合实现
2. 生成比特流
3. 上板测试

如果还有问题，使用ILA监测关键信号定位具体哪个阶段出错。
