# KLDJ RV32I CPU 测评技术报告（初版）

队伍编号：待填写  
姓名：待填写  
年级：待填写  
专业：待填写  
日期：待填写  

---

## 填报标记说明

为方便后续补充实测数据，本文档使用以下标记。正式提交前可以保留这些标记用于自查，也可以在全部补齐后统一删除。

| 标记 | 含义 |
| --- | --- |
| <span style="color:#1F4E79;font-weight:700">【固定信息】</span> | 来自当前 RTL 或 Vivado 工程结构，提交前只需复核 |
| <span style="color:#C00000;font-weight:700">【需实测】</span> | 需要在 Vivado Simulation、Implementation 或上板环境中重新获取 |
| <span style="color:#7030A0;font-weight:700">【需截图】</span> | 需要在最终报告中插入波形图、报告截图或板卡/数字孪生截图 |
| <span style="color:#666666;font-weight:700">【参考值】</span> | 当前工程中已有的参考数据，只用于排版和对照，最终以本人实测为准 |

---

## 摘要

本文针对 KLDJ RV32I CPU 开展功能正确性、指令集覆盖性、流水线行为、性能指标和上板可运行性测评。被测 CPU 采用五级流水线结构，包含取指、译码、执行、访存和写回阶段，并实现数据前递、load-use 暂停、分支/跳转冲刷以及外部数据存储器/MMIO 访问接口。

测评方法采用“仿真差分验证 + 数字孪生/FPGA 上板验证”的双路径方案。仿真部分使用 `rv32i_supported_instr_tb.sv` 作为自检 testbench，构造软件参考模型，在每条指令进入写回阶段并确认完成执行时比较 PC、寄存器堆和访存结果；上板部分基于 `digital_twin` 工程，通过 IROM 程序加载、MMIO 外设访问、LED/数码管/UART 输出展示硬件运行现象。测试范围覆盖 RV32I 基础整数指令集中除 `FENCE`、`ECALL`、`EBREAK` 以外的 37 条指令。

最终报告需要结合本人 Vivado 实测数据填写仿真通过情况、完成执行的指令条数、平均 CPI、时序频率、资源使用率以及上板截图。本文档同时给出建议的截图位置、分析文字模板和高分呈现方式，便于后续整理为比赛提交材料。

**关键词：** RV32I；五级流水线；差分验证；Vivado Simulation；FPGA 上板验证；数字孪生；MMIO

---

## 目录

1. [引言](#1-引言)  
2. [测评对象与实验环境](#2-测评对象与实验环境)  
3. [测评方法与指标体系](#3-测评方法与指标体系)  
4. [RV32I 指令集支持与测试用例设计](#4-rv32i-指令集支持与测试用例设计)  
5. [CPU 性能与特色功能测评设计](#5-cpu-性能与特色功能测评设计)  
6. [综合测评结果与分析](#6-综合测评结果与分析)  
7. [结论](#7-结论)  
8. [后续填报检查清单](#8-后续填报检查清单)  
9. [附录](#9-附录)  

---

## 图表清单

正式提交前建议至少补齐以下图表：

| 编号 | 图表名称 | 状态 |
| --- | --- | --- |
| 图 2-1 | Vivado Simulation 顶层设置截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 2-2 | Hardware Manager 下载 bitstream 截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-1 | RV32I 自检 Console summary 截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-2 | 算术逻辑类指令关键波形 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-3 | 访存类指令关键波形 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-4 | 分支跳转类指令关键波形 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-5 | Timing Report 截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-6 | Utilization Report 截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| 图 6-7 | 数字孪生/板卡运行结果截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |

---

# 1. 引言

RISC-V RV32I 是面向 32 位整数处理器设计的基础指令集，具有指令编码规整、硬件实现简洁、扩展性强等特点。对于自研 CPU 作品而言，测评报告不仅需要说明“实现了哪些指令”，还需要通过清晰的测试用例和可复现的实验结果证明指令行为、流水线控制和硬件集成的正确性。

本报告面向比赛提交材料编写，目标是形成一份能够被评委快速阅读和复核的 CPU 测评文档。报告采用科研工程论文式组织方式：先说明测评对象与实验环境，再给出测评方法、测试用例和指标体系，随后通过仿真与上板双重证据呈现结果，最后总结设计达标情况。

本文的主要测评问题包括：

1. KLDJ CPU 是否完整支持比赛要求的 RV32I 37 条基础整数指令？
2. 算术逻辑、访存、分支跳转等关键指令类别是否具有清晰测试用例和预期结果？
3. 五级流水线的数据相关、load-use 暂停和控制流冲刷是否工作正确？
4. Vivado 实现结果是否达到目标时钟频率，资源占用是否合理？
5. 上板/数字孪生运行结果是否与仿真结果一致？

# 2. 测评对象与实验环境

## 2.1 被测 CPU 概述

KLDJ CPU 是一个 RV32I 五级流水线处理器。处理器顶层为 `KLDJ_top`，对外暴露取指接口、数据存储器接口和若干 testbench 观测信号。流水线结构如表 2-1 所示。

表 2-1 CPU 流水线阶段说明

| 阶段 | 功能 | 主要验证关注点 |
| --- | --- | --- |
| IF | PC 更新、顺序取指、跳转重定向 | PC 是否按顺序或目标地址更新 |
| ID | 指令译码、立即数生成、寄存器堆读取 | RV32I 37 条指令译码是否正确 |
| EX | ALU 运算、比较、分支判断、JAL/JALR 目标计算 | 运算结果、分支条件和目标地址 |
| MEM | load/store 访问、字节使能、符号/零扩展 | 访存地址、写掩码和读数据扩展 |
| WB | 写回寄存器堆、提交观测 | 写回值、提交顺序和寄存器状态 |

处理器实现了 EX/MEM 与 MEM/WB 数据前递机制，针对 load-use 相关插入必要暂停，并在分支或跳转发生时冲刷错误路径指令。这些机制均在后续测试用例中进行覆盖。

## 2.2 仿真测试平台

仿真验证使用 Vivado Simulation。测试平台顶层为 `rv32i_supported_instr_tb.sv`，该 testbench 直接例化 `KLDJ_top`，并提供指令存储器、数据存储器和软件参考模型。仿真平台配置见表 2-2。

表 2-2 仿真平台配置

| 项目 | 内容 |
| --- | --- |
| 仿真工具 | <span style="color:#C00000;font-weight:700">【需实测】</span> Vivado Simulation，版本待填写 |
| 仿真顶层 | `rv32i_supported_instr_tb` |
| testbench 文件 | `kldj.srcs2/sim_1/imports/sim/rv32i_supported_instr_tb.sv` |
| CPU 顶层文件 | `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v` |
| 仿真时钟周期 | <span style="color:#1F4E79;font-weight:700">【固定信息】</span> 10 ns。testbench 中 `forever #5 clk = ~clk;` 表示每 5 ns 翻转一次，完整周期为 10 ns |
| 复位方式 | 高电平有效复位，即 `rst=1` 时 CPU 处于复位状态，`rst=0` 后释放复位并开始运行 |
| 结果判断方式 | CPU 每完成一条指令并进入写回/提交观测点时，testbench 将 PC、寄存器堆和访存结果与参考模型比较 |

说明：如果后续修改 testbench 中的 `#5`，仿真时钟周期需要按“翻转间隔 × 2”重新计算；也可以在 Vivado 波形窗口中测量两个相邻上升沿之间的时间来确认。

<span style="color:#7030A0;font-weight:700">【需截图】</span> 图 2-1：Vivado Simulation 设置界面，标出仿真顶层 `rv32i_supported_instr_tb`。

## 2.3 上板验证平台

上板验证基于 `digital_twin` 工程完成。板级顶层 `top.sv` 连接差分时钟、UART、数字孪生控制器和 CPU 子系统；`student_top.sv` 将 CPU 与 IROM、DRAM/MMIO 桥接模块连接起来。上板环境见表 2-3。

表 2-3 上板验证平台配置

| 项目 | 内容 |
| --- | --- |
| Vivado 工程 | `digital_twin/digital_twin.xpr` |
| 板级顶层 | `digital_twin/digital_twin.srcs/sources_1/new/top.sv` |
| CPU 接入顶层 | `digital_twin/digital_twin.srcs/sources_1/new/student_top.sv` |
| FPGA 开发板/器件 | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写，例如 Xilinx K-7 / `xc7k325tffg900-2` |
| 下载工具 | <span style="color:#C00000;font-weight:700">【需实测】</span> Vivado Hardware Manager，版本待填写 |
| bitstream | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |

<span style="color:#7030A0;font-weight:700">【需截图】</span> 图 2-2：Hardware Manager 下载 bitstream 成功界面。

## 2.4 测试交互方式

仿真阶段，测试程序由 testbench 内部生成，CPU 通过 `tb_if_pc` 输出取指地址，testbench 根据 PC 返回对应指令。上板阶段，测试程序写入 IROM 初始化文件，随 bitstream 一同下载到 FPGA 或数字孪生平台。

结果观察方式见表 2-4。

表 2-4 结果观察方式

| 场景 | 观察方式 | 建议呈现形式 |
| --- | --- | --- |
| 仿真整体结果 | xsim Console summary | 截图并摘录 PASS/FAIL、周期数、完成执行的指令数 |
| 算术逻辑行为 | 寄存器写回波形 | 红框标出目标寄存器写入值 |
| 访存行为 | `mem_addr`, `mem_wdata`, `mem_be`, `mem_rdata` | 红框标出地址、掩码和读写数据 |
| 分支跳转行为 | `tb_ex_jump`, `tb_ex_jump_pc`, `wb_commit_pc` | 红框标出跳转目标和错误路径不提交 |
| 上板结果 | LED、数码管、UART 或数字孪生界面 | 表格说明显示值含义 |

如果上板结果通过 LED 展示，建议定义 `0x00000000` 为全部通过，非零值为错误码；如果能够使用 UART 输出，建议打印 `PASS` 或 `Expected: xx, Actual: xx`，便于截图证明。

# 3. 测评方法与指标体系

## 3.1 差分验证方法

仿真 testbench 内部维护一份软件参考模型，包括 32 个通用寄存器、字节寻址数据存储器、期望提交 PC 和期望下一 PC。每生成一条测试指令，参考模型同步执行该指令的语义；DUT 每完成一条指令并到达写回/提交观测点时，testbench 将 DUT 状态与参考模型逐项比较。

这里的“提交”是流水线 CPU 测试中的常用说法，意思是一条指令已经执行到可以确认结果的位置。本项目中主要通过 `wb_commit_valid` 和 `wb_commit_pc` 观察这一时刻。它不是新的硬件功能，只是测试时用于判断“这条指令已经执行完成”的观测点。

表 3-1 差分检查项

| 检查项 | 检查内容 | 可发现的问题 |
| --- | --- | --- |
| 提交 PC | `wb_commit_pc` 是否等于期望 PC | 取指、分支、跳转错误 |
| 寄存器堆 | `x0` 至 `x31` 是否与参考模型一致 | ALU、写回、前递错误 |
| 下一 PC | 顺序、分支、JAL、JALR 目标是否正确 | 控制流错误 |
| 访存结果 | load/store 数据是否与参考模型一致 | 字节使能、扩展、地址错误 |
| 错误路径 | 被跳过指令是否不会提交 | 流水线冲刷错误 |

该方法的优点是结果判断自动化，不依赖人工逐条观察波形；波形截图主要用于最终报告解释关键场景。

## 3.2 测评指标

表 3-2 测评指标体系

| 类别 | 指标 | 数据来源 |
| --- | --- | --- |
| 指令集覆盖 | RV32I 37 条指令是否覆盖 | testbench 用例分类 |
| 功能正确性 | 仿真 PASS/FAIL、错误数 | xsim Console |
| 流水线行为 | 数据前递、暂停、冲刷是否正确 | 波形与差分结果 |
| 性能 | `cycles`、`retired_steps`、平均 CPI | xsim summary |
| 实现频率 | CPU 时钟频率、WNS、TNS | Timing Report |
| 资源占用 | LUT、寄存器、BRAM、DSP、IO | Utilization Report |
| 上板一致性 | LED/数码管/UART 输出是否符合预期 | 板卡或数字孪生截图 |

# 4. RV32I 指令集支持与测试用例设计

## 4.1 RV32I 指令支持概况

本 CPU 支持 RV32I 基础整数指令集中除 `FENCE`、`ECALL`、`EBREAK` 外的 37 条测评指令。支持清单见表 4-1。

表 4-1 RV32I 指令支持清单

| 类别 | 支持指令 |
| --- | --- |
| U 型立即数 | `LUI`, `AUIPC` |
| 跳转 | `JAL`, `JALR` |
| 条件分支 | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| I 型算术逻辑 | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| R 型算术逻辑 | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Load | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Store | `SB`, `SH`, `SW` |

## 4.2 算术与逻辑运算指令测试

测试目的：验证 ALU 运算、立即数扩展、寄存器堆读写和数据前递。

覆盖指令包括 `ADD`、`SUB`、`AND`、`OR`、`XOR`、`SLL`、`SRL`、`SRA`、`SLT`、`SLTU` 以及对应 I 型立即数指令。输入数据覆盖 0、1、`0xffffffff`、`0x7fffffff`、`0x80000000`、正负边界立即数和随机样本。

关键代码片段：

```systemverilog
case_add(sample_word(i + 161), sample_word(i + 173));
case_sub(sample_word(i + 181), sample_word(i + 193));
case_slt(sample_word(i + 227), sample_word(i + 239));
case_sltu(sample_word(i + 251), sample_word(i + 263));
case_and(sample_word(i + 353), sample_word(i + 367));
```

表 4-2 算术逻辑类测试预期

| 环境 | 预期输出 |
| --- | --- |
| 仿真 | 每条指令完成执行后，目标寄存器值与参考模型一致 |
| 上板 | 自检程序错误码保持 0，LED/UART 显示算术逻辑类测试通过 |

## 4.3 访存指令测试

测试目的：验证 load/store 地址计算、写字节使能、数据对齐、符号扩展和零扩展。

覆盖指令包括 `LB`、`LH`、`LW`、`LBU`、`LHU`、`SB`、`SH`、`SW`。测试程序先设置基地址和待写入数据，再执行不同宽度和不同偏移的 store/load 组合。

关键代码片段：

```systemverilog
exec_store(F3_SW, 5'd10, 5'd11, 0);
exec_load (F3_LW, 5'd12, 5'd10, 0);
exec_store(F3_SH, 5'd10, 5'd11, 8);
exec_load (F3_LH, 5'd13, 5'd10, 8);
exec_load (F3_LHU, 5'd14, 5'd10, 8);
exec_store(F3_SB, 5'd10, 5'd11, 12);
exec_load (F3_LB, 5'd15, 5'd10, 12);
exec_load (F3_LBU, 5'd16, 5'd10, 12);
```

表 4-3 访存类测试预期

| 环境 | 预期输出 |
| --- | --- |
| 仿真 | `mem_addr`、`mem_wdata`、`mem_be` 与访问宽度一致，load 写回值正确 |
| 上板 | DRAM/MMIO 读写自检通过，LED/UART 不输出错误码 |

## 4.4 分支与跳转指令测试

测试目的：验证条件判断、目标 PC 计算、`JAL/JALR` 写回 `PC+4` 以及流水线冲刷。

覆盖指令包括 `BEQ`、`BNE`、`BLT`、`BGE`、`BLTU`、`BGEU`、`JAL`、`JALR`。testbench 为每类分支构造 taken 与 not-taken 两类路径，并在错误路径放置计数指令；若冲刷失败，错误路径指令会提交并触发差分失败。

关键代码片段：

```systemverilog
build_branch_suite(3'b000, 8); // BEQ
build_branch_suite(3'b001, 8); // BNE
build_branch_suite(3'b100, 8); // BLT
build_branch_suite(3'b101, 8); // BGE
build_branch_suite(3'b110, 8); // BLTU
build_branch_suite(3'b111, 8); // BGEU

case_jal(5'd3);
case_jalr(5'd6);
```

表 4-4 分支跳转类测试预期

| 环境 | 预期输出 |
| --- | --- |
| 仿真 | taken 时跳到目标地址，not-taken 时顺序执行，错误路径不提交 |
| 上板 | 分支跳转自检通过，LED/UART 显示通过码 |

# 5. CPU 性能与特色功能测评设计

## 5.1 性能测评设计

性能测评采用两个层面的指标：一是仿真程序的平均 CPI，二是 Vivado 实现后的 CPU 时钟频率。当前 RV32I 混合自检程序包含 ALU、访存、分支、跳转和流水线冒险场景，因此可作为基础性能测试程序。若需要更偏“应用程序”的展示，可额外准备冒泡排序或斐波那契汇编程序写入 IROM。

表 5-1 性能指标填写表

| 指标 | 结果 |
| --- | --- |
| 仿真周期数 `cycles` | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 完成执行的指令数 `retired_steps` | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 平均 CPI | <span style="color:#C00000;font-weight:700">【需实测】</span> `cycles / retired_steps` |
| CPU 时钟频率 | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| WNS/TNS | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 等效指令吞吐 | <span style="color:#C00000;font-weight:700">【需实测】</span> `CPU 频率 / CPI` |

<span style="color:#666666;font-weight:700">【参考值】</span> 当前工程目录中一次仿真结果形式为：

```text
[SUMMARY] rv32i supported pipeline diff-style test passed.
[INFO] total_cases=360 retired_steps=1609 program_words=1667 cycles=1729
```

该参考结果对应平均 CPI 约为 1.0746。正式报告请替换为本人重新运行的 Vivado 结果。

## 5.2 特色功能测评设计

本设计不强行声称未实现的中断、AXI 或浮点功能，而突出已经具备且可验证的工程特性：五级流水线、数据前递、load-use 暂停、分支/跳转冲刷和数字孪生 MMIO 交互。

表 5-2 特色功能测评用例

| 特色功能 | 测试方法 | 预期现象 |
| --- | --- | --- |
| 五级流水线执行 | 观察连续提交波形 | 多数普通指令可接近每周期完成一条 |
| 数据前递 | 构造连续 RAW 相关 ALU 指令 | 不产生错误写回 |
| load-use 暂停 | load 后立即使用结果 | 插入必要暂停，最终结果正确 |
| 分支/跳转冲刷 | taken 分支后放置错误路径指令 | 错误路径不提交 |
| 数字孪生 MMIO | CPU 读开关/按键、写 LED/数码管 | 输出随输入变化 |

# 6. 综合测评结果与分析

本章是最终提交材料的重点。建议每个测试类别均采用“用例-仿真-上板”三列对比表，并在截图中使用红框、箭头和文字标注关键信号。

## 6.1 RV32I 指令集测试结果

### 6.1.1 仿真 summary

表 6-1 RV32I 自检仿真结果

| 项目 | 结果 |
| --- | --- |
| 仿真结论 | <span style="color:#C00000;font-weight:700">【需实测】</span> PASS / FAIL |
| `total_cases` | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| `retired_steps` | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| `program_words` | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| `cycles` | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |

<span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-1：xsim Console summary。

### 6.1.2 分类别结果对比

表 6-2 RV32I 指令集测试结果对比

| 测试用例 | 仿真核心波形及解析 | 上板实测图及解析 |
| --- | --- | --- |
| 算术逻辑类 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-2。标出 `wb_commit_valid`、`wb_commit_pc` 和目标寄存器写回值。说明第 N 个周期该指令完成执行，目标寄存器写入预期值。 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-3。LED/UART 显示算术逻辑测试通过码。 |
| 访存类 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-4。标出 `mem_addr`、`mem_wdata`、`mem_be`、`mem_rdata`。说明访问宽度和写回值正确。 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-5。DRAM/MMIO 自检通过，输出与预期一致。 |
| 分支跳转类 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-6。标出 `tb_ex_jump`、`tb_ex_jump_pc`、`wb_commit_pc`。说明 taken 分支跳到目标地址，错误路径不提交。 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 图 6-7。分支跳转测试通过码。 |

结果分析建议写法：

> 如图 6-2 至图 6-7 所示，算术逻辑、访存和分支跳转三类测试均在仿真中得到与参考模型一致的结果。上板运行时，测试程序输出通过码，说明硬件环境中的执行结果与仿真预期一致。

## 6.2 CPU 性能测评结果

表 6-3 性能测评结果

| 测评项 | 证据 | 结果 |
| --- | --- | --- |
| CPU 时钟频率 | <span style="color:#7030A0;font-weight:700">【需截图】</span> Timing Report Clock Summary | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| WNS/TNS | <span style="color:#7030A0;font-weight:700">【需截图】</span> Timing Summary | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 平均 CPI | <span style="color:#7030A0;font-weight:700">【需截图】</span> xsim summary | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 等效指令吞吐 | 由 `CPU 频率 / CPI` 计算 | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 资源占用 | <span style="color:#7030A0;font-weight:700">【需截图】</span> Utilization Report | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |

性能结论建议写法：

> Timing Report 显示 CPU 时钟达到 ___ MHz，WNS 为 ___ ns，说明设计满足目标频率约束。RV32I 混合测试程序共完成 ___ 条指令，耗时 ___ 个周期，平均 CPI 为 ___。结合目标时钟频率，CPU 在该混合指令流下的等效指令吞吐约为 ___ MIPS。

## 6.3 特色功能测评结果

表 6-4 特色功能测评结果

| 特色功能 | 仿真证据 | 上板证据 | 结论 |
| --- | --- | --- | --- |
| 数据前递与暂停 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 连续相关指令波形 | 可选 | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 分支/跳转冲刷 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 错误路径不提交波形 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 自检通过码 | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |
| 数字孪生 MMIO | 可选 | <span style="color:#7030A0;font-weight:700">【需截图】</span> 开关/按键输入与 LED/数码管输出 | <span style="color:#C00000;font-weight:700">【需实测】</span> 待填写 |

# 7. 结论

本文围绕 KLDJ RV32I CPU 的功能正确性、指令集覆盖性、流水线行为、性能指标和上板可运行性建立了完整测评方案。仿真部分通过差分自检 testbench 覆盖 RV32I 37 条测评指令，能够自动检查 PC、寄存器堆和访存结果；上板部分通过数字孪生工程和 MMIO 外设输出，使 CPU 执行结果能够在硬件环境中直接观察。

最终提交时，可在补齐实测数据后形成如下结论：

> 经仿真和上板验证，KLDJ CPU 能够完整、准确地执行 RV32I 基础整数指令集中本次测评要求的 37 条指令。算术逻辑、访存、分支跳转和流水线相关场景均通过测试；Vivado 实现结果满足目标时钟频率要求；上板运行现象与仿真预期一致。因此，该自研 CPU 达到了本次 RV32I CPU 测评要求。

# 8. 后续填报检查清单

正式提交前按表 8-1 逐项检查。

表 8-1 最终填报检查清单

| 编号 | 项目 | 状态 |
| --- | --- | --- |
| C-1 | 填写 Vivado Simulation 版本；仿真时钟周期按 testbench 中 `#5` 得到 10 ns，如修改时钟再重新计算 | <span style="color:#C00000;font-weight:700">【需实测】</span> |
| C-2 | 插入仿真顶层设置截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| C-3 | 插入 RV32I 自检 summary 截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| C-4 | 填写 `total_cases`、`retired_steps`、`cycles`、CPI | <span style="color:#C00000;font-weight:700">【需实测】</span> |
| C-5 | 插入算术逻辑、访存、分支跳转关键波形 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| C-6 | 填写 FPGA 器件、bitstream 路径、下载工具版本 | <span style="color:#C00000;font-weight:700">【需实测】</span> |
| C-7 | 插入 Timing Report 和 Utilization Report | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| C-8 | 插入上板/数字孪生运行结果截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| C-9 | 用红框和箭头标注所有关键波形截图 | <span style="color:#7030A0;font-weight:700">【需截图】</span> |
| C-10 | 删除或处理不需要保留的彩色填报标记 | <span style="color:#C00000;font-weight:700">【需实测】</span> |

# 9. 附录

## 9.1 测试文件清单

表 9-1 仿真测试文件

| 用途 | 文件 |
| --- | --- |
| RV32I 差分 testbench | `kldj.srcs2/sim_1/imports/sim/rv32i_supported_instr_tb.sv` |
| CPU 顶层 | `kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v` |
| 宏定义 | `kldj.srcs2/sources_1/imports/rtl/define.v` |
| IF/ID/EX/MEM/WB 模块 | `KLDJ_ifu.v`, `KLDJ_idu.v`, `KLDJ_exu.v`, `KLDJ_lsu.v`, `KLDJ_wbu.v` |
| 寄存器堆与 ALU | `KLDJ_regfile.v`, `KLDJ_alu.v`, `alu_*.v`, `MuxKey*.v` |

表 9-2 上板工程文件

| 用途 | 文件 |
| --- | --- |
| Vivado 工程 | `digital_twin/digital_twin.xpr` |
| 板级顶层 | `digital_twin/digital_twin.srcs/sources_1/new/top.sv` |
| CPU 接入顶层 | `digital_twin/digital_twin.srcs/sources_1/new/student_top.sv` |
| 外设桥 | `digital_twin/digital_twin.srcs/sources_1/new/perip_bridge.sv` |
| DRAM/显示/串口 | `dram_driver.sv`, `display_seg.sv`, `seg7.sv`, `uart.sv`, `twin_controller.sv` |

## 9.2 高分呈现建议

1. 第 6 章尽量使用“三列表格”：左列写测试用例，中列放仿真波形和解释，右列放上板截图和解释。
2. 波形截图不要只贴原图，应使用红框、箭头和文字标出 `pc` 跳转地址、寄存器写入值、`mem_be`、`mem_rdata` 等关键信号。
3. 如果上板结果用 LED 表示，需要附表说明 LED 二进制值、十六进制值和含义。
4. 如果能用 UART 打印，建议打印 `PASS` 或 `Expected: xx, Actual: xx`，比单独 LED 更直观。
5. 不要把未实现的中断、AXI 或浮点功能写成特色功能。当前设计更适合突出五级流水线、冒险处理和数字孪生 MMIO 交互。
