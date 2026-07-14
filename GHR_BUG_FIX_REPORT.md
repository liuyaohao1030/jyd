# CPU跑飞Bug修复报告 - GHR恢复问题

## 问题描述
六级流水线CPU在FPGA上板后一直"跑飞"（run away），无法正常执行程序。

## 根本原因

### **GHR（Global History Register）在分支预测错误时没有恢复机制**

这是一个**gshare分支预测器的关键bug**：

#### Gshare工作原理
```
PHT_index = PC_index XOR GHR
```
- GHR记录最近的分支历史（taken=1, not-taken=0）
- 每次分支执行后，GHR左移并追加新的结果：`ghr <= {ghr[4:0], taken}`

#### Bug场景

```
时间轴：分支预测错误导致GHR被污染

T0: GHR = 000000
    Branch1 @ IF，预测taken
    
T1: GHR = 000000（还未更新）
    Branch1 @ ID
    Branch2 @ IF，使用GHR=000000预测
    
T2: GHR = 000000
    Branch1 @ EX1
    Branch2 @ ID
    Branch3 @ IF，使用GHR=000000预测
    
T3: GHR = 000000
    Branch1 @ EX2，检测到预测错误！实际是not-taken
    产生 ex_redirect = 1
    Branch2 @ EX1
    Branch3 @ ID
    
T4: GHR = 000001（更新了Branch1的结果，但是错误的！）
    ❌ 问题：GHR被投机更新污染了
    ❌ Branch2和Branch3是错误路径，它们的预测基于错误的GHR
    新指令 @ IF，使用错误的GHR=000001查询PHT
    
T5: GHR = 000011（继续被污染）
    所有后续分支预测都基于错误的GHR
    导致预测准确率暴跌
    CPU不断redirect，完全"跑飞"！
```

#### 为什么会导致跑飞？

1. **错误的GHR导致错误的PHT索引**
   - 原本应该查询PHT[index=5]，现在查询PHT[index=7]
   - 得到完全不相关的预测结果

2. **雪崩效应**
   - 第一次预测错误 → GHR被污染
   - 后续所有预测都基于错误的GHR → 持续预测错误
   - 每次错误又进一步污染GHR → 恶性循环

3. **表现症状**
   - 分支预测准确率接近0
   - 频繁的流水线flush
   - PC跳来跳去，程序无法正常执行
   - ILA观察到ex_redirect信号频繁拉高

## 修复方案

### 核心思路

在分支预测错误时，**恢复GHR到正确的值**。

#### 方法：使用流水线中保存的pred_pht_idx

代码中已经在流水线各级保存了`pred_pht_idx`：
- `if_pred_pht_idx` - IF阶段保存
- `if_id_pred_pht_idx` - ID阶段保存
- `id_ex_pred_pht_idx` - EX1阶段保存
- `ex1_ex2_pred_pht_idx` - EX2阶段保存

`pred_pht_idx`的值就是当时查询PHT时使用的索引：
```verilog
pred_pht_idx = PC_index XOR GHR_at_fetch_time
```

当分支在EX2检测到预测错误时，`ex1_ex2_pred_pht_idx`包含了该分支取指时的GHR信息。

#### GHR恢复公式

```
原始关系：pred_pht_idx = btb_idx ^ ghr_old
因此：   ghr_old = pred_pht_idx ^ btb_idx

恢复到分支执行后的GHR：
ghr_recovered = pred_pht_idx ^ update_btb_idx
```

其中`update_btb_idx = update_pc[INDEX_WIDTH+1:2]`是分支指令的PC索引。

### 代码修改

#### 1. 修改 `bpu.v` - 添加redirect信号

```verilog
module bpu #(
     parameter INDEX_WIDTH     = 6
    ,parameter BHT_RESET_VALUE = 2'b01
)(
     input  wire                  clk
    ,input  wire                  rst
    // ... 其他信号 ...
    
    // 新增：Redirect recovery
    ,input  wire                  redirect
    ,input  wire [INDEX_WIDTH-1:0] redirect_pht_idx
);
```

#### 2. 修改 `gshare_btb_core` - 添加GHR恢复逻辑

```verilog
always @(posedge clk) begin
    if(rst == `KLDJ_RSTABLE) begin
        ghr       <= {INDEX_WIDTH{1'b0}};
        pht_valid <= {ENTRY_NUM{1'b0}};
        btb_valid <= {ENTRY_NUM{1'b0}};
    end else if(redirect) begin
        // 新增：在分支预测错误时恢复GHR
        // redirect_pht_idx是分支取指时保存的PHT索引
        // 通过XOR恢复原始GHR
        ghr <= redirect_pht_idx ^ update_btb_idx;
    end else if(update_valid) begin
        // 正常更新逻辑
        pht[update_pht_idx]       <= update_pht_next;
        pht_valid[update_pht_idx] <= 1'b1;
        if(update_taken) begin
            btb_valid[update_btb_idx]  <= 1'b1;
            btb_data[update_btb_idx]   <= {update_tag, update_target};
        end
        ghr <= {ghr[INDEX_WIDTH-2:0], update_taken};
    end
end
```

**关键点**：
- `redirect`的优先级高于`update_valid`
- 当redirect和update_valid同时有效时，先恢复GHR，不执行正常更新
- 这样可以立即修正被污染的GHR

#### 3. 修改 `KLDJ_top.v` - 连接信号

```verilog
bpu #(
     .INDEX_WIDTH  (BPU_INDEX_WIDTH)
) u_bpu(
    .clk          (core_clk          )
    ,.rst          (core_rst          )
    // ... 其他信号 ...
    ,.redirect     (ex_redirect       )          // 新增
    ,.redirect_pht_idx(ex1_ex2_pred_pht_idx)    // 新增
);
```

## 修复后的行为

```
时间轴：GHR正确恢复

T0-T3: 同上，Branch1在EX2检测到预测错误

T4: ex_redirect = 1
    BPU收到redirect信号
    GHR恢复：ghr <= redirect_pht_idx ^ update_btb_idx
    ✅ GHR被正确恢复到Branch1之前的状态
    新指令 @ IF，使用正确的GHR查询PHT
    
T5: GHR基于正确的历史
    后续分支预测准确率恢复正常
    CPU正常执行
```

## 修改的文件

1. `pipilined5/kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`
   - 添加`redirect`和`redirect_pht_idx`输入端口
   - 在GHR更新逻辑中添加redirect处理分支

2. `pipilined5/kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v`
   - 连接`ex_redirect`到BPU的`redirect`
   - 连接`ex1_ex2_pred_pht_idx`到BPU的`redirect_pht_idx`

## 测试建议

### 1. 仿真测试

创建包含多个分支的测试程序：

```asm
0x80000000: addi x1, x0, 0
0x80000004: addi x2, x0, 10
loop:
0x80000008: addi x1, x1, 1      # x1++
0x8000000c: blt  x1, x2, loop   # if(x1 < 10) goto loop
0x80000010: ...                  # 继续执行
```

观察：
- 分支预测错误发生时，GHR是否正确恢复
- redirect后的第一条新指令是否使用了正确的GHR
- 分支预测准确率是否正常

### 2. ILA调试信号

添加以下信号到ILA：
```verilog
(* mark_debug = "true" *) wire ex_redirect;
(* mark_debug = "true" *) wire [5:0] ghr;                    // 需要在bpu.v中导出
(* mark_debug = "true" *) wire [5:0] ex1_ex2_pred_pht_idx;
(* mark_debug = "true" *) wire [31:0] if_pc;
(* mark_debug = "true" *) wire bpu_pred_taken;
```

观察：
- 每次`ex_redirect=1`时，下一个周期GHR的值
- GHR是否回到了正确的历史状态

### 3. FPGA验证

1. 重新综合、实现、生成比特流
2. 上板运行之前"跑飞"的程序
3. 观察：
   - 程序是否能正常运行到结束
   - LED/数码管输出是否正确
   - UART输出是否符合预期

### 4. 性能测试

使用包含大量分支的benchmark测试：
- 统计分支预测准确率（通过性能计数器）
- 对比修复前后的IPC（Instructions Per Cycle）
- 应该看到显著的性能提升

## 为什么之前没发现这个Bug？

1. **仿真环境可能测试用例简单**
   - 短程序、少分支，GHR污染影响不明显
   - 可能只跑了几十条指令就结束

2. **症状可能被误判**
   - "跑飞"的症状很多：PC错误、死循环、异常跳转等
   - 容易先怀疑其他更"明显"的问题

3. **Gshare的复杂性**
   - GHR是投机状态，需要恢复机制
   - 这在教科书中经常被简化或省略
   - 不熟悉gshare实现细节容易遗漏

## 关键教训

### 设计分支预测器时的要点

1. **投机状态需要恢复机制**
   - GHR、RAS（Return Address Stack）等都是投机更新的
   - 必须在预测错误时恢复到正确状态

2. **在流水线中保存预测信息**
   - 保存取指时的预测结果（taken/not-taken）
   - 保存预测时使用的索引（PHT index、GHR snapshot等）
   - 这些信息用于EX阶段的更新和恢复

3. **优先级设计**
   - `redirect`优先级应高于`update`
   - 避免在同一周期既恢复又更新导致错误

4. **测试用例**
   - 需要包含连续多个分支的测试
   - 需要覆盖预测错误的场景
   - 长时间运行测试（几千条指令以上）

## 下一步

1. **重新综合并上板测试**
2. **如果还有问题**，检查：
   - 复位逻辑
   - 时序约束
   - 其他流水线控制信号
3. **性能优化**（修复后）：
   - 调整BHT_RESET_VALUE
   - 增大BTB/PHT容量
   - 考虑添加RAS（Return Address Stack）

---

**修复完成时间**：请在此记录上板测试结果和时间

**测试结果**：
- [ ] 仿真测试通过
- [ ] FPGA上板测试通过
- [ ] 性能符合预期

**备注**：
