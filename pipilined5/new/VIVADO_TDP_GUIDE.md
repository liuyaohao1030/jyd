# True Dual Port BRAM - Vivado 操作指南

## 目录

1. [概述](#1-概述)
2. [创建 DRAM_TDP IP 核](#2-创建-dram_tdp-ip-核)
3. [修改 dram_driver.sv](#3-修改-dram_driversv)
4. [仿真验证](#4-仿真验证)
5. [综合与实现](#5-综合与实现)
6. [时序分析](#6-时序分析)
7. [上板验证](#7-上板验证)
8. [故障排除](#8-故障排除)

---

## 1. 概述

### 1.1 修改目标

将 DRAM 从单端口分布式存储器 (`dist_mem_gen`) 改为**真双端口 BRAM** (`blk_mem_gen`)：

- **Port A**: 写操作 (寄存器化输入，打断关键路径)
- **Port B**: 读操作 (组合逻辑地址，不影响读延迟)
- **不修改 CPU 管线**

### 1.2 文件清单

| 文件 | 说明 | 操作 |
|------|------|------|
| `dram_driver.sv` | DRAM 驱动模块 | **已修改** - 使用真双端口 |
| `DRAM_TDP.sv` | 行为级 BRAM 模型 | **新建** - 仿真用 |
| `IROM_BHV.sv` | 行为级 IROM 模型 | **新建** - 仿真用 |
| `tb_dram_tdp.sv` | DRAM_TDP 单元测试 | **新建** |
| `tb_student_top_tdp.sv` | 全系统测试 | **新建** |
| `sim_tdp.sh` | 仿真脚本 | **新建** |

### 1.3 时序对比

```
修改前 (单端口, 13级逻辑, ~6.2ns):
  EX: addr → 转发MUX → ALU → CARRY4×5 → 地址解码 → BRAM WEA → RAMB36E1

修改后 (真双端口, ~8级逻辑, ~4.5ns):
  EX: addr → 转发MUX → ALU → CARRY4×5 → EX/MEM寄存器
  新关键路径: bram_we_r(寄存器) → MUX → RAMB36E1 WEA (~1.5ns)
```

---

## 2. 创建 DRAM_TDP IP 核

### 2.1 打开 IP Catalog

1. 在 Vivado 中，点击左侧 **IP Catalog**
2. 搜索 `Block Memory Generator`
3. 双击打开配置向导

### 2.2 基本配置 (Basic)

| 参数 | 值 |
|------|-----|
| **Component Name** | `DRAM_TDP` |
| **Interface Type** | Native |
| **Memory Type** | True Dual Port RAM |

### 2.3 端口 A 配置 (Port A)

| 参数 | 值 |
|------|-----|
| **Write Width** | 32 |
| **Read Width** | 32 |
| **Write Depth** | 65536 |
| **Read Depth** | 65536 |
| **Operating Mode** | Write First |
| **Enable Port Type** | Always Enabled |
| **Byte Write Enable** | ☑ Yes |
| **Byte Size** | 8 |
| **Write Depth (auto)** | 65536 |

### 2.4 端口 B 配置 (Port B)

| 参数 | 值 |
|------|-----|
| **Write Width** | 32 |
| **Read Width** | 32 |
| **Write Depth** | 65536 |
| **Read Depth** | 65536 |
| **Operating Mode** | Read First |
| **Enable Port Type** | Always Enabled |
| **Byte Write Enable** | ☑ Yes |
| **Byte Size** | 8 |

### 2.5 其他设置 (Other Options)

| 参数 | 值 |
|------|-----|
| **Algorithm** | Minimum Area |
| **Memory Initialization** | ☑ Load Init File |
| **Init File** | 选择 `dram.coe` (或留空，全部初始化为 0) |
| **Fill Remaining Memory Locations** | ☑ 0 |

### 2.6 生成 IP

1. 点击 **OK**
2. 在弹出窗口中确认生成
3. 等待 IP 生成完成
4. 在 **Sources** 窗口中应看到 `DRAM_TDP` IP

### 2.7 验证 IP 接口

生成的 IP 应具有以下端口：

```verilog
// Port A
input  wire         clka,
input  wire         ena,
input  wire [3:0]   wea,      // Byte write enable
input  wire [15:0]  addra,
input  wire [31:0]  dina,
output wire [31:0]  douta,

// Port B
input  wire         clkb,
input  wire         enb,
input  wire [3:0]   web,
input  wire [15:0]  addrb,
input  wire [31:0]  dinb,
output wire [31:0]  doutb
```

---

## 3. 修改 dram_driver.sv

### 3.1 替换文件

将 `new/dram_driver.sv` 的内容复制到 Vivado 项目中的对应位置。

**关键修改点**:

```verilog
// 旧: 单端口 BRAM
DRAM_BRAM Mem_DRAM (
    .clka  (clk),
    .ena   (1'b1),
    .wea   (bram_we),
    .addra (dram_addr),
    .dina  (perip_wdata),
    .douta (bram_dout)
);

// 新: 真双端口 BRAM
// 写寄存器组 (打断关键路径)
logic [15:0] bram_addr_r;
logic [ 3:0] bram_we_r;
logic [31:0] bram_din_r;

always_ff @(posedge clk) begin
    bram_addr_r <= perip_addr[17:2];
    bram_we_r   <= dram_wen ? perip_be : 4'b0000;
    bram_din_r  <= perip_wdata;
end

// 读地址 (组合逻辑)
logic [15:0] bram_addr_rd;
assign bram_addr_rd = perip_addr[17:2];

// 实例化
DRAM_TDP u_dram_tdp (
    .clka  (clk),           .ena   (1'b1),
    .wea   (bram_we_r),     .addra (bram_addr_r),
    .dina  (bram_din_r),    .douta (),
    .clkb  (clk),           .enb   (1'b1),
    .web   (4'b0000),       .addrb (bram_addr_rd),
    .dinb  (32'b0),         .doutb (perip_rdata)
);
```

### 3.2 不需要修改的文件

- `perip_bridge.sv` - **无需修改**
  - `rd_is_dram_q` 已经是寄存器输出，与 BRAM 的 1 拍读延迟对齐
  - 写路径: `dram_wen` 仍然是组合逻辑输入，在 `dram_driver` 内部被寄存

- `student_top.sv` - **无需修改**
  - 端口连接不变

- `KLDJ_top.v` - **无需修改**
  - CPU 管线不受影响

---

## 4. 仿真验证

### 4.1 方法一: 使用 Vivado 仿真器 (xsim)

#### 步骤 1: 添加源文件

1. 在 Vivado 中，**Add Sources** → **Add or create design sources**
2. 添加以下文件:
   - `DRAM_TDP.sv` (仿真用行为级模型)
   - `dram_driver.sv` (已修改)
3. **Add Sources** → **Add or create simulation sources**
4. 添加测试文件:
   - `tb_dram_tdp.sv` (单元测试)
   - `tb_student_top_tdp.sv` (全系统测试)

#### 步骤 2: 设置仿真顶层

1. 在 **Simulation** → **Simulation Settings**
2. 设置 **Top module name** 为 `tb_dram_tdp` (单元测试) 或 `tb_student_top_tdp` (全系统测试)

#### 步骤 3: 运行仿真

1. 点击 **Run Simulation** → **Run Behavioral Simulation**
2. 在 Tcl 控制台中运行:
   ```tcl
   run 100us
   ```

#### 步骤 4: 检查结果

- 单元测试: 控制台应显示 `ALL TESTS PASSED!`
- 全系统测试: 检查 LED 输出和 DRAM 写操作日志

### 4.2 方法二: 使用 xsim 命令行

```bash
cd jyd/pipilined5/new

# 复制 hex 文件
cp ../kldj.srcs2/sim_1/imports/sim/irom_v2.hex .

# 单元测试
./sim_tdp.sh unit

# 全系统测试
./sim_tdp.sh full
```

### 4.3 方法三: 在现有项目中替换 IP 进行仿真

如果不想使用行为级模型，可以:

1. 先在 Vivado 中创建 DRAM_TDP IP (步骤 2)
2. 将行为级模型 `DRAM_TDP.sv` 从项目中移除
3. 使用 IP 进行仿真 (Vivado 会自动使用 IP 的仿真模型)

### 4.4 波形调试

在 xsim 波形查看器中，添加以下信号:

```
# 关键信号
tb_dram_tdp/u_dut/mem          # 内存内容
tb_dram_tdp/u_dut/douta        # Port A 输出
tb_dram_tdp/u_dut/doutb        # Port B 输出

# dram_driver 信号
tb_*/bridge_inst/dram_driver_inst/bram_addr_r   # 写地址寄存器
tb_*/bridge_inst/dram_driver_inst/bram_we_r     # 写使能寄存器
tb_*/bridge_inst/dram_driver_inst/bram_din_r    # 写数据寄存器
tb_*/bridge_inst/dram_driver_inst/bram_addr_rd  # 读地址(组合)
tb_*/bridge_inst/dram_driver_inst/perip_rdata   # 读数据输出
```

---

## 5. 综合与实现

### 5.1 替换 IP

1. 在 **Sources** → **IP Sources** 中:
   - 右键旧的 `DRAM` IP → **Remove File from Project**
   - 确保新的 `DRAM_TDP` IP 已在项目中

2. 更新 `dram_driver.sv` 中的实例化名:
   - 旧: `DRAM_BRAM Mem_DRAM (...)`
   - 新: `DRAM_TDP u_dram_tdp (...)`

### 5.2 添加约束 (XDC)

如果需要 Pblock 约束，将新 BRAM 放在合适位置:

```tcl
# 查看 BRAM 资源使用
report_utilization -hierarchical

# 可选: 创建 Pblock 约束
create_pblock pblock_dram
resize_pblock pblock_dram -add {RAMB36_X2Y10:RAMB36_X3Y30}
add_cells_to_pblock pblock_dram [get_cells student_top_inst/bridge_inst/dram_driver_inst/u_dram_tdp/*]
```

### 5.3 综合设置

1. **Run Synthesis**
2. 综合完成后检查:
   - **Utilization Report**: 确认使用了 BRAM 资源 (不是 LUT)
   - **Schematic**: 确认 DRAM_TDP 实例正确连接

### 5.4 实现

1. **Run Implementation**
2. 检查:
   - **Timing Report**: 确认 WNS (Worst Negative Slack) 为正
   - **Utilization Report**: 确认资源使用合理

---

## 6. 时序分析

### 6.1 检查时序报告

```tcl
# 打开时序报告
open_run impl_1
report_timing_summary

# 检查关键路径
report_timing -nworst 10 -setup
```

### 6.2 预期结果

| 指标 | 修改前 | 预期修改后 |
|------|--------|-----------|
| 关键路径延迟 | ~6.2ns | ~4.5ns |
| WNS (150MHz) | ~0.07ns | ~2.1ns |
| 最高频率 | ~150MHz | ~200MHz |

### 6.3 如果时序不满足

1. 检查是否正确使用了 BRAM (不是分布式 RAM)
2. 检查写寄存器组是否正确实例化
3. 检查是否有其他路径成为新的关键路径
4. 考虑添加 Pipeline 寄存器 (如果需要)

---

## 7. 上板验证

### 7.1 生成比特流

1. **Generate Bitstream**
2. 等待完成 (可能需要较长时间)

### 7.2 下载到开发板

1. **Open Hardware Manager**
2. **Open Target** → **Auto Connect**
3. **Program Device** → 选择生成的 `.bit` 文件

### 7.3 验证 irom-v2 程序

1. 复位开发板
2. 观察 LED 和七段数码管输出
3. 检查是否与预期结果一致

### 7.4 使用 ILA 调试 (可选)

如果需要调试，可以添加 ILA 核:

```tcl
# 在 XDC 中添加
create_debug_core ila_0 ila
set_property C_DATA_DEPTH 4096 [get_debug_cores ila_0]
set_property port_width 1 [get_debug_ports ila_0/clk]
connect_debug_port ila_0/clk [get_nets clk]

# 添加探针
create_debug_port ila_0 probe
set_property port_width 32 [get_debug_ports ila_0/probe0]
connect_debug_port ila_0/probe0 [get_nets {perip_addr[*]}]
```

---

## 8. 故障排除

### 8.1 仿真失败

**问题**: `DRAM_TDP` 模块找不到
```
ERROR: [VRFC 10-2063] Module <DRAM_TDP> not found
```
**解决**: 确保 `DRAM_TDP.sv` 已添加到项目中，或使用 Vivado IP 替代行为级模型。

**问题**: 仿真结果不正确
**解决**:
1. 检查波形中 `bram_we_r` 是否正确
2. 检查 `bram_addr_r` 和 `bram_addr_rd` 是否正确
3. 确认时钟和复位信号正常

### 8.2 综合错误

**问题**: IP 端口不匹配
```
ERROR: [Synth 8-448] named port connection 'douta' does not exist
```
**解决**: 检查 IP 配置，确保端口名称和位宽正确。

**问题**: 时序违规
**解决**:
1. 检查写寄存器组是否正确添加
2. 检查是否有时序例外约束
3. 考虑降低时钟频率

### 8.3 上板问题

**问题**: 程序不运行
**解决**:
1. 检查复位信号
2. 检查时钟信号
3. 使用 ILA 调试

**问题**: 数据读写错误
**解决**:
1. 检查地址映射是否正确
2. 检查字节使能信号
3. 确认 BRAM 初始化文件正确

---

## 附录 A: 文件依赖关系

```
student_top.sv
├── KLDJ_top.v (CPU 核心)
├── IROM (IP 或 IROM_BHV.sv)
└── perip_bridge.sv
    ├── display_seg.sv
    ├── counter.sv
    └── dram_driver.sv (已修改)
        └── DRAM_TDP (IP 或 DRAM_TDP.sv)
```

## 附录 B: 时序图

### 写操作时序 (Port A)

```
        ___     ___     ___     ___     ___
clk    |   |___|   |___|   |___|   |___|   |___
       
EX:    | addr=A, data=X, we=1  |
       |                         |
bridge:| 组合逻辑 → 寄存器锁存  |
       |                         |
       | addr_r=A, we_r=BE, din_r=X
       |                         |
BRAM:  |                         | 写入 (A, X)
       └─────────────────────────┘
              1 周期延迟
```

### 读操作时序 (Port B)

```
        ___     ___     ___     ___
clk    |   |___|   |___|   |___|   |___
       
EX:    | addr=B (Load) |
       |                |
bridge:| 组合逻辑地址   |
       |                |
BRAM:  |                | 读取 (B) → doutb
       |                |          (1拍延迟)
       └────────────────┘
```

### 读写同时 (不同端口)

```
        ___     ___     ___     ___
clk    |   |___|   |___|   |___|   |___
       
Port A:| 写入 addr=0x10  |
       |                  |
Port B:| 读取 addr=0x20   | → doutb = 旧值
       |                  |   (互不干扰)
       └──────────────────┘
```

---

## 附录 C: 快速参考

### 关键信号

| 信号 | 方向 | 说明 |
|------|------|------|
| `bram_we_r` | reg | 写使能寄存器 (4位) |
| `bram_addr_r` | reg | 写地址寄存器 (16位) |
| `bram_din_r` | reg | 写数据寄存器 (32位) |
| `bram_addr_rd` | wire | 读地址 (组合逻辑) |
| `perip_rdata` | wire | 读数据输出 |

### Tcl 常用命令

```tcl
# 查看 IP 状态
report_ip_status

# 查看资源使用
report_utilization -hierarchical

# 查看时序
report_timing_summary
report_timing -nworst 10

# 查看 BRAM 使用
report_utilization -cells [get_cells -hierarchical -filter {REF_NAME=~*BRAM*}]
```
