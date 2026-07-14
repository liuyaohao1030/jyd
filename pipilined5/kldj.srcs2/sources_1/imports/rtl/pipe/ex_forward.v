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
    // outputs to EX1/EX2 pipeline register (renamed for clarity)
    ,output wire [`KLDJ_DATA]    ex1_data1
    ,output wire [`KLDJ_DATA]    ex1_data2
    ,output wire [`KLDJ_DATA]    ex1_data3
    ,output wire [`KLDJ_DATA]    ex1_data4
    ,output wire [`KLDJ_DATA]    ex1_store_wdata
    ,output wire [`KLDJ_DATA]    ex1_rs1_data
    ,output wire [`KLDJ_DATA]    ex1_rs2_data
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

    // Removed old load_use_stall logic - now handled by ex1_hazard module

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

    assign id_ex_rs2_to_data2 = ((id_ex_exu_op >= 18'ha) && (id_ex_exu_op <= 18'h19)) |
                                ((id_ex_exu_op >= 18'h25) && (id_ex_exu_op <= 18'h2c));
    assign id_ex_store_op = ((id_ex_exu_op >= 18'h22) && (id_ex_exu_op <= 18'h24));

    assign ex1_data1 = id_ex_rs1_ren ? ex_rs1_data : id_ex_data1;
    assign ex1_data2 = id_ex_rs2_to_data2 ? ex_rs2_data : id_ex_data2;
    assign ex1_data3 = id_ex_data3;
    assign ex1_data4 = id_ex_data4;
    assign ex1_store_wdata = id_ex_store_op ? ex_rs2_data : id_ex_data3;
    assign ex1_rs1_data = ex_rs1_data;
    assign ex1_rs2_data = ex_rs2_data;

endmodule
