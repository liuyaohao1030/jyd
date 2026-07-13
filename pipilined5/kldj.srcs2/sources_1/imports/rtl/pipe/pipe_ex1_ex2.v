`include "../define.v"

// EX1/EX2 pipeline register
// EX1: forwarding and operand selection
// EX2: ALU computation, branch decision, CSR, MUL/DIV
module pipe_ex1_ex2 #(
    parameter BPU_INDEX_WIDTH = 6
)(
    input wire                  clk
    ,input wire                  rst
    // from EX1 stage (after forwarding)
    ,input wire                  id_ex_valid
    ,input wire [`KLDJ_PC]       id_ex_pc
    ,input wire [`KLDJ_PC]       id_ex_snpc
    ,input wire                  id_ex_pred_taken
    ,input wire [`KLDJ_PC]       id_ex_pred_target
    ,input wire [BPU_INDEX_WIDTH-1:0] id_ex_pred_pht_idx
    ,input wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input wire                  id_ex_wb_ctl
    ,input wire [17:0]           id_ex_exu_op
    ,input wire [9:0]            id_ex_alu_ctrl
    ,input wire [3:0]            id_ex_ls_ctl
    ,input wire [`KLDJ_DATA]     ex1_data1
    ,input wire [`KLDJ_DATA]     ex1_data2
    ,input wire [`KLDJ_DATA]     ex1_data3
    ,input wire [`KLDJ_DATA]     ex1_data4
    ,input wire [`KLDJ_DATA]     ex1_store_wdata
    // CSR signals
    ,input wire [11:0]           id_ex_csr_addr
    ,input wire                  id_ex_csr_op
    ,input wire [4:0]            id_ex_csr_zimm
    // control signals
    ,input wire                  ex_redirect
    ,input wire                  ex1_dependency_stall
    ,input wire                  ex2_stall
    // pipeline register outputs
    ,output reg                  ex1_ex2_valid
    ,output reg [`KLDJ_PC]       ex1_ex2_pc
    ,output reg [`KLDJ_PC]       ex1_ex2_snpc
    ,output reg                  ex1_ex2_pred_taken
    ,output reg [`KLDJ_PC]       ex1_ex2_pred_target
    ,output reg [BPU_INDEX_WIDTH-1:0] ex1_ex2_pred_pht_idx
    ,output reg [`KLDJ_REGADDR]  ex1_ex2_rd_addr
    ,output reg                  ex1_ex2_wb_ctl
    ,output reg [17:0]           ex1_ex2_exu_op
    ,output reg [9:0]            ex1_ex2_alu_ctrl
    ,output reg [3:0]            ex1_ex2_ls_ctl
    ,output reg [`KLDJ_DATA]     ex1_ex2_data1
    ,output reg [`KLDJ_DATA]     ex1_ex2_data2
    ,output reg [`KLDJ_DATA]     ex1_ex2_data3
    ,output reg [`KLDJ_DATA]     ex1_ex2_data4
    ,output reg [`KLDJ_DATA]     ex1_ex2_store_wdata
    // CSR signals
    ,output reg [11:0]           ex1_ex2_csr_addr
    ,output reg                  ex1_ex2_csr_op
    ,output reg [4:0]            ex1_ex2_csr_zimm
    // combinational derived outputs
    ,output wire                 ex1_ex2_load_op
);

    assign ex1_ex2_load_op = (ex1_ex2_exu_op >= 18'h1d) && (ex1_ex2_exu_op <= 18'h21);

    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            ex1_ex2_valid       <= 1'b0;
            ex1_ex2_pred_taken  <= 1'b0;
            ex1_ex2_wb_ctl      <= 1'b0;
            ex1_ex2_csr_op      <= 1'b0;
        end else if (ex_redirect) begin
            // flush on redirect
            ex1_ex2_valid       <= 1'b0;
            ex1_ex2_pred_taken  <= 1'b0;
            ex1_ex2_wb_ctl      <= 1'b0;
            ex1_ex2_csr_op      <= 1'b0;
        end else if (ex1_dependency_stall) begin
            // insert bubble when dependency stall
            ex1_ex2_valid       <= 1'b0;
            ex1_ex2_pred_taken  <= 1'b0;
            ex1_ex2_wb_ctl      <= 1'b0;
            ex1_ex2_csr_op      <= 1'b0;
        end else if (!ex2_stall) begin
            // normal advancement
            ex1_ex2_valid       <= id_ex_valid;
            ex1_ex2_pred_taken  <= id_ex_valid && id_ex_pred_taken;
            ex1_ex2_wb_ctl      <= id_ex_valid && id_ex_wb_ctl;
            ex1_ex2_csr_op      <= id_ex_valid && id_ex_csr_op;
        end
        // else: hold (ex2_stall without dependency_stall)
    end

    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            ex1_ex2_pc          <= `KLDJ_ZERO32;
            ex1_ex2_snpc        <= `KLDJ_ZERO32;
            ex1_ex2_pred_target <= `KLDJ_ZERO32;
            ex1_ex2_pred_pht_idx <= {BPU_INDEX_WIDTH{1'b0}};
            ex1_ex2_rd_addr     <= 5'd0;
            ex1_ex2_exu_op      <= 18'd0;
            ex1_ex2_alu_ctrl    <= 10'd0;
            ex1_ex2_ls_ctl      <= 4'd0;
            ex1_ex2_data1       <= `KLDJ_ZERO32;
            ex1_ex2_data2       <= `KLDJ_ZERO32;
            ex1_ex2_data3       <= `KLDJ_ZERO32;
            ex1_ex2_data4       <= `KLDJ_ZERO32;
            ex1_ex2_store_wdata <= `KLDJ_ZERO32;
            ex1_ex2_csr_addr    <= 12'b0;
            ex1_ex2_csr_zimm    <= 5'b0;
        end else if (ex1_dependency_stall) begin
            // insert bubble: clear operation-related fields
            ex1_ex2_exu_op      <= 18'd0;
            ex1_ex2_alu_ctrl    <= 10'd0;
            ex1_ex2_ls_ctl      <= 4'd0;
        end else if (!ex2_stall) begin
            // normal advancement
            ex1_ex2_pc          <= id_ex_pc;
            ex1_ex2_snpc        <= id_ex_snpc;
            ex1_ex2_pred_target <= id_ex_valid ? id_ex_pred_target : `KLDJ_ZERO32;
            ex1_ex2_pred_pht_idx <= id_ex_valid ? id_ex_pred_pht_idx : {BPU_INDEX_WIDTH{1'b0}};
            ex1_ex2_rd_addr     <= id_ex_rd_addr;
            ex1_ex2_exu_op      <= id_ex_exu_op;
            ex1_ex2_alu_ctrl    <= id_ex_valid ? id_ex_alu_ctrl : 10'd0;
            ex1_ex2_ls_ctl      <= id_ex_ls_ctl;
            ex1_ex2_data1       <= ex1_data1;
            ex1_ex2_data2       <= ex1_data2;
            ex1_ex2_data3       <= ex1_data3;
            ex1_ex2_data4       <= ex1_data4;
            ex1_ex2_store_wdata <= ex1_store_wdata;
            ex1_ex2_csr_addr    <= id_ex_csr_addr;
            ex1_ex2_csr_zimm    <= id_ex_csr_zimm;
        end
        // else: hold all data (ex2_stall without dependency_stall)
    end

endmodule
