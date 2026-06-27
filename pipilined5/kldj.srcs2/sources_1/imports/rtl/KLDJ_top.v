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

    wire                         core_clk;
    wire                         core_locked;
    wire                         core_rst;

    assign core_clk      = clk;
    assign core_locked   = 1'b1;  


    assign core_rst = rst | ~core_locked;
    assign core_clk_o = core_clk;

    // IF stage
    wire [`KLDJ_INST]            if_inst;
    wire [`KLDJ_PC]              if_pc;
    wire [`KLDJ_PC]              if_snpc;

    // IF/ID pipeline register
    reg                          if_id_valid;
    reg [`KLDJ_INST]             if_id_inst;
    reg [`KLDJ_PC]               if_id_pc;
    reg [`KLDJ_PC]               if_id_snpc;

    // ID stage
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

    // ID/EX pipeline register
    reg                          id_ex_valid;
    reg [`KLDJ_PC]               id_ex_pc;
    reg [`KLDJ_PC]               id_ex_snpc;
    reg [`KLDJ_REGADDR]          id_ex_rs1_addr;
    reg [`KLDJ_REGADDR]          id_ex_rs2_addr;
    reg [`KLDJ_REGADDR]          id_ex_rd_addr;
    reg                          id_ex_rs1_ren;
    reg                          id_ex_rs2_ren;
    reg                          id_ex_wb_ctl;
    reg [17:0]                   id_ex_exu_op;
    reg [9:0]                    id_ex_alu_ctrl;
    reg [3:0]                    id_ex_ls_ctl;
    reg [`KLDJ_DATA]             id_ex_data1;
    reg [`KLDJ_DATA]             id_ex_data2;
    reg [`KLDJ_DATA]             id_ex_data3;
    reg [`KLDJ_DATA]             id_ex_data4;
    reg [`KLDJ_DATA]             id_ex_rs1_data;
    reg [`KLDJ_DATA]             id_ex_rs2_data;

    // EX stage
    wire [`KLDJ_DATA]            ex_rs1_data;
    wire [`KLDJ_DATA]            ex_rs2_data;
    wire                         id_ex_rs2_to_data2;
    wire                         id_ex_store_op;
    wire [`KLDJ_DATA]            ex_data1;
    wire [`KLDJ_DATA]            ex_data2;
    wire [`KLDJ_DATA]            ex_data3;
    wire [`KLDJ_DATA]            ex_data4;
    wire [`KLDJ_DATA]            ex_store_wdata;
    wire                         exu_jump_raw;
    wire [`KLDJ_PC]              exu_jump_pc_raw;
    wire [`KLDJ_DATA]            exu_data;
    wire                         ex_redirect;

    // EX/MEM pipeline register
    reg                          ex_mem_valid;
    reg [`KLDJ_PC]               ex_mem_pc;
    reg [`KLDJ_REGADDR]          ex_mem_rd_addr;
    reg                          ex_mem_wb_ctl;
    reg [17:0]                   ex_mem_exu_op;
    reg [3:0]                    ex_mem_ls_ctl;
    reg [`KLDJ_DATA]             ex_mem_exu_res;
    (* keep = "true" *) reg [`KLDJ_DATA] ex_mem_mem_addr;
    reg [`KLDJ_DATA]             ex_mem_store_wdata;

    // MEM stage
    wire [`KLDJ_DATA]            lsu_mem_addr;
    wire [`KLDJ_DATA]            lsu_mem_wdata;
    wire                         lsu_mem_we;
    wire [3:0]                   lsu_mem_be;
    wire [`KLDJ_DATA]            lsu_res;
    wire                         lsu_is_load;
    wire [`KLDJ_DATA]            mem_stage_wb_data;
    wire                         mem_stage_wb_ctl;
    wire [`KLDJ_DATA]            wb_reg_rd_data;
    wire                         wb_wen;

    // MEM/WB pipeline register, kept as the external retirement observation point.
    reg                          mem_wb_valid;
    reg [`KLDJ_PC]               mem_wb_pc;
    reg [`KLDJ_REGADDR]          mem_wb_rd_addr;
    reg                          mem_wb_wb_ctl;
    reg [`KLDJ_DATA]             mem_wb_wb_data;

    // Commit observation point for the instruction written back on this edge.
    reg                          wb_commit_valid;
    reg [`KLDJ_PC]               wb_commit_pc;
    reg [`KLDJ_REGADDR]          wb_commit_rd_addr;
    reg                          wb_commit_wb_ctl;
    reg [`KLDJ_DATA]             wb_commit_wb_data;

    // Regfile
    wire [`KLDJ_REG]             reg_id_rs1_data;
    wire [`KLDJ_REG]             reg_id_rs2_data;

    wire                         id_ex_load_op;
    wire                         ex_mem_load_op;
    wire                         ex_mem_forward_valid;
    wire                         mem_wb_forward_valid;
    wire                         ex_mem_rs1_forward_hit;
    wire                         mem_wb_rs1_forward_hit;
    wire                         ex_mem_rs2_forward_hit;
    wire                         mem_wb_rs2_forward_hit;
    wire                         load_use_stall;

    assign id_ex_load_op = (id_ex_exu_op >= 18'h1d) && (id_ex_exu_op <= 18'h21);
    assign ex_mem_load_op = (ex_mem_exu_op >= 18'h1d) && (ex_mem_exu_op <= 18'h21);

    assign load_use_stall = id_ex_valid && id_ex_load_op && (id_ex_rd_addr != 5'd0) &&
                            if_id_valid &&
                            ((id_reg_rs1_ren && (id_reg_rs1_addr == id_ex_rd_addr)) ||
                             (id_reg_rs2_ren && (id_reg_rs2_addr == id_ex_rd_addr)));

    KLDJ_ifu ifu0(
         .clk     (core_clk          )
        ,.rst     (core_rst          )
        ,.hold    (load_use_stall    )
        ,.jump    (ex_redirect       )
        ,.jump_pc (exu_jump_pc_raw   )
        ,.inst_i  (tb_if_inst        )
        ,.inst_o  (if_inst           )
        ,.pc_o    (if_pc             )
        ,.snpc    (if_snpc           )
    );

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
    );

    assign ex_mem_forward_valid = ex_mem_valid && ex_mem_wb_ctl && !ex_mem_load_op &&
                                  (ex_mem_rd_addr != 5'd0);
    assign mem_wb_forward_valid = mem_wb_valid && mem_wb_wb_ctl && (mem_wb_rd_addr != 5'd0);

    assign ex_mem_rs1_forward_hit = id_ex_rs1_ren && ex_mem_forward_valid &&
                                    (id_ex_rs1_addr == ex_mem_rd_addr);
    assign mem_wb_rs1_forward_hit = id_ex_rs1_ren && mem_wb_forward_valid &&
                                    (id_ex_rs1_addr == mem_wb_rd_addr);
    assign ex_mem_rs2_forward_hit = id_ex_rs2_ren && ex_mem_forward_valid &&
                                    (id_ex_rs2_addr == ex_mem_rd_addr);
    assign mem_wb_rs2_forward_hit = id_ex_rs2_ren && mem_wb_forward_valid &&
                                    (id_ex_rs2_addr == mem_wb_rd_addr);

    assign ex_rs1_data = ex_mem_rs1_forward_hit ? ex_mem_exu_res :
                         mem_wb_rs1_forward_hit ? mem_wb_wb_data :
                         id_ex_rs1_data;

    assign ex_rs2_data = ex_mem_rs2_forward_hit ? ex_mem_exu_res :
                         mem_wb_rs2_forward_hit ? mem_wb_wb_data :
                         id_ex_rs2_data;

    assign id_ex_rs2_to_data2 = ((id_ex_exu_op >= 18'ha) && (id_ex_exu_op <= 18'h19));
    assign id_ex_store_op = ((id_ex_exu_op >= 18'h22) && (id_ex_exu_op <= 18'h24));

    assign ex_data1 = id_ex_rs1_ren ? ex_rs1_data : id_ex_data1;
    assign ex_data2 = id_ex_rs2_to_data2 ? ex_rs2_data : id_ex_data2;
    assign ex_data3 = id_ex_data3;
    assign ex_data4 = id_ex_data4;
    assign ex_store_wdata = id_ex_store_op ? ex_rs2_data : id_ex_data3;

    KLDJ_exu exu2(
         .data1       (ex_data1              )
        ,.data2       (ex_data2              )
        ,.data3       (ex_data3              )
        ,.data4       (ex_data4              )
        ,.exu_op      (id_ex_exu_op          )
        ,.alu_ctrl    (id_ex_alu_ctrl        )
        ,.exu_jump    (exu_jump_raw          )
        ,.exu_jump_pc (exu_jump_pc_raw       )
        ,.exu_res     (exu_data              )
    );

    assign ex_redirect = id_ex_valid && exu_jump_raw;

    KLDJ_lsu lsu3(
         .exu_op      (ex_mem_exu_op         )
        ,.id_ls_ctl   (ex_mem_ls_ctl         )
        ,.ls_addr     (ex_mem_mem_addr       )
        ,.ls_wdata    (ex_mem_store_wdata    )
        ,.mem_addr    (lsu_mem_addr          )
        ,.mem_wdata   (lsu_mem_wdata         )
        ,.mem_we      (lsu_mem_we            )
        ,.mem_be      (lsu_mem_be            )
        ,.mem_rdata   (mem_rdata             )
        ,.lsu_res     (lsu_res               )
        ,.is_load     (lsu_is_load           )
    );

    assign mem_addr = lsu_mem_addr;
    assign mem_wdata = ex_mem_valid ? lsu_mem_wdata : `KLDJ_ZERO32;
    assign mem_we = ex_mem_valid && lsu_mem_we;
    assign mem_be = ex_mem_valid ? lsu_mem_be : 4'b0000;

    assign mem_stage_wb_data = lsu_is_load ? lsu_res : ex_mem_exu_res;
    assign mem_stage_wb_ctl = ex_mem_valid && ex_mem_wb_ctl;

    KLDJ_wbu wbu4(
         .wb_ctl      (mem_stage_wb_ctl      )
        ,.exu_res     (mem_stage_wb_data     )
        ,.wb_data     (wb_reg_rd_data        )
        ,.wb_wen      (wb_wen                )
    );

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

    always@(posedge core_clk) begin
        if(core_rst == `KLDJ_RSTABLE) begin
            if_id_valid <= 1'b0;
            if_id_inst  <= KLDJ_NOP;
            if_id_pc    <= `KLDJ_STARTPC;
            if_id_snpc  <= `KLDJ_STARTPC + `KLDJ_PLUS4;
        end else if(ex_redirect) begin
            if_id_valid <= 1'b0;
            if_id_inst  <= KLDJ_NOP;
            if_id_pc    <= `KLDJ_ZERO32;
            if_id_snpc  <= `KLDJ_ZERO32;
        end else if(!load_use_stall) begin
            if_id_valid <= 1'b1;
            if_id_inst  <= if_inst;
            if_id_pc    <= if_pc;
            if_id_snpc  <= if_snpc;
        end
    end

    always@(posedge core_clk) begin
        if(core_rst == `KLDJ_RSTABLE) begin
            id_ex_valid    <= 1'b0;
            id_ex_pc       <= `KLDJ_ZERO32;
            id_ex_snpc     <= `KLDJ_ZERO32;
            id_ex_rs1_addr <= 5'd0;
            id_ex_rs2_addr <= 5'd0;
            id_ex_rd_addr  <= 5'd0;
            id_ex_rs1_ren  <= 1'b0;
            id_ex_rs2_ren  <= 1'b0;
            id_ex_wb_ctl   <= 1'b0;
            id_ex_exu_op   <= 18'd0;
            id_ex_alu_ctrl <= 10'd0;
            id_ex_ls_ctl   <= 4'd0;
            id_ex_data1    <= `KLDJ_ZERO32;
            id_ex_data2    <= `KLDJ_ZERO32;
            id_ex_data3    <= `KLDJ_ZERO32;
            id_ex_data4    <= `KLDJ_ZERO32;
            id_ex_rs1_data <= `KLDJ_ZERO32;
            id_ex_rs2_data <= `KLDJ_ZERO32;
        end else if(ex_redirect || load_use_stall) begin
            id_ex_valid    <= 1'b0;
            id_ex_pc       <= `KLDJ_ZERO32;
            id_ex_snpc     <= `KLDJ_ZERO32;
            id_ex_rs1_addr <= 5'd0;
            id_ex_rs2_addr <= 5'd0;
            id_ex_rd_addr  <= 5'd0;
            id_ex_rs1_ren  <= 1'b0;
            id_ex_rs2_ren  <= 1'b0;
            id_ex_wb_ctl   <= 1'b0;
            id_ex_exu_op   <= 18'd0;
            id_ex_alu_ctrl <= 10'd0;
            id_ex_ls_ctl   <= 4'd0;
            id_ex_data1    <= `KLDJ_ZERO32;
            id_ex_data2    <= `KLDJ_ZERO32;
            id_ex_data3    <= `KLDJ_ZERO32;
            id_ex_data4    <= `KLDJ_ZERO32;
            id_ex_rs1_data <= `KLDJ_ZERO32;
            id_ex_rs2_data <= `KLDJ_ZERO32;
        end else begin
            id_ex_valid    <= if_id_valid;
            id_ex_pc       <= if_id_pc;
            id_ex_snpc     <= if_id_snpc;
            id_ex_rs1_addr <= id_reg_rs1_addr;
            id_ex_rs2_addr <= id_reg_rs2_addr;
            id_ex_rd_addr  <= id_reg_rd_addr;
            id_ex_rs1_ren  <= if_id_valid && id_reg_rs1_ren;
            id_ex_rs2_ren  <= if_id_valid && id_reg_rs2_ren;
            id_ex_wb_ctl   <= if_id_valid && id_wb_ctl;
            id_ex_exu_op   <= id_exu_op;
            id_ex_alu_ctrl <= if_id_valid ? id_alu_ctrl : 10'd0;
            id_ex_ls_ctl   <= id_ls_ctl;
            id_ex_data1    <= id_data1;
            id_ex_data2    <= id_data2;
            id_ex_data3    <= id_data3;
            id_ex_data4    <= id_data4;
            id_ex_rs1_data <= reg_id_rs1_data;
            id_ex_rs2_data <= reg_id_rs2_data;
        end
    end

    always@(posedge core_clk) begin
        if(core_rst == `KLDJ_RSTABLE) begin
            ex_mem_valid       <= 1'b0;
            ex_mem_pc          <= `KLDJ_ZERO32;
            ex_mem_rd_addr     <= 5'd0;
            ex_mem_wb_ctl      <= 1'b0;
            ex_mem_exu_op      <= 18'd0;
            ex_mem_ls_ctl      <= 4'd0;
            ex_mem_exu_res     <= `KLDJ_ZERO32;
            ex_mem_mem_addr    <= `KLDJ_ZERO32;
            ex_mem_store_wdata <= `KLDJ_ZERO32;
        end else begin
            ex_mem_valid       <= id_ex_valid;
            ex_mem_pc          <= id_ex_pc;
            ex_mem_rd_addr     <= id_ex_rd_addr;
            ex_mem_wb_ctl      <= id_ex_valid && id_ex_wb_ctl;
            ex_mem_exu_op      <= id_ex_exu_op;
            ex_mem_ls_ctl      <= id_ex_ls_ctl;
            ex_mem_exu_res     <= exu_data;
            ex_mem_mem_addr    <= exu_data;
            ex_mem_store_wdata <= ex_store_wdata;
        end
    end

    always@(posedge core_clk) begin
        if(core_rst == `KLDJ_RSTABLE) begin
            mem_wb_valid   <= 1'b0;
            mem_wb_pc      <= `KLDJ_ZERO32;
            mem_wb_rd_addr <= 5'd0;
            mem_wb_wb_ctl  <= 1'b0;
            mem_wb_wb_data <= `KLDJ_ZERO32;
        end else begin
            mem_wb_valid   <= ex_mem_valid;
            mem_wb_pc      <= ex_mem_pc;
            mem_wb_rd_addr <= ex_mem_rd_addr;
            mem_wb_wb_ctl  <= mem_stage_wb_ctl;
            mem_wb_wb_data <= wb_reg_rd_data;
        end
    end

    always@(posedge core_clk) begin
        if(core_rst == `KLDJ_RSTABLE) begin
            wb_commit_valid   <= 1'b0;
            wb_commit_pc      <= `KLDJ_ZERO32;
            wb_commit_rd_addr <= 5'd0;
            wb_commit_wb_ctl  <= 1'b0;
            wb_commit_wb_data <= `KLDJ_ZERO32;
        end else begin
            wb_commit_valid   <= mem_wb_valid;
            wb_commit_pc      <= mem_wb_pc;
            wb_commit_rd_addr <= mem_wb_rd_addr;
            wb_commit_wb_ctl  <= mem_wb_wb_ctl;
            wb_commit_wb_data <= mem_wb_wb_data;
        end
    end

    assign tb_ex_jump = ex_redirect;
    assign tb_ex_jump_pc = ex_redirect ? exu_jump_pc_raw : `KLDJ_ZERO32;
    assign tb_ex_res = wb_commit_valid ? wb_commit_wb_data : `KLDJ_ZERO32;
    assign tb_if_pc = if_pc;

endmodule
