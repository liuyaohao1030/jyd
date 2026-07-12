# KLDJ CPU 六级流水线（EX1/EX2）实施框架

## 1. 文档目的

本文档记录一个供后续实施的六级流水线改造框架。目标是在允许微架构周期变化和一定 IPC 损失的前提下，通过拆分现有 EX 阶段获得明显的主频提升。

当前五级结构：

```text
IF → ID → EX → MEM → WB
```

建议六级结构：

```text
IF → ID → EX1 → EX2 → MEM → WB
```

其中：

- **EX1**：数据相关检测、前递选择、最终操作数准备；
- **EX2**：ALU、分支判断、跳转目标、访存地址、CSR、MUL/DIV 和 BPU 更新；
- 所有不可撤销副作用放在 EX2 或更晚阶段；
- 第一版采用保守 hazard 策略，优先保证时序和正确性，之后再逐步恢复旁路以改善 IPC。

本文档是实施框架，不是可以直接替换现有 RTL 的完整补丁。

---

## 2. 改造动机

175 MHz 实现的最差 setup 路径从 EX/MEM 控制寄存器到 IFU PC 寄存器，数据路径延迟为 5.820 ns，其中：

```text
逻辑延迟：1.018 ns（17.491%）
布线延迟：4.802 ns（82.509%）
```

现有 EX 组合链大致为：

```text
ID/EX
  → EX/MEM、MEM/WB 相关性比较
  → 32 位 forwarding mux
  → 操作数用途选择
  → ALU/比较/移位
  → branch_taken
  → jump target
  → ex_bpu_ctrl
  → redirect/PC
```

EX1/EX2 边界可以把前递选择和实际执行拆成两个独立时序弧，比只给 `ex_redirect` 打拍更系统，也更容易建立一致的 hazard、flush 和副作用规则。

---

## 3. 推荐模块结构

```text
rtl/
├── KLDJ_top.v
├── stage/
│   ├── KLDJ_ifu.v
│   ├── KLDJ_idu.v
│   ├── KLDJ_ex1.v          # 可选，封装 EX1
│   ├── KLDJ_exu.v          # 作为 EX2
│   ├── KLDJ_lsu.v
│   └── KLDJ_wbu.v
└── pipe/
    ├── pipe_if_id.v
    ├── pipe_id_ex.v        # ID/EX1
    ├── ex_forward.v        # EX1 forwarding
    ├── ex1_hazard.v        # 新增 hazard unit
    ├── pipe_ex1_ex2.v      # 新增流水寄存器
    ├── ex_bpu_ctrl.v       # EX2 分支恢复
    ├── pipe_ex_mem.v       # EX2/MEM
    └── pipe_mem_wb.v
```

初期不必重命名现有文件：

- `pipe_id_ex.v` 继续作为 ID/EX1；
- `pipe_ex_mem.v` 继续作为 EX2/MEM；
- 只新增 `pipe_ex1_ex2.v` 和 `ex1_hazard.v`；
- 初期继续传递现有 `exu_op`、`alu_ctrl` 和 `ls_ctl`，不要同时进行控制编码重构。

---

## 4. 总体数据流

```text
                            ┌──────────────────────────┐
                            │          BPU             │
                            │ lookup IF / update EX2   │
                            └───────▲──────────┬───────┘
                                    │          │
┌────┐  ┌───────┐  ┌────┐  ┌───────┐  ┌─────┴──────┐
│ IF │→ │ IF/ID │→ │ ID │→ │ ID/EX1│→ │    EX1     │
└─▲──┘  └───────┘  └────┘  └───────┘  │ forwarding │
  │                                     │ operands   │
  │                                     └─────┬──────┘
  │                                           │
  │                                     ┌─────▼──────┐
  │                                     │  EX1/EX2   │
  │                                     └─────┬──────┘
  │                                           │
  │                                     ┌─────▼──────┐
  └──── redirect/correct_pc ────────────│    EX2     │
                                        │ ALU/branch │
                                        │ addr/CSR   │
                                        └─────┬──────┘
                                              │
                                        ┌─────▼──────┐
                                        │  EX2/MEM   │
                                        └─────┬──────┘
                                              │
                                        ┌─────▼──────┐
                                        │    MEM     │
                                        └─────┬──────┘
                                              │
                                        ┌─────▼──────┐
                                        │  MEM/WB    │
                                        └─────┬──────┘
                                              │
                                        ┌─────▼──────┐
                                        │    WB      │
                                        └────────────┘
```

---

## 5. EX1 的职责

EX1 只负责准备 EX2 所需的稳定输入，原则上不产生不可撤销副作用。

### 5.1 前递命中判断

把当前 `ex_forward.v` 中的比较放在 EX1：

```text
id_ex_rs1_addr == ex2_mem_rd_addr
id_ex_rs1_addr == mem_wb_rd_addr
id_ex_rs2_addr == ex2_mem_rd_addr
id_ex_rs2_addr == mem_wb_rd_addr
```

### 5.2 前递数据选择

第一版只从已经寄存的后级结果前递：

```text
EX2/MEM → EX1
MEM/WB  → EX1
```

不在第一版加入：

```text
EX2 组合 ALU 输出 → EX1
```

否则容易重新形成 EX2 ALU→EX1 mux→EX1/EX2 寄存器的长组合路径。

### 5.3 最终操作数准备

EX1 生成并锁存：

```text
ex1_data1
ex1_data2
ex1_data3
ex1_data4
ex1_store_wdata
```

### 5.4 可选预译码

第一版仍传递原始控制字段。行为稳定后，再考虑生成：

```text
is_branch
branch_kind
is_jal
is_jalr
is_load
is_store
mem_size
is_mul
is_div
is_csr
is_ecall
is_mret
result_class
```

不要在第一次新增流水级时同时重编码整个 `exu_op`。

---

## 6. 新增 EX1/EX2 流水寄存器

建议新增：

```text
rtl/pipe/pipe_ex1_ex2.v
```

### 6.1 建议字段

#### 指令身份

```text
ex1_ex2_valid
ex1_ex2_pc
ex1_ex2_snpc
ex1_ex2_rd_addr
```

#### 分支预测信息

```text
ex1_ex2_pred_taken
ex1_ex2_pred_target
ex1_ex2_pred_pht_idx
```

#### EX1 最终操作数

```text
ex1_ex2_data1
ex1_ex2_data2
ex1_ex2_data3
ex1_ex2_data4
ex1_ex2_store_wdata
```

#### 原有执行控制

```text
ex1_ex2_wb_ctl
ex1_ex2_exu_op
ex1_ex2_alu_ctrl
ex1_ex2_ls_ctl
```

#### CSR 控制

```text
ex1_ex2_csr_addr
ex1_ex2_csr_op
ex1_ex2_csr_zimm
```

### 6.2 接口框架

```verilog
`include "../define.v"

module pipe_ex1_ex2 #(
    parameter BPU_INDEX_WIDTH = 6
)(
     input  wire                         clk
    ,input  wire                         rst
    ,input  wire                         flush
    ,input  wire                         hold
    ,input  wire                         bubble

    ,input  wire                         id_ex_valid
    ,input  wire [`KLDJ_PC]              id_ex_pc
    ,input  wire [`KLDJ_PC]              id_ex_snpc
    ,input  wire [`KLDJ_REGADDR]         id_ex_rd_addr

    ,input  wire                         id_ex_pred_taken
    ,input  wire [`KLDJ_PC]              id_ex_pred_target
    ,input  wire [BPU_INDEX_WIDTH-1:0]   id_ex_pred_pht_idx

    ,input  wire [`KLDJ_DATA]            ex1_data1
    ,input  wire [`KLDJ_DATA]            ex1_data2
    ,input  wire [`KLDJ_DATA]            ex1_data3
    ,input  wire [`KLDJ_DATA]            ex1_data4
    ,input  wire [`KLDJ_DATA]            ex1_store_wdata

    ,input  wire                         id_ex_wb_ctl
    ,input  wire [17:0]                  id_ex_exu_op
    ,input  wire [9:0]                   id_ex_alu_ctrl
    ,input  wire [3:0]                   id_ex_ls_ctl

    ,input  wire [11:0]                  id_ex_csr_addr
    ,input  wire                         id_ex_csr_op
    ,input  wire [4:0]                   id_ex_csr_zimm

    ,output reg                          ex1_ex2_valid
    ,output reg  [`KLDJ_PC]              ex1_ex2_pc
    ,output reg  [`KLDJ_PC]              ex1_ex2_snpc
    ,output reg  [`KLDJ_REGADDR]         ex1_ex2_rd_addr

    ,output reg                          ex1_ex2_pred_taken
    ,output reg  [`KLDJ_PC]              ex1_ex2_pred_target
    ,output reg  [BPU_INDEX_WIDTH-1:0]   ex1_ex2_pred_pht_idx

    ,output reg  [`KLDJ_DATA]            ex1_ex2_data1
    ,output reg  [`KLDJ_DATA]            ex1_ex2_data2
    ,output reg  [`KLDJ_DATA]            ex1_ex2_data3
    ,output reg  [`KLDJ_DATA]            ex1_ex2_data4
    ,output reg  [`KLDJ_DATA]            ex1_ex2_store_wdata

    ,output reg                          ex1_ex2_wb_ctl
    ,output reg  [17:0]                  ex1_ex2_exu_op
    ,output reg  [9:0]                   ex1_ex2_alu_ctrl
    ,output reg  [3:0]                   ex1_ex2_ls_ctl

    ,output reg  [11:0]                  ex1_ex2_csr_addr
    ,output reg                          ex1_ex2_csr_op
    ,output reg  [4:0]                   ex1_ex2_csr_zimm
);

    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            ex1_ex2_valid         <= 1'b0;
            ex1_ex2_pred_taken    <= 1'b0;
            ex1_ex2_wb_ctl        <= 1'b0;
            ex1_ex2_exu_op        <= 18'b0;
            ex1_ex2_alu_ctrl      <= 10'b0;
            ex1_ex2_ls_ctl        <= 4'b0;
            ex1_ex2_csr_op        <= 1'b0;

            ex1_ex2_pc            <= `KLDJ_ZERO32;
            ex1_ex2_snpc          <= `KLDJ_ZERO32;
            ex1_ex2_rd_addr       <= 5'b0;
            ex1_ex2_pred_target   <= `KLDJ_ZERO32;
            ex1_ex2_pred_pht_idx  <= {BPU_INDEX_WIDTH{1'b0}};
            ex1_ex2_data1         <= `KLDJ_ZERO32;
            ex1_ex2_data2         <= `KLDJ_ZERO32;
            ex1_ex2_data3         <= `KLDJ_ZERO32;
            ex1_ex2_data4         <= `KLDJ_ZERO32;
            ex1_ex2_store_wdata   <= `KLDJ_ZERO32;
            ex1_ex2_csr_addr      <= 12'b0;
            ex1_ex2_csr_zimm      <= 5'b0;
        end else if (flush) begin
            // flush 必须高于 hold，杀掉 EX2 redirect 后面的年轻指令。
            ex1_ex2_valid         <= 1'b0;
            ex1_ex2_pred_taken    <= 1'b0;
            ex1_ex2_wb_ctl        <= 1'b0;
            ex1_ex2_exu_op        <= 18'b0;
            ex1_ex2_alu_ctrl      <= 10'b0;
            ex1_ex2_ls_ctl        <= 4'b0;
            ex1_ex2_csr_op        <= 1'b0;
        end else if (bubble) begin
            // EX1 consumer 保持在 ID/EX1，同时向 EX2 插入气泡。
            ex1_ex2_valid         <= 1'b0;
            ex1_ex2_pred_taken    <= 1'b0;
            ex1_ex2_wb_ctl        <= 1'b0;
            ex1_ex2_exu_op        <= 18'b0;
            ex1_ex2_alu_ctrl      <= 10'b0;
            ex1_ex2_ls_ctl        <= 4'b0;
            ex1_ex2_csr_op        <= 1'b0;
        end else if (!hold) begin
            ex1_ex2_valid         <= id_ex_valid;
            ex1_ex2_pc            <= id_ex_pc;
            ex1_ex2_snpc          <= id_ex_snpc;
            ex1_ex2_rd_addr       <= id_ex_rd_addr;

            ex1_ex2_pred_taken    <= id_ex_valid && id_ex_pred_taken;
            ex1_ex2_pred_target   <= id_ex_pred_target;
            ex1_ex2_pred_pht_idx  <= id_ex_pred_pht_idx;

            ex1_ex2_data1         <= ex1_data1;
            ex1_ex2_data2         <= ex1_data2;
            ex1_ex2_data3         <= ex1_data3;
            ex1_ex2_data4         <= ex1_data4;
            ex1_ex2_store_wdata   <= ex1_store_wdata;

            ex1_ex2_wb_ctl        <= id_ex_valid && id_ex_wb_ctl;
            ex1_ex2_exu_op        <= id_ex_exu_op;
            ex1_ex2_alu_ctrl      <= id_ex_alu_ctrl;
            ex1_ex2_ls_ctl        <= id_ex_ls_ctl;

            ex1_ex2_csr_addr      <= id_ex_csr_addr;
            ex1_ex2_csr_op        <= id_ex_valid && id_ex_csr_op;
            ex1_ex2_csr_zimm      <= id_ex_csr_zimm;
        end
    end

endmodule
```

实际实施时应匹配现有流水寄存器的注释、复位和赋值风格。

---

## 7. 顶层连接框架

### 7.1 EX1 forwarding

```verilog
ex_forward u_ex1_forward(
    .id_ex_valid          (id_ex_valid),
    .id_ex_rs1_addr       (id_ex_rs1_addr),
    .id_ex_rs2_addr       (id_ex_rs2_addr),
    .id_ex_rd_addr        (id_ex_rd_addr),
    .id_ex_rs1_ren        (id_ex_rs1_ren),
    .id_ex_rs2_ren        (id_ex_rs2_ren),
    .id_ex_exu_op         (id_ex_exu_op),

    .id_ex_data1          (id_ex_data1),
    .id_ex_data2          (id_ex_data2),
    .id_ex_data3          (id_ex_data3),
    .id_ex_data4          (id_ex_data4),
    .id_ex_rs1_data       (id_ex_rs1_data),
    .id_ex_rs2_data       (id_ex_rs2_data),

    .ex_mem_rd_addr       (ex_mem_rd_addr),
    .ex_mem_exu_res       (ex_mem_exu_res),
    .ex_mem_forward_valid (ex_mem_forward_valid),

    .mem_wb_rd_addr       (mem_wb_rd_addr),
    .mem_wb_wb_data       (mem_wb_wb_data),
    .mem_wb_forward_valid (mem_wb_forward_valid),

    .ex_data1             (ex1_data1),
    .ex_data2             (ex1_data2),
    .ex_data3             (ex1_data3),
    .ex_data4             (ex1_data4),
    .ex_store_wdata       (ex1_store_wdata),

    // 后续由新的 hazard unit 取代旧 load-use 逻辑。
    .load_use_stall       (legacy_load_use_stall)
);
```

### 7.2 EX1/EX2 流水寄存器

```verilog
pipe_ex1_ex2 #(
    .BPU_INDEX_WIDTH(BPU_INDEX_WIDTH)
) u_pipe_ex1_ex2(
    .clk                    (core_clk),
    .rst                    (core_rst),
    .flush                  (ex2_redirect),
    .hold                   (ex2_busy_stall),
    .bubble                 (ex1_dependency_stall),

    .id_ex_valid            (id_ex_valid),
    .id_ex_pc               (id_ex_pc),
    .id_ex_snpc             (id_ex_snpc),
    .id_ex_rd_addr          (id_ex_rd_addr),
    .id_ex_pred_taken       (id_ex_pred_taken),
    .id_ex_pred_target      (id_ex_pred_target),
    .id_ex_pred_pht_idx     (id_ex_pred_pht_idx),

    .ex1_data1              (ex1_data1),
    .ex1_data2              (ex1_data2),
    .ex1_data3              (ex1_data3),
    .ex1_data4              (ex1_data4),
    .ex1_store_wdata        (ex1_store_wdata),

    .id_ex_wb_ctl           (id_ex_wb_ctl),
    .id_ex_exu_op           (id_ex_exu_op),
    .id_ex_alu_ctrl         (id_ex_alu_ctrl),
    .id_ex_ls_ctl           (id_ex_ls_ctl),
    .id_ex_csr_addr         (id_ex_csr_addr),
    .id_ex_csr_op           (id_ex_csr_op),
    .id_ex_csr_zimm         (id_ex_csr_zimm),

    // 其余输出连接到 ex1_ex2_* 顶层信号。
    ...
);
```

### 7.3 EX2 执行

```verilog
KLDJ_exu exu2(
    .clk          (core_clk),
    .rst          (core_rst),
    .valid        (ex1_ex2_valid),

    .data1        (ex1_ex2_data1),
    .data2        (ex1_ex2_data2),
    .data3        (ex1_ex2_data3),
    .data4        (ex1_ex2_data4),

    .exu_op       (ex1_ex2_exu_op),
    .alu_ctrl     (ex1_ex2_alu_ctrl),

    .csr_addr     (ex1_ex2_csr_addr),
    .csr_op       (ex1_ex2_csr_op),
    .csr_zimm     (ex1_ex2_csr_zimm),
    ...
);
```

---

## 8. 分支恢复与 flush

`ex_bpu_ctrl` 必须全部消费 EX1/EX2 中的指令信息：

```verilog
ex_bpu_ctrl #(
    .BPU_INDEX_WIDTH(BPU_INDEX_WIDTH)
) u_ex2_bpu_ctrl(
    .id_ex_valid        (ex1_ex2_valid),
    .id_ex_pc           (ex1_ex2_pc),
    .id_ex_snpc         (ex1_ex2_snpc),
    .id_ex_pred_taken   (ex1_ex2_pred_taken),
    .id_ex_pred_target  (ex1_ex2_pred_target),
    .id_ex_pred_pht_idx (ex1_ex2_pred_pht_idx),
    .id_ex_exu_op       (ex1_ex2_exu_op),

    .exu_jump_raw       (ex2_jump),
    .exu_jump_pc_raw    (ex2_jump_pc),
    .is_ecall           (ex2_is_ecall),
    .is_mret            (ex2_is_mret),
    .mtvec_val          (mtvec_val),

    .ex_actual_taken    (ex2_actual_taken),
    .ex_correct_pc      (ex2_correct_pc),
    .ex_redirect        (ex2_redirect),

    .bpu_update_valid   (bpu_update_valid),
    .bpu_update_pc      (bpu_update_pc),
    .bpu_update_pht_idx (bpu_update_pht_idx),
    .bpu_update_taken   (bpu_update_taken),
    .bpu_update_target  (bpu_update_target)
);
```

IFU 改用 EX2 恢复信号：

```verilog
.redirect    (ex2_redirect)
.redirect_pc(ex2_correct_pc)
```

EX2 redirect 时，必须 flush 三处年轻状态：

```text
IF/ID
ID/EX1
EX1/EX2
```

产生 redirect 的 EX2 指令本身必须允许正常进入 EX2/MEM，不能被自己的 redirect 杀掉。

统一优先级：

```text
reset > redirect/flush > stall/hold > normal advance
```

---

## 9. 暂停和气泡控制

不要继续用单个 `frontend_stall` 表示所有情况，建议拆分：

```verilog
wire ex1_dependency_stall;
wire ex2_busy_stall;
wire frontend_hold;
wire id_ex1_hold;
wire ex1_ex2_hold;
wire id_ex1_bubble;
wire ex1_ex2_bubble;
```

推荐控制表：

| 原因 | PC/IFID | ID/EX1 | EX1/EX2 | EX2/MEM |
|---|---|---|---|---|
| EX1 dependency stall | hold | hold | bubble | advance |
| EX2 MUL/DIV busy | hold | hold | hold | bubble/按现有协议 |
| EX2 redirect | redirect/flush | flush | flush | 当前 EX2 正常推进 |
| reset | reset | reset | reset | reset |

关键区别：

- dependency stall 必须让生产者继续推进，同时保持消费者；
- 因此 ID/EX1 是 hold，EX1/EX2 是 bubble；
- 如果 dependency stall 时同时 hold EX1/EX2，会造成生产者无法离开、消费者永久等待的死锁。

---

## 10. 第一版 hazard unit

建议新增：

```text
rtl/pipe/ex1_hazard.v
```

框架：

```verilog
module ex1_hazard(
     input  wire         id_ex_valid
    ,input  wire [4:0]   id_ex_rs1_addr
    ,input  wire [4:0]   id_ex_rs2_addr
    ,input  wire         id_ex_rs1_ren
    ,input  wire         id_ex_rs2_ren

    ,input  wire         ex1_ex2_valid
    ,input  wire [4:0]   ex1_ex2_rd_addr
    ,input  wire         ex1_ex2_wb_ctl

    ,input  wire         ex2_mem_valid
    ,input  wire [4:0]   ex2_mem_rd_addr
    ,input  wire         ex2_mem_wb_ctl
    ,input  wire         ex2_mem_load_op

    ,output wire         ex1_dependency_stall
);

    wire depends_on_ex2 =
        id_ex_valid &&
        ex1_ex2_valid &&
        ex1_ex2_wb_ctl &&
        (ex1_ex2_rd_addr != 5'd0) &&
        ((id_ex_rs1_ren && id_ex_rs1_addr == ex1_ex2_rd_addr) ||
         (id_ex_rs2_ren && id_ex_rs2_addr == ex1_ex2_rd_addr));

    wire depends_on_mem_load =
        id_ex_valid &&
        ex2_mem_valid &&
        ex2_mem_wb_ctl &&
        ex2_mem_load_op &&
        (ex2_mem_rd_addr != 5'd0) &&
        ((id_ex_rs1_ren && id_ex_rs1_addr == ex2_mem_rd_addr) ||
         (id_ex_rs2_ren && id_ex_rs2_addr == ex2_mem_rd_addr));

    assign ex1_dependency_stall =
        depends_on_ex2 || depends_on_mem_load;

endmodule
```

这是保守第一版：

```text
EX2 producer → EX1 consumer
```

统一 stall 一拍。后续加入 EX2→EX1 bypass 后，再只对结果尚未就绪的类型 stall。

---

## 11. EX1 forwarding 框架

第一版只前递已寄存结果：

```verilog
wire ex2_mem_rs1_hit =
    id_ex_rs1_ren &&
    ex2_mem_forward_valid &&
    (id_ex_rs1_addr == ex2_mem_rd_addr);

wire mem_wb_rs1_hit =
    id_ex_rs1_ren &&
    mem_wb_forward_valid &&
    (id_ex_rs1_addr == mem_wb_rd_addr);

assign ex1_rs1_data =
    ex2_mem_rs1_hit ? ex2_mem_exu_res :
    mem_wb_rs1_hit  ? mem_wb_wb_data  :
                      id_ex_rs1_data;
```

rs2 同理。

hazard unit 已阻止消费者在依赖当前 EX2 生产者时进入 EX2，因此不需要第一版的 EX2 组合结果旁路。

---

## 12. Load-use hazard

增加 EX1/EX2 后，load 数据可能到 MEM 或 MEM/WB 才可用，load-use penalty 可能增加。

至少检查：

```text
ID/EX1 consumer 依赖 EX1/EX2 load
ID/EX1 consumer 依赖 EX2/MEM load，且数据尚未返回
```

第一版可以保守 stall，后续再加入：

```text
MEM load result → EX1
```

旁路减少等待。

必须结合 `new/dram_driver.sv` 的 BRAM 读延迟和 `mem_rdata` 有效周期重新确定等待拍数。

---

## 13. EX2/MEM 连接

原 `pipe_ex_mem` 改为消费 EX1/EX2 状态：

```verilog
pipe_ex_mem u_pipe_ex2_mem(
    .clk                (core_clk),
    .rst                (core_rst),

    .id_ex_valid        (ex1_ex2_valid),
    .id_ex_pc           (ex1_ex2_pc),
    .id_ex_rd_addr      (ex1_ex2_rd_addr),
    .id_ex_wb_ctl       (ex1_ex2_wb_ctl),
    .id_ex_exu_op       (ex1_ex2_exu_op),
    .id_ex_ls_ctl       (ex1_ex2_ls_ctl),

    .exu_data           (ex2_data),
    .ex_mem_addr_i      (ex2_mem_addr),
    .ex_store_wdata     (ex1_ex2_store_wdata),
    .ex_stall           (ex2_busy_stall),
    ...
);
```

redirect 周期当前 EX2 指令应正常推进，flush 只清除更年轻的级。

---

## 14. Memory request 的位置

现有 `ex_mem_req_ctrl` 必须改用 EX2 数据：

```verilog
ex_mem_req_ctrl u_ex2_mem_req_ctrl(
    .id_ex_valid     (ex1_ex2_valid),
    .ex_stall        (ex2_busy_stall),
    .id_ex_exu_op    (ex1_ex2_exu_op),
    .id_ex_ls_ctl    (ex1_ex2_ls_ctl),
    .ex_mem_addr_pre (ex2_mem_addr),
    .ex_store_wdata  (ex1_ex2_store_wdata),
    ...
);
```

EX1 不能提前产生有效 `mem_we` 或 MMIO write，否则错误路径指令可能在 EX2 分支恢复前产生不可撤销副作用。

---

## 15. CSR、ECALL 和 MRET

CSR 和异常副作用必须和 EX2 指令对齐：

```verilog
KLDJ_csr u_csr(
    .csr_raddr (ex1_ex2_csr_addr),
    .csr_we    (ex2_csr_we && ex1_ex2_valid),
    .csr_waddr (ex1_ex2_csr_addr),
    .csr_wdata (ex2_csr_wdata),

    .ecall_en  (ex2_is_ecall && ex1_ex2_valid),
    .ecall_pc  (ex1_ex2_pc),

    .mret_en   (ex2_is_mret && ex1_ex2_valid),
    ...
);
```

不能保留对原 `id_ex_*` CSR 信号的副作用引用，否则会把 EX1 的年轻指令状态与 EX2 的老指令混在一起。

---

## 16. MUL/DIV 控制

第一版建议继续放在 EX2：

```verilog
assign ex2_busy_stall = ex2_mul_stall || ex2_div_stall;
```

当 EX2 busy：

```text
PC/IFID：hold
ID/EX1：hold
EX1/EX2：hold
EX2/MEM：插入 bubble 或沿用当前协议
```

必须保证：

1. EX1/EX2 hold 时不会重复启动 MUL/DIV；
2. done 周期允许 EX2/MEM 捕获结果；
3. 捕获结果后 EX1/EX2 才接收下一条指令；
4. 年轻指令不能在 busy 期间越过 EX2；
5. redirect 不能错误清除产生 redirect 的当前 EX2 指令。

可能需要定义：

```verilog
wire ex2_accept;
wire ex2_fire;
```

具体规则需结合当前 `mul_ip_wrapper`、`div_ip_wrapper` 的 `start/busy/done` 协议确定。

---

## 17. 不可撤销副作用的位置

以下操作必须保留在 EX2 或更晚阶段：

```text
mem_we
MMIO write
CSR write
ECALL trap state update
MRET state update
BPU update
性能 instret
寄存器写回
```

EX1 只做组合准备和 hazard/forwarding，不能执行这些副作用。

---

## 18. 性能计数器与 commit

建议重新定义事件所属阶段：

| 事件 | 建议位置 |
|---|---|
| cycle | 不变 |
| instret | WB commit |
| frontend stall | PC/IFID 实际 hold |
| dependency stall | EX1 hazard |
| mul/div stall | EX2 busy |
| redirect | EX2 redirect |
| load/store | EX2 发出有效请求 |

示例：

```verilog
wire perf_event_redirect = ex2_redirect;

wire perf_event_load =
    ex1_ex2_valid &&
    !ex2_busy_stall &&
    ex2_req_load;
```

新增流水级和 stall 后，性能计数值的微架构语义会变化，这是预期行为。

---

## 19. 关键控制不变量

实施和审查时应持续检查：

1. 每条有效指令最多进入 EX2 一次；
2. 每条有效指令最多写寄存器一次；
3. 每个 store/MMIO write 最多发出一次；
4. 每个 CSR write 最多执行一次；
5. 每个 BPU update 最多执行一次；
6. redirect 当拍的 EX2 指令允许正常完成；
7. redirect 杀死所有比 EX2 更年轻的指令；
8. flush 优先于 hold；
9. dependency stall 允许更老指令继续推进；
10. busy stall 保持正在执行的 EX2 指令；
11. x0 永远不产生依赖 stall；
12. load 数据未就绪前不能把地址作为 load 数据前递；
13. EX1 不产生不可撤销副作用；
14. PC、flush、redirect target 和 BPU update 来自同一条 EX2 指令；
15. 连续分支不会复用上一条分支的预测元数据；
16. store address 和 store data 的前递独立且都正确；
17. redirect 与 dependency stall 同周期时，redirect 必须优先；
18. EX2 busy 期间不得重复启动 MUL/DIV 或重复提交副作用。

---

## 20. 分阶段实施建议

### 阶段 1：只建立流水结构

1. 新建 `pipe_ex1_ex2.v`；
2. 在 `KLDJ_top.v` 声明完整 `ex1_ex2_*` 信号；
3. EX forwarding 输出接入 EX1/EX2；
4. EXU 改为消费 `ex1_ex2_*`；
5. `ex_bpu_ctrl` 改为消费 `ex1_ex2_*`；
6. `pipe_ex_mem` 改为消费 `ex1_ex2_*`；
7. CSR 和 memory request 移到 EX2；
8. redirect flush 扩展到 EX1/EX2；
9. 暂时对所有 EX2 dependency 保守 stall 一拍；
10. 暂不改 `exu_op` 编码，不改 BPU，不改 `new` 外围模块。

### 阶段 2：补全 hazard

覆盖：

```text
ALU → ALU
ALU → branch
ALU → store address
ALU → store data
load → ALU
load → branch
load → store
CSR → consumer
JAL/JALR link register → consumer
MUL/DIV → consumer
```

### 阶段 3：恢复 IPC

逐步增加：

1. EX2 simple ALU result → EX1 bypass；
2. MEM load result → EX1 bypass；
3. `result_ready` 分类；
4. 只对尚未就绪的结果 stall；
5. 对 branch、store address 和 store data 分别确认旁路。

每加入一种 bypass，都要重新检查是否重建长组合路径。

### 阶段 4：控制预译码与扇出优化

行为稳定后，再引入：

```text
branch_kind
is_jump
is_memory
is_mul_div
result_class
```

逐步替代 EX2 内部重复的 `exu_op` 比较。

---

## 21. 不建议的实现方式

1. **只寄存 `ex_redirect`**：容易导致 PC、flush、BPU update 和副作用错位；
2. **只在 ALU 输出后增加一级**：前递和分支比较长路径可能仍然存在；
3. **第一版加入 EX2 组合旁路**：容易抵消新增流水级的时序收益；
4. **同时重编码 `exu_op`**：会把流水改造和控制重构风险叠加；
5. **同时修改 `new/dram_driver`**：CPU 内部周期和外围 memory latency 同时变化，难以定位错误；
6. **让 EX1 发出 store/CSR/BPU 副作用**：错误路径指令可能提前修改状态；
7. **dependency stall 时 hold EX1/EX2**：容易形成生产者无法推进的死锁；
8. **hold 优先于 redirect**：错误路径指令可能被保留并继续执行。

---

## 22. 预期收益和代价

### 可能收益

拆分后：

```text
ID/EX1 → EX1/EX2
```

主要包含：

- hazard compare；
- forwarding mux；
- operand select。

而：

```text
EX1/EX2 → EX2/MEM 或 IFU
```

主要包含：

- ALU/branch compare；
- branch target；
- redirect；
- PC mux。

相比当前约 5.8 ns 的长链，这种结构更有机会显著提高 Fmax。实际提升取决于综合、布局、布线、旁路策略和新关键路径位置，不能仅凭结构保证具体频率。

### 预期代价

- 分支错误预测 penalty 可能增加一拍；
- 保守第一版中，连续相关 ALU 指令会 stall；
- load-use penalty 可能增加；
- MUL/DIV hold 控制需要重构；
- performance counter 的 stall/redirect 统计语义变化；
- 增加流水寄存器和控制网络资源。

如果目标优先级是“主频显著提升，高于 IPC”，这是推荐路线。若目标是严格保持原 CPI/周期行为，则不应增加该流水级。

---

## 23. 实施前检查清单

开始修改前应先确认：

- [ ] 当前所有 `id_ex_*` 使用点已经列出；
- [ ] 哪些使用点应改为 `ex1_ex2_*` 已标记；
- [ ] EX1 不产生任何状态副作用；
- [ ] EX2 redirect 的 flush 范围明确；
- [ ] redirect 与 stall 的优先级明确；
- [ ] EX2/MEM 在 redirect 周期仍捕获当前 EX2 指令；
- [ ] load 数据实际有效周期已结合 `dram_driver` 确定；
- [ ] MUL/DIV `start/busy/done` 周期已画出；
- [ ] CSR/ECALL/MRET 全部与 EX2 元数据对齐；
- [ ] BPU update 全部与 EX2 分支对齐；
- [ ] store address 和 store data hazard 均已覆盖；
- [ ] x0 依赖被排除；
- [ ] performance counter 的新语义已记录；
- [ ] 第一版不同时修改 BPU、DRAM、MMIO 和控制编码。

---

## 24. 总结

建议采用正式的 EX1/EX2 六级流水结构：

```text
IF → ID → EX1 → EX2 → MEM → WB
```

核心设计原则：

1. EX1 负责 forwarding 和操作数准备；
2. EX2 负责 ALU、分支、地址、CSR 和副作用；
3. EX1/EX2 是统一的指令流水边界，而不是特殊 redirect 寄存器；
4. 第一版对 EX2 依赖保守 stall，优先保证时序；
5. redirect 同时 flush IF/ID、ID/EX1 和 EX1/EX2；
6. flush 优先于 hold；
7. 产生 redirect 的 EX2 指令正常推进；
8. 所有不可撤销副作用留在 EX2 或更晚；
9. 功能稳定后再逐步增加旁路和预译码以恢复 IPC。
