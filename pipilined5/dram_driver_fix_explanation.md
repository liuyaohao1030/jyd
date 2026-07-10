# DRAM Driver Forwarding 修复说明

## 问题根源

原代码的forwarding逻辑存在**时序不匹配**问题：

### 原代码的问题

```systemverilog
assign buf_valid = buf_valid_sr[0];  // 在 cycle N+1 和 N+2 都为1
wire fwd = buf_valid && (bram_addr_rd == bram_addr_r);  // 使用组合逻辑地址
```

### 时序分析（原代码）

假设在 **Cycle N** 有一个 Store Byte 操作（地址 0x1000，数据 0x12，byte enable = 4'b0001）：

| Cycle | dram_wen | buf_valid_sr | buf_valid | bram_addr_rd | bram_dout内容 | forwarding结果 |
|-------|----------|--------------|-----------|--------------|---------------|----------------|
| N     | 1        | 2'b00        | 0         | -            | 其他地址数据  | -              |
| N+1   | 0        | 2'b11        | **1**     | 0x1000       | **其他地址数据**❌ | **错误的fwd_data** |
| N+2   | 0        | 2'b01        | **1**     | 0x1000       | **0x1000旧数据**✓ | 正确的fwd_data |
| N+3   | 0        | 2'b00        | 0         | 0x1000       | 0x1000新数据  | 不forward      |

**问题：**
- 在 Cycle N+1，如果有 Load Word 0x1000，forwarding被触发
- 但 `bram_dout` 包含的是**上一次读操作的地址数据**，不是0x1000的数据！
- 字节级forwarding会使用错误的数据：
  ```systemverilog
  fwd_data[7:0]   = bram_din_r[7:0]    // 0x12 (正确)
  fwd_data[31:8]  = bram_dout[31:8]    // 错误地址的数据！❌
  ```

## 修复方案

### 关键修改点

1. **寄存读地址**，使其与BRAM输出延迟匹配：
   ```systemverilog
   logic [15:0] bram_addr_rd_r;
   always @(posedge clk) begin
       bram_addr_rd_r <= bram_addr_rd;
   end
   ```

2. **延迟forwarding窗口**，只在 `bram_dout` 有效时forward：
   ```systemverilog
   assign buf_valid = buf_valid_sr[0] && !buf_valid_sr[1];  // 只在2'b01时为1
   ```

3. **使用寄存地址比较**：
   ```systemverilog
   wire fwd = buf_valid && (bram_addr_rd_r == bram_addr_r);
   ```

### 修复后的时序

| Cycle | dram_wen | buf_valid_sr | buf_valid | bram_addr_rd | bram_addr_rd_r | bram_dout内容 | forwarding |
|-------|----------|--------------|-----------|--------------|----------------|---------------|------------|
| N     | 1        | 2'b00        | 0         | -            | -              | 其他地址      | 不触发     |
| N+1   | 0        | 2'b11        | **0**     | 0x1000       | -              | 其他地址      | **不触发**✓ |
| N+2   | 0        | 2'b01        | **1**     | -            | 0x1000         | **0x1000旧数据**✓ | **触发**✓ |
| N+3   | 0        | 2'b00        | 0         | -            | -              | 0x1000新数据  | 不触发     |

**现在正确了：**
- Cycle N+1：不触发forwarding，正常从BRAM读取（得到旧数据，但这是Store之后立即Load的情况，需要等1个周期）
- Cycle N+2：触发forwarding，此时 `bram_dout` 包含正确地址的旧数据，字节级混合是正确的！
- Cycle N+3：BRAM已写入完成，直接从BRAM读取新数据

## Store-Load Hazard 处理

### 场景1：Store后立即Load（流水线中相邻指令）

如果CPU流水线允许Store和Load背靠背执行：

```
Cycle N:   Store 地址A (MEM stage)
Cycle N+1: Load 地址A (MEM stage) ← 此时Store还未写入BRAM！
```

**修复后的行为：**
- Cycle N+1: Load请求地址A，但forwarding **不触发**（`buf_valid=0`）
- Load会读到**旧数据**（因为Store还未完成）
- 这意味着**CPU需要在流水线层面处理hazard**（插入stall或用自己的forwarding）

**这是正确的设计！** 因为：
1. DRAM driver的写延迟是2 cycle（设计目标）
2. 如果CPU没有内部forwarding，需要在Store和Load之间插入1个stall
3. 或者CPU可以在EX阶段就进行forwarding（不依赖DRAM driver）

### 场景2：Store后隔1个周期Load

```
Cycle N:   Store 地址A
Cycle N+1: (其他操作)
Cycle N+2: Load 地址A
```

- Cycle N+2: Load请求，forwarding触发✓
- Cycle N+3: 返回正确的混合数据✓

## 为什么要这样修改？

### 原设计（1-cycle写延迟）
- 直接连接，无寄存器
- Store-Load完全依赖CPU的内部forwarding
- 时序路径短但可能违反timing

### 新设计（2-cycle写延迟）
- 寄存器打断关键路径
- DRAM driver提供有限的forwarding（1个周期窗口）
- 需要CPU配合处理相邻指令的hazard

## 测试建议

测试以下场景：

1. **字节写入后字读取**：
   ```assembly
   sb   x1, 0(x2)    # Store byte
   lw   x3, 0(x2)    # Load word (需要forwarding低字节)
   ```

2. **半字写入后字读取**：
   ```assembly
   sh   x1, 0(x2)    # Store half-word
   lw   x3, 0(x2)    # Load word (需要forwarding低半字)
   ```

3. **连续Store-Load同地址**：
   ```assembly
   sw   x1, 0(x2)
   lw   x3, 0(x2)    # 紧邻，可能需要CPU stall
   nop
   lw   x4, 0(x2)    # 隔1周期，forwarding生效
   ```

## 总结

修复的核心是**确保forwarding时 `bram_dout` 包含正确地址的数据**，通过：
1. 寄存读地址（匹配BRAM 1-cycle延迟）
2. 延迟forwarding窗口（只在数据有效时触发）

这样字节级forwarding的混合逻辑才是正确的！
