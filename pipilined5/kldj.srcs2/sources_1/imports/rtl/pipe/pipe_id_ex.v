`include "../define.v"

module pipe_id_ex #(
     parameter BPU_INDEX_WIDTH = 6
)(
     input wire                  clk
    ,input wire                  rst
    // from ID stage
    ,input wire                  if_id_valid
    ,input wire [`KLDJ_PC]       if_id_pc
    ,input wire [`KLDJ_PC]       if_id_snpc
    ,input wire                  if_id_pred_taken
    ,input wire                  if_id_pred_is_jalr
    ,input wire [`KLDJ_PC]       if_id_pred_target
    ,input wire [BPU_INDEX_WIDTH-1:0] if_id_pred_pht_idx
    ,input wire [`KLDJ_REGADDR]  id_reg_rs1_addr
    ,input wire [`KLDJ_REGADDR]  id_reg_rs2_addr
    ,input wire [`KLDJ_REGADDR]  id_reg_rd_addr
    ,input wire                  id_reg_rs1_ren
    ,input wire                  id_reg_rs2_ren
    ,input wire                  id_wb_ctl
    ,input wire [17:0]           id_exu_op
    ,input wire [9:0]            id_alu_ctrl
    ,input wire [3:0]            id_ls_ctl
    ,input wire [`KLDJ_DATA]     id_data1
    ,input wire [`KLDJ_DATA]     id_data2
    ,input wire [`KLDJ_DATA]     id_data3
    ,input wire [`KLDJ_DATA]     id_data4
    ,input wire [`KLDJ_DATA]     reg_id_rs1_data
    ,input wire [`KLDJ_DATA]     reg_id_rs2_data
    // CSR signals from ID
    ,input wire [11:0]           id_csr_addr
    ,input wire                  id_csr_op
    ,input wire [4:0]            id_csr_zimm
    // control
    ,input wire                  ex_redirect
    ,input wire                  load_use_stall
    ,input wire                  ex_stall
    // pipeline register outputs
    ,output reg                  id_ex_valid
    ,output reg [`KLDJ_PC]       id_ex_pc
    ,output reg [`KLDJ_PC]       id_ex_snpc
    ,output reg                  id_ex_pred_taken
    ,output reg                  id_ex_pred_is_jalr
    ,output reg [`KLDJ_PC]       id_ex_pred_target
    ,output reg [BPU_INDEX_WIDTH-1:0] id_ex_pred_pht_idx
    ,output reg [`KLDJ_REGADDR]  id_ex_rs1_addr
    ,output reg [`KLDJ_REGADDR]  id_ex_rs2_addr
    ,output reg [`KLDJ_REGADDR]  id_ex_rd_addr
    ,output reg                  id_ex_rs1_ren
    ,output reg                  id_ex_rs2_ren
    ,output reg                  id_ex_wb_ctl
    ,output reg [17:0]           id_ex_exu_op
    ,output reg [9:0]            id_ex_alu_ctrl
    ,output reg [3:0]            id_ex_ls_ctl
    ,output reg [`KLDJ_DATA]     id_ex_data1
    ,output reg [`KLDJ_DATA]     id_ex_data2
    ,output reg [`KLDJ_DATA]     id_ex_data3
    ,output reg [`KLDJ_DATA]     id_ex_data4
    ,output reg [`KLDJ_DATA]     id_ex_rs1_data
    ,output reg [`KLDJ_DATA]     id_ex_rs2_data
    // CSR signals to EX
    ,output reg [11:0]           id_ex_csr_addr
    ,output reg                  id_ex_csr_op
    ,output reg [4:0]            id_ex_csr_zimm
    // registered predecode outputs
    ,output reg                  id_ex_load_op
    ,output reg                  id_ex_store_op
    ,output reg                  id_ex_rs2_to_data2
    ,output reg                  id_ex_branch_op
    ,output reg                  id_ex_jal_op
    ,output reg                  id_ex_jalr_op
);

    wire id_load_op = (id_exu_op >= 18'h1d) && (id_exu_op <= 18'h21);
    wire id_store_op = (id_exu_op >= 18'h22) && (id_exu_op <= 18'h24);
    wire id_rs2_to_data2 = ((id_exu_op >= 18'ha) && (id_exu_op <= 18'h19)) ||
                           ((id_exu_op >= 18'h25) && (id_exu_op <= 18'h2c));
    wire id_branch_op = (id_exu_op >= 18'h14) && (id_exu_op <= 18'h19);
    wire id_jal_op = (id_exu_op == 18'h1c);
    wire id_jalr_op = (id_exu_op == 18'h9);

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            id_ex_valid    <= 1'b0;
            id_ex_pred_taken  <= 1'b0;
            id_ex_pred_is_jalr <= 1'b0;
            id_ex_rs1_ren  <= 1'b0;
            id_ex_rs2_ren  <= 1'b0;
            id_ex_wb_ctl   <= 1'b0;
            id_ex_csr_op   <= 1'b0;
            id_ex_load_op  <= 1'b0;
            id_ex_store_op <= 1'b0;
            id_ex_rs2_to_data2 <= 1'b0;
            id_ex_branch_op <= 1'b0;
            id_ex_jal_op    <= 1'b0;
            id_ex_jalr_op   <= 1'b0;
        end else if(ex_redirect || load_use_stall) begin
            id_ex_valid    <= 1'b0;
            id_ex_pred_taken  <= 1'b0;
            id_ex_pred_is_jalr <= 1'b0;
            id_ex_rs1_ren  <= 1'b0;
            id_ex_rs2_ren  <= 1'b0;
            id_ex_wb_ctl   <= 1'b0;
            id_ex_csr_op   <= 1'b0;
            id_ex_load_op  <= 1'b0;
            id_ex_store_op <= 1'b0;
            id_ex_rs2_to_data2 <= 1'b0;
            id_ex_branch_op <= 1'b0;
            id_ex_jal_op    <= 1'b0;
            id_ex_jalr_op   <= 1'b0;
        end else if(!ex_stall) begin
            id_ex_valid    <= if_id_valid;
            id_ex_pred_taken  <= if_id_valid && if_id_pred_taken;
            id_ex_pred_is_jalr <= if_id_valid && if_id_pred_is_jalr;
            id_ex_rs1_ren  <= if_id_valid && id_reg_rs1_ren;
            id_ex_rs2_ren  <= if_id_valid && id_reg_rs2_ren;
            id_ex_wb_ctl   <= if_id_valid && id_wb_ctl;
            id_ex_csr_op   <= if_id_valid && id_csr_op;
            id_ex_load_op  <= if_id_valid && id_load_op;
            id_ex_store_op <= if_id_valid && id_store_op;
            id_ex_rs2_to_data2 <= if_id_valid && id_rs2_to_data2;
            id_ex_branch_op <= if_id_valid && id_branch_op;
            id_ex_jal_op    <= if_id_valid && id_jal_op;
            id_ex_jalr_op   <= if_id_valid && id_jalr_op;
        end
    end

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            id_ex_pc       <= `KLDJ_ZERO32;
            id_ex_snpc     <= `KLDJ_ZERO32;
            id_ex_pred_target <= `KLDJ_ZERO32;
            id_ex_pred_pht_idx <= {BPU_INDEX_WIDTH{1'b0}};
            id_ex_rs1_addr <= 5'd0;
            id_ex_rs2_addr <= 5'd0;
            id_ex_rd_addr  <= 5'd0;
            id_ex_exu_op   <= 18'd0;
            id_ex_alu_ctrl <= 10'd0;
            id_ex_ls_ctl   <= 4'd0;
            id_ex_data1    <= `KLDJ_ZERO32;
            id_ex_data2    <= `KLDJ_ZERO32;
            id_ex_data3    <= `KLDJ_ZERO32;
            id_ex_data4    <= `KLDJ_ZERO32;
            id_ex_rs1_data <= `KLDJ_ZERO32;
            id_ex_rs2_data <= `KLDJ_ZERO32;
            id_ex_csr_addr <= 12'b0;
            id_ex_csr_zimm <= 5'b0;
        end else if(load_use_stall) begin
            id_ex_exu_op   <= 18'd0;
            id_ex_alu_ctrl <= 10'd0;
            id_ex_ls_ctl   <= 4'd0;
        end else if(!ex_stall) begin
            id_ex_pc       <= if_id_pc;
            id_ex_snpc     <= if_id_snpc;
            id_ex_pred_target <= if_id_valid ? if_id_pred_target : `KLDJ_ZERO32;
            id_ex_pred_pht_idx <= if_id_valid ? if_id_pred_pht_idx : {BPU_INDEX_WIDTH{1'b0}};
            id_ex_rs1_addr <= id_reg_rs1_addr;
            id_ex_rs2_addr <= id_reg_rs2_addr;
            id_ex_rd_addr  <= id_reg_rd_addr;
            id_ex_exu_op   <= id_exu_op;
            id_ex_alu_ctrl <= if_id_valid ? id_alu_ctrl : 10'd0;
            id_ex_ls_ctl   <= id_ls_ctl;
            id_ex_data1    <= id_data1;
            id_ex_data2    <= id_data2;
            id_ex_data3    <= id_data3;
            id_ex_data4    <= id_data4;
            id_ex_rs1_data <= reg_id_rs1_data;
            id_ex_rs2_data <= reg_id_rs2_data;
            id_ex_csr_addr <= id_csr_addr;
            id_ex_csr_zimm <= id_csr_zimm;
        end
    end

endmodule
