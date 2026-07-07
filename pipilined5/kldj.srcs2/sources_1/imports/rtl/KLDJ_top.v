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
);

    localparam [`KLDJ_INST] KLDJ_NOP = 32'h00000013;

    // Clock and reset
    wire                         core_clk;
    wire                         core_locked;
    wire                         core_rst;

    assign core_clk      = clk;
    assign core_locked   = 1'b1;
    assign core_rst      = rst | ~core_locked;
    assign core_clk_o    = core_clk;

    // IF stage wires
    wire [`KLDJ_INST]            if_inst;
    wire [`KLDJ_PC]              if_pc;
    wire [`KLDJ_PC]              if_snpc;

    // IF/ID pipeline register outputs
    wire                         if_id_valid;
    wire [`KLDJ_INST]            if_id_inst;
    wire [`KLDJ_PC]              if_id_pc;
    wire [`KLDJ_PC]              if_id_snpc;

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

    // EX stage wires
    wire [`KLDJ_DATA]            ex_data1;
    wire [`KLDJ_DATA]            ex_data2;
    wire [`KLDJ_DATA]            ex_data3;
    wire [`KLDJ_DATA]            ex_data4;
    wire [`KLDJ_DATA]            ex_store_wdata;
    wire                         exu_jump_raw;
    wire [`KLDJ_PC]              exu_jump_pc_raw;
    wire [`KLDJ_DATA]            exu_data;
    wire [`KLDJ_DATA]            ex_mem_addr_pre;
    wire                         ex_redirect;
    wire                         load_use_stall;
    wire                         div_stall;
    wire                         mul_stall;
    wire                         ex_stall;
    wire                         frontend_stall;

    // CSR module wires
    wire [31:0]                  csr_rdata;
    wire                         csr_we;
    wire [31:0]                  csr_wdata;
    wire                         is_ecall;
    wire                         is_mret;
    wire [31:0]                  mret_pc;
    wire [31:0]                  mtvec_val;

    // EX/MEM pipeline register outputs
    wire                         ex_mem_valid;
    wire [`KLDJ_PC]              ex_mem_pc;
    wire [`KLDJ_REGADDR]         ex_mem_rd_addr;
    wire                         ex_mem_wb_ctl;
    wire [17:0]                  ex_mem_exu_op;
    wire [3:0]                   ex_mem_ls_ctl;
    wire [`KLDJ_DATA]            ex_mem_exu_res;
    wire [`KLDJ_DATA]            ex_mem_mem_addr;
    wire [`KLDJ_DATA]            ex_mem_store_wdata;
    wire                         ex_mem_load_op;
    wire                         ex_mem_forward_valid;

    // MEM stage wires
    wire [`KLDJ_DATA]            mem_stage_wb_data;
    wire                         mem_stage_wb_ctl;
    wire [`KLDJ_DATA]            mem_addr_memstage_unused;
    wire [`KLDJ_DATA]            mem_wdata_memstage_unused;
    wire                         mem_we_memstage_unused;
    wire [3:0]                   mem_be_memstage_unused;

    // EX-stage memory request wires
    wire                         ex_req_load;
    wire                         ex_req_store;
    wire                         ex_req_mem;
    wire [1:0]                   ex_req_size;
    wire [3:0]                   ex_req_be;
    wire [`KLDJ_DATA]            ex_req_wdata;

    // MEM/WB pipeline register outputs
    wire                         mem_wb_valid;
    wire [`KLDJ_PC]              mem_wb_pc;
    wire [`KLDJ_REGADDR]         mem_wb_rd_addr;
    wire                         mem_wb_wb_ctl;
    wire [`KLDJ_DATA]            mem_wb_wb_data;
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

    // ========================================================
    // Module instantiations
    // ========================================================

    // Select jump target: ecall jumps to mtvec, otherwise use EXU result
    wire [31:0] redirect_pc = is_ecall ? mtvec_val : exu_jump_pc_raw;

    // IF stage
    KLDJ_ifu ifu0(
         .clk     (core_clk          )
        ,.rst     (core_rst          )
        ,.hold    (frontend_stall    )
        ,.jump    (ex_redirect       )
        ,.jump_pc (redirect_pc       ) 
        ,.inst_i  (tb_if_inst        )
        ,.inst_o  (if_inst           )
        ,.pc_o    (if_pc             )
        ,.snpc    (if_snpc           )
    );

    // IF/ID pipeline register
    pipe_if_id u_pipe_if_id(
         .clk             (core_clk          )
        ,.rst             (core_rst          )
        ,.if_inst         (if_inst           )
        ,.if_pc           (if_pc             )
        ,.if_snpc         (if_snpc           )
        ,.ex_redirect     (ex_redirect       )
        ,.load_use_stall  (frontend_stall    )
        ,.if_id_valid     (if_id_valid       )
        ,.if_id_inst      (if_id_inst        )
        ,.if_id_pc        (if_id_pc          )
        ,.if_id_snpc      (if_id_snpc        )
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
    pipe_id_ex u_pipe_id_ex(
         .clk             (core_clk          )
        ,.rst             (core_rst          )
        ,.if_id_valid     (if_id_valid       )
        ,.if_id_pc        (if_id_pc          )
        ,.if_id_snpc      (if_id_snpc        )
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
        ,.id_csr_addr     (id_csr_addr       )
        ,.id_csr_op       (id_csr_op         )
        ,.id_csr_zimm     (id_csr_zimm       )
        ,.ex_redirect     (ex_redirect       )
        ,.load_use_stall  (load_use_stall    )
        ,.ex_stall        (ex_stall          )
        ,.id_ex_valid     (id_ex_valid       )
        ,.id_ex_pc        (id_ex_pc          )
        ,.id_ex_snpc      (id_ex_snpc        )
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

    // EX forwarding and MUX
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
        ,.ex_mem_rd_addr       (ex_mem_rd_addr       )
        ,.ex_mem_exu_res       (ex_mem_exu_res       )
        ,.ex_mem_forward_valid (ex_mem_forward_valid )
        ,.mem_wb_rd_addr       (mem_wb_rd_addr       )
        ,.mem_wb_wb_data       (mem_wb_wb_data       )
        ,.mem_wb_forward_valid (mem_wb_forward_valid )
        ,.if_id_valid          (if_id_valid          )
        ,.id_reg_rs1_addr      (id_reg_rs1_addr      )
        ,.id_reg_rs2_addr      (id_reg_rs2_addr      )
        ,.id_reg_rs1_ren       (id_reg_rs1_ren       )
        ,.id_reg_rs2_ren       (id_reg_rs2_ren       )
        ,.ex_data1             (ex_data1             )
        ,.ex_data2             (ex_data2             )
        ,.ex_data3             (ex_data3             )
        ,.ex_data4             (ex_data4             )
        ,.ex_store_wdata       (ex_store_wdata       )
        ,.load_use_stall       (load_use_stall       )
    );

    // EX stage
    KLDJ_exu exu2(
        .clk          (core_clk              )
        ,.rst         (core_rst              )
        ,.valid       (id_ex_valid           )
        ,.data1       (ex_data1              )
        ,.data2       (ex_data2              )
        ,.data3       (ex_data3              )
        ,.data4       (ex_data4              )
        ,.exu_op      (id_ex_exu_op          )
        ,.alu_ctrl    (id_ex_alu_ctrl        )
        // CSR interface
        ,.csr_addr    (id_ex_csr_addr        )
        ,.csr_op      (id_ex_csr_op          )
        ,.csr_zimm    (id_ex_csr_zimm        )
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
        ,.ex_mem_addr (ex_mem_addr_pre       )
        ,.div_stall   (div_stall             )
        ,.mul_stall   (mul_stall             )
    );

    // ecall also triggers redirect (jump to mtvec)
    assign ex_redirect = id_ex_valid && (exu_jump_raw || is_ecall);
    assign ex_stall = div_stall || mul_stall;
    assign frontend_stall = load_use_stall || ex_stall;

    assign ex_req_load  = (id_ex_exu_op >= 18'h1d) && (id_ex_exu_op <= 18'h21);
    assign ex_req_store = (id_ex_exu_op >= 18'h22) && (id_ex_exu_op <= 18'h24);
    assign ex_req_mem   = id_ex_valid && !ex_stall && (ex_req_load || ex_req_store);
    assign ex_req_size  = id_ex_ls_ctl[1:0];
    assign ex_req_be    = (ex_req_size == 2'b00) ? (4'b0001 << ex_mem_addr_pre[1:0]) :
                          (ex_req_size == 2'b01) ? (4'b0011 << {ex_mem_addr_pre[1], 1'b0}) :
                          (ex_req_size == 2'b10) ? 4'b1111 : 4'b0000;
    assign ex_req_wdata = (ex_req_size == 2'b00) ? {4{ex_store_wdata[7:0]}} :
                          (ex_req_size == 2'b01) ? {2{ex_store_wdata[15:0]}} :
                          ex_store_wdata;
    
    // CSR module instantiation
    KLDJ_csr u_csr(
         .clk       (core_clk              )
        ,.rst       (core_rst              )
        ,.csr_raddr (id_ex_csr_addr        )
        ,.csr_rdata (csr_rdata             )
        ,.csr_we    (csr_we && id_ex_valid  )
        ,.csr_waddr (id_ex_csr_addr        )
        ,.csr_wdata (csr_wdata             )
        ,.ecall_en  (is_ecall && id_ex_valid)
        ,.ecall_pc  (id_ex_pc              )
        ,.mret_en   (is_mret && id_ex_valid )
        ,.mret_pc   (mret_pc               )
        ,.mtvec_val (mtvec_val             )
    );

    // EX/MEM pipeline register
    pipe_ex_mem u_pipe_ex_mem(
         .clk               (core_clk            )
        ,.rst               (core_rst            )
        ,.id_ex_valid       (id_ex_valid         )
        ,.id_ex_pc          (id_ex_pc            )
        ,.id_ex_rd_addr     (id_ex_rd_addr       )
        ,.id_ex_wb_ctl      (id_ex_wb_ctl        )
        ,.id_ex_exu_op      (id_ex_exu_op        )
        ,.id_ex_ls_ctl      (id_ex_ls_ctl        )
        ,.exu_data          (exu_data            )
        ,.ex_mem_addr_i     (ex_mem_addr_pre     )
        ,.ex_store_wdata    (ex_store_wdata      )
        ,.ex_stall          (ex_stall            )
        ,.ex_mem_valid      (ex_mem_valid        )
        ,.ex_mem_pc         (ex_mem_pc           )
        ,.ex_mem_rd_addr    (ex_mem_rd_addr      )
        ,.ex_mem_wb_ctl     (ex_mem_wb_ctl       )
        ,.ex_mem_exu_op     (ex_mem_exu_op       )
        ,.ex_mem_ls_ctl     (ex_mem_ls_ctl       )
        ,.ex_mem_exu_res    (ex_mem_exu_res      )
        ,.ex_mem_mem_addr   (ex_mem_mem_addr     )
        ,.ex_mem_store_wdata(ex_mem_store_wdata  )
        ,.ex_mem_load_op    (ex_mem_load_op      )
        ,.ex_mem_forward_valid(ex_mem_forward_valid)
    );

    // MEM stage (LSU + memory interface + WB data MUX)
    mem_stage_top u_mem_stage_top(
         .ex_mem_valid       (ex_mem_valid        )
        ,.ex_mem_exu_op      (ex_mem_exu_op       )
        ,.ex_mem_ls_ctl      (ex_mem_ls_ctl       )
        ,.ex_mem_exu_res     (ex_mem_exu_res      )
        ,.ex_mem_mem_addr    (ex_mem_mem_addr     )
        ,.ex_mem_store_wdata (ex_mem_store_wdata  )
        ,.ex_mem_wb_ctl      (ex_mem_wb_ctl       )
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
        ,.ex_mem_valid      (ex_mem_valid        )
        ,.ex_mem_pc         (ex_mem_pc           )
        ,.ex_mem_rd_addr    (ex_mem_rd_addr      )
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
    assign tb_ex_jump_pc = ex_redirect ? redirect_pc : `KLDJ_ZERO32;
    assign tb_ex_res    = wb_commit_valid ? wb_commit_wb_data : `KLDJ_ZERO32;
    assign tb_if_pc     = if_pc;
    assign mem_addr     = ex_req_mem ? ex_mem_addr_pre : `KLDJ_ZERO32;
    assign mem_wdata    = (id_ex_valid && !ex_stall && ex_req_store) ? ex_req_wdata : `KLDJ_ZERO32;
    assign mem_we       = id_ex_valid && !ex_stall && ex_req_store;
    assign mem_be       = ex_req_mem ? ex_req_be : 4'b0000;

endmodule
