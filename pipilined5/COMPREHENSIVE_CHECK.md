# EX1/EX2拆分后的全面检查

## 1. Valid信号检查

### ✅ EXU的valid信号
- KLDJ_exu.valid = ex1_ex2_valid ✓

### ✅ CSR的valid门控
- csr_we = csr_we && ex1_ex2_valid ✓
- ecall_en = is_ecall && ex1_ex2_valid ✓
- mret_en = is_mret && ex1_ex2_valid ✓

### ✅ ex_mem_req_ctrl的valid
- ex1_ex2_valid ✓

## 2. 前递信号检查

### ✅ ex_forward的输入
- 从EX2/MEM前递: ex2_mem_rd_addr, ex2_mem_exu_res, ex2_mem_forward_valid ✓
- 从MEM/WB前递: mem_wb_rd_addr, mem_wb_wb_data, mem_wb_forward_valid ✓

### ✅ forward_valid的定义
- ex2_mem_forward_valid = ex2_mem_valid && ex2_mem_wb_ctl && !ex2_mem_load_op && (ex2_mem_rd_addr != 5'd0) ✓
- mem_wb_forward_valid = mem_wb_valid && mem_wb_wb_ctl && (mem_wb_rd_addr != 5'd0) ✓

## 3. 冒险检测检查

### ✅ ex1_hazard的输入
- ID/EX: id_ex_valid, id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rs1_ren, id_ex_rs2_ren ✓
- EX1/EX2: ex1_ex2_valid, ex1_ex2_rd_addr, ex1_ex2_wb_ctl ✓
- EX2/MEM: ex2_mem_valid, ex2_mem_rd_addr, ex2_mem_wb_ctl, ex2_mem_load_op ✓

### ✅ x0检查
- 所有4个依赖检测都检查了 rs != 0 和 rd != 0 ✓

## 4. 流水线寄存器检查

### ✅ pipe_id_ex
- 输入: load_use_stall = ex1_dependency_stall || ex2_stall ✓
- 输入: ex_stall = ex2_stall ✓

### ✅ pipe_ex1_ex2
- 控制: ex_redirect (flush) ✓
- 控制: ex1_dependency_stall (bubble) ✓
- 控制: ex2_stall (hold) ✓
- Hold逻辑: 显式else if分支 ✓

### ✅ pipe_ex_mem
- 输入: ex1_ex2_* ✓
- 输出: ex2_mem_* ✓
- 控制: ex2_stall ✓

### ✅ pipe_mem_wb
- 输入: ex_mem_valid → 应该是ex2_mem_valid！
