# DRAM Driver Forwarding 修复方案 V2（优化版）

## 问题回顾

原始代码的forwarding在**部分字节写入**场景下使用了错误的`bram_dout`：

```systemverilog
// 原代码问题
wire fwd = buf_valid && (bram_addr_rd == bram_addr_r);
assign fwd_data[7:0] = bram_we_r[0] ? bram_din_r[7:0] : bram_dout[7:0];  // bram_dout可能是错误地址！
```

## 关键洞察

**并非所有写操作都需要等待`bram_dout`有效！**

### 场景分类

1. **整字写入（SW, bram_we_r = 4'b1111）**
   - 所有4个字节都来自`bram_din_r`
   - **不需要**`bram_dout`
   - 可以在cycle N+1（最早）就forward ✓

2. **部分字节写入（SB/SH, bram_we_r ≠ 4'b1111）**
   - 部分字节来自`bram_din_r`，其余字节来自`bram_dout`
   - **需要**正确的`bram_dout`
   - 必须在cycle N+2才能forward ✓

## 优化方案：两阶段Forwarding

```systemverilog
wire is_full_word_write = (bram_we_r == 4'b1111);

// 早期forward (cycle N+1): 仅全字写入
wire fwd_early = buf_valid && buf_valid_sr[1] && is_full_word_write && (bram_addr_rd == bram_addr_r);

// 正常forward (cycle N+2): 所有写入
wire fwd_normal = buf_valid && !buf_valid_sr[1] && (bram_addr_rd_r == bram_addr_r);

wire fwd = fwd_early || fwd_normal;
```

## 时序分析

### 场景1：整字写入 (SW) 后立即读取 (LW)

```
Cycle N:   sw x1, 0(x2)     dram_wen=1, bram_we_r将在N+1变成4'b1111
Posedge N+1: 捕获store, buf_valid_sr = 2'b11
Cycle N+1: lw x3, 0(x2)     
           bram_addr_rd = addr
           fwd_early = 1 && 1 && 1 && 1 = 1  ✓
           返回 bram_din_r (全部4字节)  ✓
Posedge N+2: buf_valid_sr = 2'b01, bram_addr_rd_r = addr
Cycle N+2: (如果再次读取)
           fwd_normal = 1 && 1 && 1 = 1  ✓
           仍然正确
```

**优势：** SW后立即LW，在cycle N+1就能拿到正确数据，无需等待！

### 场景2：字节写入 (SB) 后字读取 (LW)

```
Cycle N:   sb x1, 0(x2)     dram_wen=1, bram_we_r将在N+1变成4'b0001
Posedge N+1: 捕获store, buf_valid_sr = 2'b11
Cycle N+1: lw x3, 0(x2)     
           bram_addr_rd = addr
           is_full_word_write = 0  (只写了1字节)
           fwd_early = 1 && 1 && 0 && 1 = 0  ✗ (不触发早期forward)
           bram_dout = 错误地址的数据
           返回 bram_dout (可能是旧数据，但至少不会混合错误地址的数据)
           
Posedge N+2: bram_addr_rd_r = addr, BRAM采样addr, buf_valid_sr = 2'b01
Cycle N+2: (Load在MEM2阶段拿数据)
           bram_dout = addr的旧数据 (正确！)
           fwd_normal = 1 && 1 && 1 = 1  ✓
           返回混合数据: byte[0]来自bram_din_r, byte[3:1]来自bram_dout  ✓
```

**说明：** SB后LW需要2个周期才能拿到正确的混合数据，但这符合BRAM 1-cycle读延迟的设计。

## 对比三种方案

| 方案 | SW→LW延迟 | SB→LW延迟 | 复杂度 | 正确性 |
|------|----------|----------|--------|--------|
| **原代码** | 0 cycle | 0 cycle | 简单 | ❌ SB→LW错误 |
| **V1修复** | 1 cycle | 1 cycle | 中等 | ✓ 但过于保守 |
| **V2优化** | 0 cycle | 1 cycle | 中等 | ✓ 最优平衡 |

## 为什么V2更好？

1. **常见场景优化**：大多数Store-Load是整字操作（SW→LW），V2在这种情况下无额外延迟
2. **正确性保证**：部分字节写入仍然正确处理，不会使用错误的`bram_dout`
3. **兼容性好**：对于期望快速SW→LW的程序（如栈操作、全局变量访问），性能更好

## CPU流水线配合

### 不需要额外Stall的场景

```assembly
sw   x1, 0(x2)    # Cycle N (MEM)
lw   x3, 0(x2)    # Cycle N+1 (MEM1), N+2 (MEM2拿数据) ✓
```

早期forward在cycle N+1触发，CPU在cycle N+2（MEM2）拿到正确数据。

### 可能需要Stall的场景

```assembly
sb   x1, 0(x2)    # Cycle N (MEM)
lw   x3, 0(x2)    # Cycle N+1 (MEM1), N+2 (MEM2拿数据)
                  # 如果CPU期望在N+1就拿到数据，需要stall 1周期
```

但这符合BRAM本身的1-cycle读延迟特性，是硬件限制。

## 实际效果

- **指令测试全通过** ✓：基本逻辑正确
- **程序测试改善**：整字Store-Load密集的程序性能提升
- **部分字节操作**：仍然正确，只是需要1个额外周期（合理）

## 总结

V2方案通过**区分整字和部分字节写入**，在保证正确性的前提下优化了常见场景的性能：
- 整字写入：早期forward（cycle N+1）
- 部分字节：正常forward（cycle N+2）
- 两种情况都使用正确的数据源，不会出现地址混淆
