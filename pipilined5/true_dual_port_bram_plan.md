# 真双端口 BRAM 实现方案

## 1. 背景

### 当前配置
- **IP 核**: `dist_mem_gen` (分布式存储器生成器)
- **类型**: 单端口 RAM (`single_port_ram`)
- **容量**: 65536 × 32位 = 256KB
- **地址宽度**: 16位
- **端口**: `a[15:0]`, `d[31:0]`, `clk`, `we`, `spo[31:0]`
- **输入/输出**: 均无寄存器 (`non_registered`)

### 目标
将 DRAM 改为**真双端口 BRAM**，实现：
- **端口 A**: 写操作 (寄存器化 WEA/地址/数据，打断关键路径)
- **端口 B**: 读操作 (保持组合逻辑地址，不影响读延迟)
- **不修改 CPU 管线**

---

## 2. 架构设计

### 2.1 整体架构

```
                    ┌─────────────────────────────────────────┐
                    │           dram_driver (修改后)           │
                    │                                         │
  perip_addr ──────►│  地址解码 + 对齐                         │
  perip_wdata ─────►│  ┌─────────────┐                        │
  perip_be ────────►│  │ 写寄存器组   │                        │
  perip_wen ───────►│  │ (posedge clk)│                        │
                    │  └──────┬──────┘                        │
                    │         │ wea_r, addr_r, din_r           │
                    │         ▼                                │
                    │  ┌─────────────────────────────────┐    │
                    │  │      True Dual Port BRAM         │    │
                    │  │                                   │    │
                    │  │  Port A (写):                     │    │
                    │  │    clka  = clk                    │    │
                    │  │    wea   = bram_we_r  ──────────►│────│──► 关键路径被打断!
                    │  │    addra = bram_addr_r            │    │
                    │  │    dina  = bram_din_r             │    │
                    │  │                                   │    │
                    │  │  Port B (读):                     │    │
                    │  │    clkb  = clk                    │    │
                    │  │    web   = 4'b0                   │    │
                    │  │    addrb = bram_addr  (组合逻辑)  │    │
                    │  │    dinb  = 32'b0                  │    │
                    │  │    doutb = bram_dout ─────────────│────│──► 读数据 (1拍延迟)
                    │  └─────────────────────────────────┘    │
                    │                                         │
                    │  perip_rdata = bram_dout ◄──────────────│──► 直接输出
                    └─────────────────────────────────────────┘
```

### 2.2 时序对比

#### 当前时序 (单端口)

```
时钟沿 N:
  EX阶段: addr=A, data=X, we=1
  → 组合逻辑到 BRAM (addr, wea, dina)
  → BRAM 在时钟沿 N+1 写入 (A, X)

时钟沿 N+1:
  EX阶段: addr=B (Load)
  → 组合逻辑到 BRAM (addr)
  → BRAM 在时钟沿 N+2 读出 (B)
```

#### 修改后时序 (真双端口)

```
时钟沿 N:
  EX阶段: addr=A, data=X, we=1
  → 组合逻辑到 bridge
  → bridge 寄存器锁存: addr_r=A, wea_r=BE, din_r=X

时钟沿 N+1:
  Port A: BRAM 写入 (A, X)  ← 写操作延迟1拍
  EX阶段: addr=B (Load)
  → Port B: BRAM 读取 (B)   ← 读操作不受影响!

时钟沿 N+2:
  Port B: BRAM 输出 B 的数据  ← 读延迟仍是1拍
```

**关键**: 读写端口独立，互不干扰。

---

## 3. 实现步骤

### 步骤 1: 创建新的 BRAM IP 核

在 Vivado IP Catalog 中创建 `blk_mem_gen` IP:

| 参数 | 值 |
|---|---|
| **Component Name** | `DRAM_TDP` |
| **Memory Type** | True Dual Port RAM |
| **Write Width A** | 32 |
| **Write Depth A** | 65536 |
| **Read Width A** | 32 |
| **Write Width B** | 32 |
| **Read Width B** | 32 |
| **Port A Write Mode** | Write First |
| **Port B Write Mode** | No Change |
| **Operating Mode A** | Write First |
| **Operating Mode B** | Read First |
| **Enable Port A** | Always Enabled |
| **Enable Port B** | Always Enabled |
| **Byte Write Enable** | Yes (Port A 和 Port B) |
| **Byte Size** | 8 |
| **Algorithm** | Minimum Area |
| **Memory Initialization** | 使用 `dram.coe` 或 `dram.mif` |

### 步骤 2: 修改 dram_driver.sv

```verilog
module dram_driver(
    input  logic         clk,
    input  logic [17:0]  perip_addr,
    input  logic [31:0]  perip_wdata,
    input  logic [3:0]   perip_be,
    input  logic         dram_wen,
    output logic [31:0]  perip_rdata
);

    // ============================================================
    // 写寄存器组: 将写信号寄存一拍，打断关键路径
    // ============================================================
    logic [15:0] bram_addr_r;
    logic [ 3:0] bram_we_r;
    logic [31:0] bram_din_r;

    always_ff @(posedge clk) begin
        bram_addr_r <= perip_addr[17:2];
        bram_we_r   <= dram_wen ? perip_be : 4'b0000;
        bram_din_r  <= perip_wdata;
    end

    // ============================================================
    // 读地址: 保持组合逻辑，不增加读延迟
    // ============================================================
    logic [15:0] bram_addr_rd;
    assign bram_addr_rd = perip_addr[17:2];

    // ============================================================
    // 真双端口 BRAM 实例化
    // ============================================================
    DRAM_TDP u_dram_tdp (
        // Port A: 写 (寄存器化)
        .clka   (clk),
        .ena    (1'b1),
        .wea    (bram_we_r),      // 4位字节写使能 (寄存器输出)
        .addra  (bram_addr_r),    // 16位地址 (寄存器输出)
        .dina   (bram_din_r),     // 32位数据 (寄存器输出)
        .douta  (),               // 不使用端口A的读输出

        // Port B: 读 (组合逻辑地址)
        .clkb   (clk),
        .enb    (1'b1),
        .web    (4'b0000),        // 端口B只读，不写
        .addrb  (bram_addr_rd),   // 16位地址 (组合逻辑)
        .dinb   (32'b0),          // 不使用
        .doutb  (perip_rdata)     // 32位读数据
    );

endmodule
```

### 步骤 3: 修改 perip_bridge.sv (可选)

如果 `perip_bridge` 中有对 DRAM 的特殊处理，需要确认读写路径正确。

当前 `perip_bridge` 中的关键代码:

```verilog
// 写路径
dram_driver dram_driver_inst (
    .clk                (clk),
    .perip_addr         (perip_addr[17:0]),
    .perip_wdata        (perip_wdata),
    .perip_be           (perip_be),
    .dram_wen           (perip_wen && is_dram_addr),
    .perip_rdata        (dram_rdata)
);

// 读路径 (已在 perip_bridge 中注册)
always_ff @(posedge clk) begin
    rd_is_dram_q <= (~perip_wen) && is_dram_addr;
    // ...
end

assign perip_rdata = rd_is_dram_q ? dram_rdata : ...;
```

**无需修改** `perip_bridge`，因为:
1. 写路径: `dram_wen` 仍然是组合逻辑输入，只是在 `dram_driver` 内部被寄存
2. 读路径: `rd_is_dram_q` 已经是寄存器输出，与 BRAM 的1拍读延迟对齐

### 步骤 4: 更新 XDC 约束 (如果需要)

```tcl
# 如果需要 Pblock 约束，将新 BRAM 放在 CPU 附近
create_pblock pblock_dram
resize_pblock pblock_dram -add {RAMB36_X2Y10:RAMB36_X3Y30}
add_cells_to_pblock pblock_dram [get_cells student_top_inst/bridge_inst/dram_driver_inst/u_dram_tdp/*]
```

---

## 4. 时序分析

### 4.1 关键路径变化

**修改前** (13级逻辑, 6.182ns):
```
mem_wb_rd_addr_reg → 转发MUX(LUT6) → 转发MUX(LUT6) → 转发MUX(LUT5)
  → ALU输入(LUT2) → CARRY4×5 → 地址解码(LUT6) → 地址解码(LUT2)
  → 地址解码(LUT6) → BRAM WEA(LUT6) → RAMB36E1
```

**修改后** (~8级逻辑, ~4.5ns):
```
mem_wb_rd_addr_reg → 转发MUX(LUT6) → 转发MUX(LUT6) → 转发MUX(LUT5)
  → ALU输入(LUT2) → CARRY4×5 → EX/MEM寄存器
```

**新关键路径** (~2级逻辑, ~1.5ns):
```
bram_we_r (寄存器) → MUX → RAMB36E1 WEA
```

### 4.2 预期时序改善

| 项目 | 修改前 | 修改后 |
|---|---|---|
| 关键路径逻辑级数 | 13级 | ~8级 |
| 关键路径延迟 | 6.182ns | ~4.5ns |
| WNS (150MHz) | 0.073ns | ~2.1ns |
| 预计最高频率 | 150MHz | **~200MHz** |

---

## 5. 功能验证

### 5.1 需要验证的场景

1. **基本读写**: Store 后 Load 同一地址
2. **连续写**: 连续多拍写不同地址
3. **读写冲突**: 同一拍读写同一地址
4. **字节写**: SB/SH/SW 的部分写入
5. **MMIO 访问**: 不影响外设读写

### 5.2 irom-v2 测试覆盖

irom-v2 已覆盖以下场景:
- ✅ 基本 Store/Load (第374行附近)
- ✅ Load-Use Stall (第453行)
- ✅ 字节/半字读写 (第380行附近)
- ✅ CSR 读写 (不影响)
- ✅ ECALL/MRET (不影响)

### 5.3 仿真验证方法

使用现有 testbench `KLDJ_top_tb` 进行验证:
1. 运行 irom-v2 程序
2. 检查所有寄存器值是否正确
3. 检查 DRAM 读写是否正确
4. 检查 MMIO 是否正常工作

---

## 6. 风险评估

### 6.1 低风险
- ✅ 读延迟不变 (1拍)
- ✅ 不需要修改 CPU 管线
- ✅ 不需要修改 perip_bridge
- ✅ irom-v2 程序已覆盖关键场景

### 6.2 中风险
- ⚠️ 写延迟增加1拍 (Store 不等待，功能无影响)
- ⚠️ 需要重新创建 BRAM IP 核
- ⚠️ 需要重新综合和实现

### 6.3 需要注意
- ⚠️ 确保 BRAM IP 的初始化文件 (dram.coe/dram.mif) 正确
- ⚠️ 确保字节写使能 (WEA) 的位宽正确 (4位)
- ⚠️ 确保读写端口的时钟域一致

---

## 7. 实施清单

- [ ] 创建 `DRAM_TDP` IP 核 (True Dual Port, 65536×32位)
- [ ] 配置 Port A: 写优先模式, 字节写使能
- [ ] 配置 Port B: 读优先模式, 无写使能
- [ ] 加载初始化文件 (dram.coe/dram.mif)
- [ ] 修改 `dram_driver.sv`: 添加写寄存器组, 实例化新 IP
- [ ] 更新 `student_top.sv` 中的端口连接 (如果需要)
- [ ] 运行仿真验证 (KLDJ_top_tb)
- [ ] 综合实现, 检查时序报告
- [ ] 上板验证 irom-v2 程序
