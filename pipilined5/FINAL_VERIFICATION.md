# EX1/EX2拆分最终验证报告

## 全面检查结果：✅ 所有信号连接正确

### 1. ✅ Valid信号传播链
```
if_id_valid → id_ex_valid → ex1_ex2_valid → ex2_mem_valid → mem_wb_valid
```
- KLDJ_exu.valid = ex1_ex2_valid ✓
- KLDJ_csr门控 = ex1_ex2_valid ✓
- ex_mem_req_ctrl.valid = ex1_ex2_valid ✓
- pipe_mem_wb.ex_mem_valid = ex2_mem_valid ✓
- mem_stage_top.ex_mem_valid = ex2_mem_valid ✓

### 2. ✅ 前递路径
```
EX2/MEM → EX1: ex2_mem_rd_addr, ex2_mem_exu_res, ex2_mem_forward_valid
MEM/WB → EX1:  mem_wb_rd_addr, mem_wb_wb_data, mem_wb_forward_valid
```
- ex2_mem_forward_valid检查了!load && rd!=0 ✓
- mem_wb_forward_valid检查了rd!=0 ✓

### 3. ✅ 冒险检测
```
ex1_hazard检测：
  - EX1依赖EX2 (ex1_ex2): 所有情况都stall
  - EX1依赖MEM (ex2_mem): 只检测load
```
- 检查了rs1/rs2 != 0 ✓
- 检查了rd != 0 ✓（已修复Bug 5）

### 4. ✅ Stall信号
```
ex2_stall = div_stall || mul_stall
frontend_stall = ex1_dependency_stall || ex2_stall
```
- pipe_id_ex.load_use_stall = frontend_stall ✓
- pipe_id_ex.ex_stall = ex2_stall ✓

### 5. ✅ 流水线寄存器控制逻辑
- pipe_id_ex: redirect > (dependency_stall||ex2_stall) > !ex2_stall ✓
- pipe_ex1_ex2: redirect > dependency_stall > ex2_stall > else ✓
- pipe_ex_mem: ex2_stall插入bubble ✓

### 6. ✅ 信号命名一致性
所有ex_mem_*已重命名为ex2_mem_*:
- ex2_mem_valid ✓
- ex2_mem_pc ✓
- ex2_mem_rd_addr ✓
- ex2_mem_exu_res ✓
- ex2_mem_forward_valid ✓

### 7. ✅ 性能计数器
- perf_event_load_use_stall = ex1_dependency_stall ✓
- perf_event_load = ex1_ex2_valid && !ex2_stall && (exu_op判断) ✓
- perf_event_store = ex1_ex2_valid && !ex2_stall && (exu_op判断) ✓

## 已修复的所有Bug

### Bug 1: pipe_ex1_ex2.v hold逻辑 ✅
添加了显式的`else if (ex2_stall)`分支

### Bug 2: 性能计数器未定义信号 ✅
load_use_stall → ex1_dependency_stall

### Bug 3: 性能计数器错误信号 ✅
改用ex1_ex2_valid和ex2_stall

### Bug 4: 未使用信号 ✅
删除ex_req_*信号定义

### Bug 5: x0寄存器检查缺失 ✅ ⭐
在ex1_hazard的4个依赖检测中都加上了rd != 0

### Bug 6: 前递策略保守 ⚠️
设计取舍，保持保守策略

## 潜在问题排查

### 检查项1: 复位行为
- ✅ 所有流水线寄存器在reset时valid=0
- ✅ PC初始化为0x80000000
- ✅ 复位优先级最高

### 检查项2: Redirect处理
- ✅ redirect时flush IF/ID/EX1三级
- ✅ 产生redirect的指令继续推进
- ✅ redirect优先级高于stall

### 检查项3: MUL/DIV多周期
- ✅ ex2_stall时EX1/EX2 hold
- ✅ ID/EX也hold（通过ex_stall信号）
- ✅ IF/ID也hold（通过frontend_stall）

### 检查项4: Load-Use
- ✅ ex1_hazard检测load依赖
- ✅ stall后从ex2_mem或mem_wb前递
- ✅ 前递valid正确排除load

### 检查项5: Store数据前递
- ✅ ex_forward处理store的rs2前递
- ✅ ex1_store_wdata正确传递到EX2

## 最终结论

**状态**: ✅ 所有已知Bug已修复，信号连接检查完毕

**关键修复**: Bug 5（x0寄存器依赖检测）最可能是导致程序跑飞的原因

**测试建议**:
1. 重新综合，检查无错误/警告
2. 上板测试irom-v2.coe
3. 如果仍有问题，使用ILA监测if_pc和frontend_stall

**预期行为**:
- PC应该从0x80000000开始正常递增
- 计数器应该正常工作
- 程序不应该卡死或跑飞

