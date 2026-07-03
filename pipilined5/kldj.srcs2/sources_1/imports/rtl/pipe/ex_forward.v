`include "../define.v"

module ex_forward(
     // from ID/EX pipeline register
     input wire                  id_ex_valid
    ,input wire [`KLDJ_REGADDR]  id_ex_rs1_addr
    ,input wire [`KLDJ_REGADDR]  id_ex_rs2_addr
    ,input wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input wire                  id_ex_rs1_ren
    ,input wire                  id_ex_rs2_ren
    ,input wire [17:0]           id_ex_exu_op
    ,input wire [`KLDJ_DATA]     id_ex_data1
    ,input wire [`KLDJ_DATA]     id_ex_data2
    ,input wire [`KLDJ_DATA]     id_ex_data3
    ,input wire [`KLDJ_DATA]     id_ex_data4
    ,input wire [`KLDJ_DATA]     id_ex_rs1_data
    ,input wire [`KLDJ_DATA]     id_ex_rs2_data
    // from EX/MEM pipeline register
    ,input wire [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,input wire [`KLDJ_DATA]     ex_mem_exu_res
    ,input wire                  ex_mem_forward_valid
    // from MEM/WB pipeline register
    ,input wire [`KLDJ_REGADDR]  mem_wb_rd_addr
    ,input wire [`KLDJ_DATA]     mem_wb_wb_data
    ,input wire                  mem_wb_forward_valid
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

    wire                         ex_mem_rs1_forward_hit;
    wire                         mem_wb_rs1_forward_hit;
    wire                         ex_mem_rs2_forward_hit;
    wire                         mem_wb_rs2_forward_hit;
    wire [`KLDJ_DATA]            ex_rs1_data;
    wire [`KLDJ_DATA]            ex_rs2_data;
    wire                         id_ex_rs2_to_data2;
    wire                         id_ex_store_op;
    wire                         id_ex_load_op;

    assign id_ex_load_op = (id_ex_exu_op >= 18'h1d) && (id_ex_exu_op <= 18'h21);

    assign load_use_stall = id_ex_valid && id_ex_load_op && (id_ex_rd_addr != 5'd0) &&
                            if_id_valid &&
                            ((id_reg_rs1_ren && (id_reg_rs1_addr == id_ex_rd_addr)) ||
                             (id_reg_rs2_ren && (id_reg_rs2_addr == id_ex_rd_addr)));

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

endmodule
