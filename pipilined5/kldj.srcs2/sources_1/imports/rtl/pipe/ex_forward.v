`include "../define.v"

module ex_forward(
     // from ID/EX pipeline register
     input wire                  id_ex_valid
    ,input wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input wire                  id_ex_rs1_ren
    ,input wire                  id_ex_rs2_ren
    // Selected in ID and captured with the consumer in ID/EX.  At this
    // point the selected producers have advanced to EX/MEM or MEM/WB.
    ,input wire [1:0]            id_ex_rs1_fwd_sel
    ,input wire [1:0]            id_ex_rs2_fwd_sel
    ,input wire                  id_ex_load_op
    ,input wire                  id_ex_store_op
    ,input wire                  id_ex_rs2_to_data2
    ,input wire [`KLDJ_DATA]     id_ex_data1
    ,input wire [`KLDJ_DATA]     id_ex_data2
    ,input wire [`KLDJ_DATA]     id_ex_data3
    ,input wire [`KLDJ_DATA]     id_ex_data4
    ,input wire [`KLDJ_DATA]     id_ex_rs1_data
    ,input wire [`KLDJ_DATA]     id_ex_rs2_data
    // from EX/MEM pipeline register
    ,input wire [`KLDJ_DATA]     ex_mem_exu_res
    // from MEM/WB pipeline register
    ,input wire [`KLDJ_DATA]     mem_wb_wb_data
    // from IF/ID stage
    ,input wire                  if_id_valid
    ,input wire [`KLDJ_REGADDR]  id_reg_rs1_addr
    ,input wire [`KLDJ_REGADDR]  id_reg_rs2_addr
    ,input wire                  id_reg_rs1_ren
    ,input wire                  id_reg_rs2_ren
    // outputs to EXU
    ,output wire [`KLDJ_DATA]    ex_data1
    ,output wire [`KLDJ_DATA]    ex_data2
    ,output wire [`KLDJ_DATA]    ex_data3
    ,output wire [`KLDJ_DATA]    ex_data4
    ,output wire [`KLDJ_DATA]    ex_store_wdata
    // outputs to pipeline control
    ,output wire                 load_use_stall
);

    wire [`KLDJ_DATA]            ex_rs1_data;
    wire [`KLDJ_DATA]            ex_rs2_data;

    localparam [1:0] FWD_EX_MEM  = 2'b01;
    localparam [1:0] FWD_MEM_WB  = 2'b10;
    assign load_use_stall = id_ex_valid && id_ex_load_op && (id_ex_rd_addr != 5'd0) &&
                            if_id_valid &&
                            ((id_reg_rs1_ren && (id_reg_rs1_addr == id_ex_rd_addr)) ||
                             (id_reg_rs2_ren && (id_reg_rs2_addr == id_ex_rd_addr)));

    // Keep the data-source priority identical to the former EX-stage
    // comparisons, but remove id_ex_rs*_addr from this timing cone.
    assign ex_rs1_data = (id_ex_rs1_fwd_sel == FWD_EX_MEM) ? ex_mem_exu_res :
                         (id_ex_rs1_fwd_sel == FWD_MEM_WB) ? mem_wb_wb_data :
                                                               id_ex_rs1_data;

    assign ex_rs2_data = (id_ex_rs2_fwd_sel == FWD_EX_MEM) ? ex_mem_exu_res :
                         (id_ex_rs2_fwd_sel == FWD_MEM_WB) ? mem_wb_wb_data :
                                                               id_ex_rs2_data;

    assign ex_data1 = id_ex_rs1_ren ? ex_rs1_data : id_ex_data1;
    assign ex_data2 = id_ex_rs2_to_data2 ? ex_rs2_data : id_ex_data2;
    assign ex_data3 = id_ex_data3;
    assign ex_data4 = id_ex_data4;
    assign ex_store_wdata = id_ex_store_op ? ex_rs2_data : id_ex_data3;

endmodule
