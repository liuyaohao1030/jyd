`include "define.v"

module KLDJ_top(
     input wire                  clk
    ,input wire                  rst
    ,input wire [`KLDJ_INST]     tb_if_inst
    ,output wire [`KLDJ_PC]      tb_if_pc
    ,output wire                 tb_ex_jump
    ,output wire [`KLDJ_PC]      tb_ex_jump_pc
    ,output wire [`KLDJ_DATA]    tb_ex_res
    ,output wire [`KLDJ_DATA]    mem_addr
    ,output wire [`KLDJ_DATA]    mem_wdata
    ,output wire                 mem_we
    ,output wire [3:0]           mem_be
    ,input  wire [`KLDJ_DATA]    mem_rdata
    ,output wire                 core_clk_o
    // Performance counter outputs
    ,output wire [31:0]          perf_cycle_count
    ,output wire [31:0]          perf_instret_count
    ,output wire [31:0]          perf_frontend_stall_count
    ,output wire [31:0]          perf_load_use_stall_count
    ,output wire [31:0]          perf_mul_stall_count
    ,output wire [31:0]          perf_div_stall_count
    ,output wire [31:0]          perf_redirect_count
    ,output wire [31:0]          perf_load_count
    ,output wire [31:0]          perf_store_count
);

    localparam [`KLDJ_INST] KLDJ_NOP = 32'h00000013;
    localparam BPU_INDEX_WIDTH = 6;

    // Clock and reset
    (* mark_debug = "true" *)wire                         core_clk;
    (* mark_debug = "true" *)wire                         core_locked;
    (* mark_debug = "true" *) wire                         core_rst;

    assign core_clk      = clk;
    assign core_locked   = 1'b1;
    assign core_rst      = rst | ~core_locked;
    assign core_clk_o    = core_clk;

    // IF stage wires
    wire [`KLDJ_INST]            if_inst;
    (* mark_debug = "true" *) wire [`KLDJ_PC]              if_pc;
    wire [`KLDJ_PC]              if_snpc;
    wire                         bpu_pred_taken;
    wire [`KLDJ_PC]              bpu_pred_target;
    wire                         if_static_jal;
    wire [`KLDJ_IMM]             if_static_jal_imm;
    wire [`KLDJ_PC]              if_static_jal_target;
    wire                         if_pred_taken;
    wire [`KLDJ_PC]              if_pred_target;
    wire [BPU_INDEX_WIDTH-1:0]   if_pred_pht_idx;
    wire                         if_btb_hit;

    // IF/ID pipeline register outputs
    wire                         if_id_valid;
    wire [`KLDJ_INST]            if_id_inst;
    wire [`KLDJ_PC]              if_id_pc;
    wire [`KLDJ_PC]              if_id_snpc;
    wire                         if_id_pred_taken;
    wire [`KLDJ_PC]              if_id_pred_target;
    wire [BPU_INDEX_WIDTH-1:0]   if_id_pred_pht_idx;

    // ID stage wires
    wire [`KLDJ_REGADDR]         id_reg_rs1_addr;
    wire [`KLDJ_REGADDR]         id_reg_rs2_addr;
    wire [`KLDJ_REGADDR]         id_reg_rd_addr;
    wire                         id_reg_rs1_ren;
    wire                         id_reg_rs2_ren;
    wire [3:0]                   id_ls_ctl;
    wire                         id_wb_ctl;
    wire [17:0]                  id_exu_op;
    wire [9:0]                   id_alu_ctrl;
    wire [`KLDJ_DATA]            id_data1;
    wire [`KLDJ_DATA]            id_data2;
    wire [`KLDJ_DATA]            id_data3;
    wire [`KLDJ_DATA]            id_data4;
    // CSR signals from ID
    wire [11:0]                  id_csr_addr;
    wire                         id_csr_op;
    wire [4:0]                   id_csr_zimm;

    // ID/EX pipeline register outputs
    wire                         id_ex_valid;
    wire [`KLDJ_PC]              id_ex_pc;
    wire [`KLDJ_PC]              id_ex_snpc;
    wire                         id_ex_pred_taken;
    wire [`KLDJ_PC]              id_ex_pred_target;
    wire [BPU_INDEX_WIDTH-1:0]   id_ex_pred_pht_idx;
    wire [`KLDJ_REGADDR]         id_ex_rs1_addr;
    wire [`KLDJ_REGADDR]         id_ex_rs2_addr;
    wire [`KLDJ_REGADDR]         id_ex_rd_addr;
    wire                         id_ex_rs1_ren;
    wire                         id_ex_rs2_ren;
    wire                         id_ex_wb_ctl;
    wire [17:0]                  id_ex_exu_op;
    wire [9:0]                   id_ex_alu_ctrl;
    wire [3:0]                   id_ex_ls_ctl;
    wire [`KLDJ_DATA]            id_ex_data1;
    wire [`KLDJ_DATA]            id_ex_data2;
    wire [`KLDJ_DATA]            id_ex_data3;
    wire [`KLDJ_DATA]            id_ex_data4;
    wire [`KLDJ_DATA]            id_ex_rs1_data;
    wire [`KLDJ_DATA]            id_ex_rs2_data;
    wire                         id_ex_load_op;
    // CSR signals from ID/EX
    wire [11:0]                  id_ex_csr_addr;
    wire                         id_ex_csr_op;
    wire [4:0]                   id_ex_csr_zimm;

    // EX1 stage wires (forwarding outputs)
    wire [`KLDJ_DATA]            ex1_data1;
    wire [`KLDJ_DATA]            ex1_data2;
    wire [`KLDJ_DATA]            ex1_data3;
    wire [`KLDJ_DATA]            ex1_data4;
    wire [`KLDJ_DATA]            ex1_store_wdata;
    wire [`KLDJ_DATA]            ex1_rs1_data;
    wire [`KLDJ_DATA]            ex1_rs2_data;
    (* mark_debug = "true" *) wire                         ex1_dependency_stall;

    // EX1/EX2 pipeline register outputs
    (* mark_debug = "true" *) wire                         ex1_ex2_valid;
    wire [`KLDJ_PC]              ex1_ex2_pc;
    wire [`KLDJ_PC]              ex1_ex2_snpc;
    wire                         ex1_ex2_pred_taken;
    wire [`KLDJ_PC]              ex1_ex2_pred_target;
    wire [BPU_INDEX_WIDTH-1:0]   ex1_ex2_pred_pht_idx;
    wire [`KLDJ_REGADDR]         ex1_ex2_rd_addr;
    wire                         ex1_ex2_wb_ctl;
    wire [17:0]                  ex1_ex2_exu_op;
    wire [9:0]                   ex1_ex2_alu_ctrl;
    wire [3:0]                   ex1_ex2_ls_ctl;
    wire [`KLDJ_DATA]            ex1_ex2_data1;
    wire [`KLDJ_DATA]            ex1_ex2_data2;
    wire [`KLDJ_DATA]            ex1_ex2_data3;
    wire [`KLDJ_DATA]            ex1_ex2_data4;
    wire [`KLDJ_DATA]            ex1_ex2_store_wdata;
    wire [11:0]                  ex1_ex2_csr_addr;
    wire                         ex1_ex2_csr_op;
    wire [4:0]                   ex1_ex2_csr_zimm;
    wire                         ex1_ex2_load_op;

    // EX2 stage wires
    wire                         exu_jump_raw;
    wire [`KLDJ_PC]              exu_jump_pc_raw;
    wire [`KLDJ_DATA]            exu_data;
    wire [`KLDJ_DATA]            ex2_mem_addr_pre;
    (* mark_debug = "true" *) wire                         ex_redirect;
    wire                         ex_actual_taken;
    wire [`KLDJ_PC]              ex_correct_pc;
    wire                         bpu_update_valid;
    wire [`KLDJ_PC]              bpu_update_pc;
    wire [BPU_INDEX_WIDTH-1:0]   bpu_update_pht_idx;
    wire                         bpu_update_taken;
    wire [`KLDJ_PC]              bpu_update_target;
    wire                         div_stall;
    wire                         mul_stall;
    (* mark_debug = "true" *) wire                         ex2_stall;
    wire                         frontend_stall;

    // CSR module wires
    wire [31:0]                  csr_rdata;
    wire                         csr_we;
    wire [31:0]                  csr_wdata;
    wire                         is_ecall;
    wire                         is_mret;
    wire [31:0]                  mret_pc;
    wire [31:0]                  mtvec_val;

    // EX2/MEM pipeline register outputs (renamed from ex_mem_* to ex2_mem_*)
    (* mark_debug = "true" *) wire                         ex2_mem_valid;
    wire [`KLDJ_PC]              ex2_mem_pc;
    wire [`KLDJ_REGADDR]         ex2_mem_rd_addr;
    wire                         ex2_mem_wb_ctl;
    wire [17:0]                  ex2_mem_exu_op;
    wire [3:0]                   ex2_mem_ls_ctl;
    wire [`KLDJ_DATA]            ex2_mem_exu_res;
    wire [`KLDJ_DATA]            ex2_mem_mem_addr;
    wire [`KLDJ_DATA]            ex2_mem_store_wdata;
    wire                         ex2_mem_load_op;
    wire                         ex2_mem_forward_valid;

    // MEM stage wires
    wire [`KLDJ_DATA]            mem_stage_wb_data;
    wire                         mem_stage_wb_ctl;
    wire [`KLDJ_DATA]            mem_addr_memstage_unused;
    wire [`KLDJ_DATA]            mem_wdata_memstage_unused;
    wire                         mem_we_memstage_unused;
    wire [3:0]                   mem_be_memstage_unused;

    // EX-stage memory request wires

    // Debug wires for memory interface (marked for ILA)
    (* mark_debug = "true" *) wire [`KLDJ_DATA]            dbg_mem_addr;
    (* mark_debug = "true" *) wire                         dbg_mem_we;
    (* mark_debug = "true" *) wire [`KLDJ_DATA]            dbg_mem_rdata;
    assign dbg_mem_addr  = mem_addr;
    assign dbg_mem_we    = mem_we;
    assign dbg_mem_rdata = mem_rdata;

    // MEM/WB pipeline register outputs
    (* mark_debug = "true" *) wire                         mem_wb_valid;
    wire [`KLDJ_PC]              mem_wb_pc;
    wire [`KLDJ_REGADDR]         mem_wb_rd_addr;
    wire                         mem_wb_wb_ctl;
    (* mark_debug = "true" *) wire [`KLDJ_DATA]            mem_wb_wb_data;
    wire                         mem_wb_forward_valid;

    // WB wires
    wire [`KLDJ_DATA]            wb_reg_rd_data;
    wire                         wb_wen;

    // WB commit observation point outputs
    wire                         wb_commit_valid;
    wire [`KLDJ_PC]              wb_commit_pc;
    wire [`KLDJ_REGADDR]         wb_commit_rd_addr;
    wire                         wb_commit_wb_ctl;
    wire [`KLDJ_DATA]            wb_commit_wb_data;

    // Regfile wires
    wire [`KLDJ_REG]             reg_id_rs1_data;
    wire [`KLDJ_REG]             reg_id_rs2_data;

    // IF-stage static JAL prediction.  JAL is unconditional, so the
    // instruction-encoded target is more reliable than a possibly stale BTB.
    assign if_static_jal        = (if_inst[6:2] == `KLDJ_JAL) && (if_inst[1:0] == 2'b11);
    assign if_static_jal_imm    = {{12{if_inst[31]}}, if_inst[19:12], if_inst[20], if_inst[30:21], 1'b0};
    assign if_static_jal_target = if_pc + if_static_jal_imm;
    assign if_pred_taken        = if_static_jal || bpu_pred_taken;
    assign if_pred_target       = if_static_jal ? if_static_jal_target : bpu_pred_target;

    // ========================================================
    // Module instantiations
    // ========================================================

    // Branch prediction unit
    bpu #(
         .INDEX_WIDTH  (BPU_INDEX_WIDTH)
    ) u_bpu(
        .clk          (core_clk          )
        ,.rst          (core_rst          )
        ,.lookup_pc    (if_pc             )
        ,.pred_taken   (bpu_pred_taken    )
        ,.pred_target  (bpu_pred_target   )
        ,.btb_hit      (if_btb_hit        )
        ,.lookup_pht_idx(if_pred_pht_idx  )
        ,.update_valid (bpu_update_valid  )
        ,.update_pc    (bpu_update_pc     )
        ,.update_pht_idx(bpu_update_pht_idx)
        ,.update_taken (bpu_update_taken  )
        ,.update_target(bpu_update_target )
    );

    // Select jump target: ecall jumps to mtvec, otherwise use EXU result
    wire [31:0] redirect_pc = ex_correct_pc;

    // IF stage
    KLDJ_ifu ifu0(
         .clk     (core_clk          )
        ,.rst     (core_rst          )
        ,.hold    (frontend_stall    )
        ,.redirect   (ex_redirect       )
        ,.redirect_pc(redirect_pc       )
        ,.pred_taken (if_pred_taken     )
        ,.pred_target(if_pred_target    )
        ,.inst_i  (tb_if_inst        )
        ,.inst_o  (if_inst           )
        ,.pc_o    (if_pc             )
        ,.snpc    (if_snpc           )
    );

    // IF/ID pipeline register
    pipe_if_id #(
         .BPU_INDEX_WIDTH(BPU_INDEX_WIDTH)
    ) u_pipe_if_id(
         .clk             (core_clk          )
        ,.rst             (core_rst          )
        ,.if_inst         (if_inst           )
        ,.if_pc           (if_pc             )
        ,.if_snpc         (if_snpc           )
        ,.if_pred_taken   (if_pred_taken     )
        ,.if_pred_target  (if_pred_target    )
        ,.if_pred_pht_idx (if_pred_pht_idx   )
        ,.ex_redirect     (ex_redirect       )
        ,.load_use_stall  (frontend_stall    )
        ,.if_id_valid     (if_id_valid       )
        ,.if_id_inst      (if_id_inst        )
        ,.if_id_pc        (if_id_pc          )
        ,.if_id_snpc      (if_id_snpc        )
        ,.if_id_pred_taken(if_id_pred_taken  )
        ,.if_id_pred_target(if_id_pred_target)
        ,.if_id_pred_pht_idx(if_id_pred_pht_idx)
    );

    // ID stage
    KLDJ_idu idu1(
         .inst_i      (if_id_valid ? if_id_inst : KLDJ_NOP)
        ,.pc_i        (if_id_pc                         )
        ,.snpc        (if_id_snpc                       )
        ,.rs1_addr    (id_reg_rs1_addr                  )
        ,.rs1_ren     (id_reg_rs1_ren                   )
        ,.rs1_data    (reg_id_rs1_data                  )
        ,.rs2_addr    (id_reg_rs2_addr                  )
        ,.rs2_ren     (id_reg_rs2_ren                   )
        ,.rs2_data    (reg_id_rs2_data                  )
        ,.rd_addr     (id_reg_rd_addr                   )
        ,.exu_op      (id_exu_op                        )
        ,.alu_ctrl    (id_alu_ctrl                      )
        ,.wbctl_op    (id_wb_ctl                        )
        ,.data1       (id_data1                         )
        ,.data2       (id_data2                         )
        ,.data3       (id_data3                         )
        ,.data4       (id_data4                         )
        ,.id_ls_ctl   (id_ls_ctl                        )
        ,.csr_addr    (id_csr_addr                      )
        ,.csr_op      (id_csr_op                        )
        ,.csr_zimm    (id_csr_zimm                      )
    );

    // ID/EX pipeline register
    pipe_id_ex #(
         .BPU_INDEX_WIDTH(BPU_INDEX_WIDTH)
    ) u_pipe_id_ex(
         .clk             (core_clk          )
        ,.rst             (core_rst          )
        ,.if_id_valid     (if_id_valid       )
        ,.if_id_pc        (if_id_pc          )
        ,.if_id_snpc      (if_id_snpc        )
        ,.if_id_pred_taken(if_id_pred_taken  )
        ,.if_id_pred_target(if_id_pred_target)
        ,.if_id_pred_pht_idx(if_id_pred_pht_idx)
        ,.id_reg_rs1_addr (id_reg_rs1_addr   )
        ,.id_reg_rs2_addr (id_reg_rs2_addr   )
        ,.id_reg_rd_addr  (id_reg_rd_addr    )
        ,.id_reg_rs1_ren  (id_reg_rs1_ren    )
        ,.id_reg_rs2_ren  (id_reg_rs2_ren    )
        ,.id_wb_ctl       (id_wb_ctl         )
        ,.id_exu_op       (id_exu_op         )
        ,.id_alu_ctrl     (id_alu_ctrl       )
        ,.id_ls_ctl       (id_ls_ctl         )
        ,.id_data1        (id_data1          )
        ,.id_data2        (id_data2          )
        ,.id_data3        (id_data3          )
        ,.id_data4        (id_data4          )
        ,.reg_id_rs1_data (reg_id_rs1_data   )
        ,.reg_id_rs2_data (reg_id_rs2_data   )
        ,.ex1_rs1_data    (ex1_rs1_data      )
        ,.ex1_rs2_data    (ex1_rs2_data      )
        ,.id_csr_addr     (id_csr_addr       )
        ,.id_csr_op       (id_csr_op         )
        ,.id_csr_zimm     (id_csr_zimm       )
        ,.ex_redirect     (ex_redirect       )
        ,.load_use_stall  (ex1_dependency_stall)
        ,.ex_stall        (ex2_stall         )
        ,.id_ex_valid     (id_ex_valid       )
        ,.id_ex_pc        (id_ex_pc          )
        ,.id_ex_snpc      (id_ex_snpc        )
        ,.id_ex_pred_taken(id_ex_pred_taken  )
        ,.id_ex_pred_target(id_ex_pred_target)
        ,.id_ex_pred_pht_idx(id_ex_pred_pht_idx)
        ,.id_ex_rs1_addr  (id_ex_rs1_addr    )
        ,.id_ex_rs2_addr  (id_ex_rs2_addr    )
        ,.id_ex_rd_addr   (id_ex_rd_addr     )
        ,.id_ex_rs1_ren   (id_ex_rs1_ren     )
        ,.id_ex_rs2_ren   (id_ex_rs2_ren     )
        ,.id_ex_wb_ctl    (id_ex_wb_ctl      )
        ,.id_ex_exu_op    (id_ex_exu_op      )
        ,.id_ex_alu_ctrl  (id_ex_alu_ctrl    )
        ,.id_ex_ls_ctl    (id_ex_ls_ctl      )
        ,.id_ex_data1     (id_ex_data1       )
        ,.id_ex_data2     (id_ex_data2       )
        ,.id_ex_data3     (id_ex_data3       )
        ,.id_ex_data4     (id_ex_data4       )
        ,.id_ex_rs1_data  (id_ex_rs1_data    )
        ,.id_ex_rs2_data  (id_ex_rs2_data    )
        ,.id_ex_load_op   (id_ex_load_op     )
        ,.id_ex_csr_addr  (id_ex_csr_addr    )
        ,.id_ex_csr_op    (id_ex_csr_op      )
        ,.id_ex_csr_zimm  (id_ex_csr_zimm    )
    );

    // EX1 hazard detection
    ex1_hazard u_ex1_hazard(
         .id_ex_valid          (id_ex_valid          )
        ,.id_ex_rs1_addr       (id_ex_rs1_addr       )
        ,.id_ex_rs2_addr       (id_ex_rs2_addr       )
        ,.id_ex_rs1_ren        (id_ex_rs1_ren        )
        ,.id_ex_rs2_ren        (id_ex_rs2_ren        )
        ,.ex1_ex2_valid        (ex1_ex2_valid        )
        ,.ex1_ex2_rd_addr      (ex1_ex2_rd_addr      )
        ,.ex1_ex2_wb_ctl       (ex1_ex2_wb_ctl       )
        ,.ex2_mem_valid        (ex2_mem_valid        )
        ,.ex2_mem_rd_addr      (ex2_mem_rd_addr      )
        ,.ex2_mem_wb_ctl       (ex2_mem_wb_ctl       )
        ,.ex2_mem_load_op      (ex2_mem_load_op      )
        ,.ex1_dependency_stall (ex1_dependency_stall )
    );

    // EX1 forwarding and MUX
    ex_forward u_ex_forward(
         .id_ex_valid          (id_ex_valid          )
        ,.id_ex_rs1_addr       (id_ex_rs1_addr       )
        ,.id_ex_rs2_addr       (id_ex_rs2_addr       )
        ,.id_ex_rd_addr        (id_ex_rd_addr        )
        ,.id_ex_rs1_ren        (id_ex_rs1_ren        )
        ,.id_ex_rs2_ren        (id_ex_rs2_ren        )
        ,.id_ex_exu_op         (id_ex_exu_op         )
        ,.id_ex_data1          (id_ex_data1          )
        ,.id_ex_data2          (id_ex_data2          )
        ,.id_ex_data3          (id_ex_data3          )
        ,.id_ex_data4          (id_ex_data4          )
        ,.id_ex_rs1_data       (id_ex_rs1_data       )
        ,.id_ex_rs2_data       (id_ex_rs2_data       )
        ,.ex_mem_rd_addr       (ex2_mem_rd_addr      )
        ,.ex_mem_exu_res       (ex2_mem_exu_res      )
        ,.ex_mem_forward_valid (ex2_mem_forward_valid)
        ,.mem_wb_rd_addr       (mem_wb_rd_addr       )
        ,.mem_wb_wb_data       (mem_wb_wb_data       )
        ,.mem_wb_forward_valid (mem_wb_forward_valid )
        ,.ex1_data1            (ex1_data1            )
        ,.ex1_data2            (ex1_data2            )
        ,.ex1_data3            (ex1_data3            )
        ,.ex1_data4            (ex1_data4            )
        ,.ex1_store_wdata      (ex1_store_wdata      )
        ,.ex1_rs1_data         (ex1_rs1_data         )
        ,.ex1_rs2_data         (ex1_rs2_data         )
    );

    // EX1/EX2 pipeline register
    pipe_ex1_ex2 #(
         .BPU_INDEX_WIDTH(BPU_INDEX_WIDTH)
    ) u_pipe_ex1_ex2(
         .clk                  (core_clk             )
        ,.rst                  (core_rst             )
        ,.id_ex_valid          (id_ex_valid          )
        ,.id_ex_pc             (id_ex_pc             )
        ,.id_ex_snpc           (id_ex_snpc           )
        ,.id_ex_pred_taken     (id_ex_pred_taken     )
        ,.id_ex_pred_target    (id_ex_pred_target    )
        ,.id_ex_pred_pht_idx   (id_ex_pred_pht_idx   )
        ,.id_ex_rd_addr        (id_ex_rd_addr        )
        ,.id_ex_wb_ctl         (id_ex_wb_ctl         )
        ,.id_ex_exu_op         (id_ex_exu_op         )
        ,.id_ex_alu_ctrl       (id_ex_alu_ctrl       )
        ,.id_ex_ls_ctl         (id_ex_ls_ctl         )
        ,.ex1_data1            (ex1_data1            )
        ,.ex1_data2            (ex1_data2            )
        ,.ex1_data3            (ex1_data3            )
        ,.ex1_data4            (ex1_data4            )
        ,.ex1_store_wdata      (ex1_store_wdata      )
        ,.id_ex_csr_addr       (id_ex_csr_addr       )
        ,.id_ex_csr_op         (id_ex_csr_op         )
        ,.id_ex_csr_zimm       (id_ex_csr_zimm       )
        ,.ex_redirect          (ex_redirect          )
        ,.ex1_dependency_stall (ex1_dependency_stall )
        ,.ex2_stall            (ex2_stall            )
        ,.ex1_ex2_valid        (ex1_ex2_valid        )
        ,.ex1_ex2_pc           (ex1_ex2_pc           )
        ,.ex1_ex2_snpc         (ex1_ex2_snpc         )
        ,.ex1_ex2_pred_taken   (ex1_ex2_pred_taken   )
        ,.ex1_ex2_pred_target  (ex1_ex2_pred_target  )
        ,.ex1_ex2_pred_pht_idx (ex1_ex2_pred_pht_idx )
        ,.ex1_ex2_rd_addr      (ex1_ex2_rd_addr      )
        ,.ex1_ex2_wb_ctl       (ex1_ex2_wb_ctl       )
        ,.ex1_ex2_exu_op       (ex1_ex2_exu_op       )
        ,.ex1_ex2_alu_ctrl     (ex1_ex2_alu_ctrl     )
        ,.ex1_ex2_ls_ctl       (ex1_ex2_ls_ctl       )
        ,.ex1_ex2_data1        (ex1_ex2_data1        )
        ,.ex1_ex2_data2        (ex1_ex2_data2        )
        ,.ex1_ex2_data3        (ex1_ex2_data3        )
        ,.ex1_ex2_data4        (ex1_ex2_data4        )
        ,.ex1_ex2_store_wdata  (ex1_ex2_store_wdata  )
        ,.ex1_ex2_csr_addr     (ex1_ex2_csr_addr     )
        ,.ex1_ex2_csr_op       (ex1_ex2_csr_op       )
        ,.ex1_ex2_csr_zimm     (ex1_ex2_csr_zimm     )
        ,.ex1_ex2_load_op      (ex1_ex2_load_op      )
    );

    // EX2 stage (EXU)
    KLDJ_exu exu2(
        .clk          (core_clk              )
        ,.rst         (core_rst              )
        ,.valid       (ex1_ex2_valid         )
        ,.data1       (ex1_ex2_data1         )
        ,.data2       (ex1_ex2_data2         )
        ,.data3       (ex1_ex2_data3         )
        ,.data4       (ex1_ex2_data4         )
        ,.exu_op      (ex1_ex2_exu_op        )
        ,.alu_ctrl    (ex1_ex2_alu_ctrl      )
        // CSR interface
        ,.csr_addr    (ex1_ex2_csr_addr      )
        ,.csr_op      (ex1_ex2_csr_op        )
        ,.csr_zimm    (ex1_ex2_csr_zimm      )
        ,.csr_rdata   (csr_rdata             )
        ,.csr_we      (csr_we                )
        ,.csr_wdata   (csr_wdata             )
        // ecall/mret interface
        ,.is_ecall    (is_ecall              )
        ,.is_mret     (is_mret               )
        ,.mret_pc     (mret_pc               )
        // original outputs
        ,.exu_jump    (exu_jump_raw          )
        ,.exu_jump_pc (exu_jump_pc_raw       )
        ,.exu_res     (exu_data              )
        ,.ex_mem_addr (ex2_mem_addr_pre      )
        ,.div_stall   (div_stall             )
        ,.mul_stall   (mul_stall             )
    );

    // EX2 redirect and BPU update control
    ex_bpu_ctrl #(
         .BPU_INDEX_WIDTH(BPU_INDEX_WIDTH)
    ) u_ex_bpu_ctrl(
         .ex1_ex2_valid       (ex1_ex2_valid       )
        ,.ex1_ex2_pc          (ex1_ex2_pc          )
        ,.ex1_ex2_snpc        (ex1_ex2_snpc        )
        ,.ex1_ex2_pred_taken  (ex1_ex2_pred_taken  )
        ,.ex1_ex2_pred_target (ex1_ex2_pred_target )
        ,.ex1_ex2_pred_pht_idx(ex1_ex2_pred_pht_idx)
        ,.ex1_ex2_exu_op      (ex1_ex2_exu_op      )
        ,.exu_jump_raw        (exu_jump_raw        )
        ,.exu_jump_pc_raw     (exu_jump_pc_raw     )
        ,.is_ecall            (is_ecall            )
        ,.is_mret             (is_mret             )
        ,.mtvec_val           (mtvec_val           )
        ,.ex_actual_taken     (ex_actual_taken     )
        ,.ex_correct_pc       (ex_correct_pc       )
        ,.ex_redirect         (ex_redirect         )
        ,.bpu_update_valid    (bpu_update_valid    )
        ,.bpu_update_pc       (bpu_update_pc       )
        ,.bpu_update_pht_idx  (bpu_update_pht_idx  )
        ,.bpu_update_taken    (bpu_update_taken    )
        ,.bpu_update_target   (bpu_update_target   )
    );

    assign ex2_stall = div_stall || mul_stall;
    assign frontend_stall = ex1_dependency_stall || ex2_stall;

    // EX2-stage BRAM request control
    ex_mem_req_ctrl u_ex_mem_req_ctrl(
         .ex1_ex2_valid    (ex1_ex2_valid     )
        ,.ex2_stall        (ex2_stall         )
        ,.ex1_ex2_exu_op   (ex1_ex2_exu_op    )
        ,.ex1_ex2_ls_ctl   (ex1_ex2_ls_ctl    )
        ,.ex2_mem_addr_pre (ex2_mem_addr_pre  )
        ,.ex2_store_wdata  (ex1_ex2_store_wdata)
        ,.mem_addr         (mem_addr          )
        ,.mem_wdata        (mem_wdata         )
        ,.mem_we           (mem_we            )
        ,.mem_be           (mem_be            )
    );

    // CSR module instantiation
    KLDJ_csr u_csr(
         .clk       (core_clk                    )
        ,.rst       (core_rst                    )
        ,.csr_raddr (ex1_ex2_csr_addr            )
        ,.csr_rdata (csr_rdata                   )
        ,.csr_we    (csr_we && ex1_ex2_valid     )
        ,.csr_waddr (ex1_ex2_csr_addr            )
        ,.csr_wdata (csr_wdata                   )
        ,.ecall_en  (is_ecall && ex1_ex2_valid   )
        ,.ecall_pc  (ex1_ex2_pc                  )
        ,.mret_en   (is_mret && ex1_ex2_valid    )
        ,.mret_pc   (mret_pc                     )
        ,.mtvec_val (mtvec_val                   )
    );

    // EX2/MEM pipeline register
    pipe_ex_mem u_pipe_ex_mem(
         .clk                  (core_clk            )
        ,.rst                  (core_rst            )
        ,.ex1_ex2_valid        (ex1_ex2_valid       )
        ,.ex1_ex2_pc           (ex1_ex2_pc          )
        ,.ex1_ex2_rd_addr      (ex1_ex2_rd_addr     )
        ,.ex1_ex2_wb_ctl       (ex1_ex2_wb_ctl      )
        ,.ex1_ex2_exu_op       (ex1_ex2_exu_op      )
        ,.ex1_ex2_ls_ctl       (ex1_ex2_ls_ctl      )
        ,.exu_data             (exu_data            )
        ,.ex2_mem_addr_i       (ex2_mem_addr_pre    )
        ,.ex2_store_wdata      (ex1_ex2_store_wdata )
        ,.ex2_stall            (ex2_stall           )
        ,.ex2_mem_valid        (ex2_mem_valid       )
        ,.ex2_mem_pc           (ex2_mem_pc          )
        ,.ex2_mem_rd_addr      (ex2_mem_rd_addr     )
        ,.ex2_mem_wb_ctl       (ex2_mem_wb_ctl      )
        ,.ex2_mem_exu_op       (ex2_mem_exu_op      )
        ,.ex2_mem_ls_ctl       (ex2_mem_ls_ctl      )
        ,.ex2_mem_exu_res      (ex2_mem_exu_res     )
        ,.ex2_mem_mem_addr     (ex2_mem_mem_addr    )
        ,.ex2_mem_store_wdata  (ex2_mem_store_wdata )
        ,.ex2_mem_load_op      (ex2_mem_load_op     )
        ,.ex2_mem_forward_valid(ex2_mem_forward_valid)
    );

    // MEM stage (LSU + memory interface + WB data MUX)
    mem_stage_top u_mem_stage_top(
         .ex_mem_valid       (ex2_mem_valid       )
        ,.ex_mem_exu_op      (ex2_mem_exu_op      )
        ,.ex_mem_ls_ctl      (ex2_mem_ls_ctl      )
        ,.ex_mem_exu_res     (ex2_mem_exu_res     )
        ,.ex_mem_mem_addr    (ex2_mem_mem_addr    )
        ,.ex_mem_store_wdata (ex2_mem_store_wdata )
        ,.ex_mem_wb_ctl      (ex2_mem_wb_ctl      )
        ,.mem_rdata          (mem_rdata           )
        ,.mem_addr           (mem_addr_memstage_unused )
        ,.mem_wdata          (mem_wdata_memstage_unused)
        ,.mem_we             (mem_we_memstage_unused   )
        ,.mem_be             (mem_be_memstage_unused   )
        ,.mem_stage_wb_data  (mem_stage_wb_data   )
        ,.mem_stage_wb_ctl   (mem_stage_wb_ctl    )
    );

    // MEM/WB pipeline register
    pipe_mem_wb u_pipe_mem_wb(
         .clk               (core_clk            )
        ,.rst               (core_rst            )
        ,.ex_mem_valid      (ex2_mem_valid       )
        ,.ex_mem_pc         (ex2_mem_pc          )
        ,.ex_mem_rd_addr    (ex2_mem_rd_addr     )
        ,.mem_stage_wb_ctl  (mem_stage_wb_ctl    )
        ,.wb_reg_rd_data    (wb_reg_rd_data      )
        ,.mem_wb_valid      (mem_wb_valid        )
        ,.mem_wb_pc         (mem_wb_pc           )
        ,.mem_wb_rd_addr    (mem_wb_rd_addr      )
        ,.mem_wb_wb_ctl     (mem_wb_wb_ctl       )
        ,.mem_wb_wb_data    (mem_wb_wb_data      )
        ,.mem_wb_forward_valid(mem_wb_forward_valid)
    );

    // WB stage
    KLDJ_wbu wbu4(
         .wb_ctl      (mem_stage_wb_ctl      )
        ,.exu_res     (mem_stage_wb_data     )
        ,.wb_data     (wb_reg_rd_data        )
        ,.wb_wen      (wb_wen                )
    );

    // Regfile
    KLDJ_regfile reg5(
         .clk         (core_clk               )
        ,.rst         (core_rst               )
        ,.waddr       (mem_wb_rd_addr         )
        ,.wdata       (mem_wb_wb_data         )
        ,.wen         (mem_wb_wb_ctl          )
        ,.raddr1      (id_reg_rs1_addr        )
        ,.rdata1      (reg_id_rs1_data        )
        ,.ren1        (id_reg_rs1_ren         )
        ,.raddr2      (id_reg_rs2_addr        )
        ,.rdata2      (reg_id_rs2_data        )
        ,.ren2        (id_reg_rs2_ren         )
    );

    // WB commit observation point
    pipe_wb_commit u_pipe_wb_commit(
         .clk              (core_clk           )
        ,.rst              (core_rst           )
        ,.mem_wb_valid     (mem_wb_valid       )
        ,.mem_wb_pc        (mem_wb_pc          )
        ,.mem_wb_rd_addr   (mem_wb_rd_addr     )
        ,.mem_wb_wb_ctl    (mem_wb_wb_ctl      )
        ,.mem_wb_wb_data   (mem_wb_wb_data     )
        ,.wb_commit_valid  (wb_commit_valid    )
        ,.wb_commit_pc     (wb_commit_pc       )
        ,.wb_commit_rd_addr(wb_commit_rd_addr  )
        ,.wb_commit_wb_ctl (wb_commit_wb_ctl   )
        ,.wb_commit_wb_data(wb_commit_wb_data  )
    );

    // Top-level outputs
    assign tb_ex_jump   = ex_redirect;
    assign tb_ex_jump_pc = ex_redirect ? ex_correct_pc : `KLDJ_ZERO32;
    assign tb_ex_res    = wb_commit_valid ? wb_commit_wb_data : `KLDJ_ZERO32;
    assign tb_if_pc     = if_pc;

/*
    // ========================================================
    // Performance counters
    // ========================================================
    wire perf_event_instret        = mem_wb_valid;
    wire perf_event_frontend_stall = frontend_stall;
    wire perf_event_load_use_stall = ex1_dependency_stall;
    wire perf_event_mul_stall      = mul_stall;
    wire perf_event_div_stall      = div_stall;
    wire perf_event_redirect       = ex_redirect;
    wire perf_event_load           = ex1_ex2_valid && !ex2_stall && ((ex1_ex2_exu_op >= 18'h1d) && (ex1_ex2_exu_op <= 18'h21));
    wire perf_event_store          = ex1_ex2_valid && !ex2_stall && ((ex1_ex2_exu_op >= 18'h22) && (ex1_ex2_exu_op <= 18'h24));

    KLDJ_perf_counters u_perf_counters(
         .clk                      (core_clk                  )
        ,.rst                      (core_rst                  )
        ,.event_instret            (perf_event_instret        )
        ,.event_frontend_stall     (perf_event_frontend_stall )
        ,.event_load_use_stall     (perf_event_load_use_stall )
        ,.event_mul_stall          (perf_event_mul_stall      )
        ,.event_div_stall          (perf_event_div_stall      )
        ,.event_redirect           (perf_event_redirect       )
        ,.event_load               (perf_event_load           )
        ,.event_store              (perf_event_store          )
        ,.perf_cycle_count         (perf_cycle_count          )
        ,.perf_instret_count       (perf_instret_count        )
        ,.perf_frontend_stall_count(perf_frontend_stall_count )
        ,.perf_load_use_stall_count(perf_load_use_stall_count )
        ,.perf_mul_stall_count     (perf_mul_stall_count      )
        ,.perf_div_stall_count     (perf_div_stall_count      )
        ,.perf_redirect_count      (perf_redirect_count       )
        ,.perf_load_count          (perf_load_count           )
        ,.perf_store_count         (perf_store_count          )
    );
*/
endmodule
