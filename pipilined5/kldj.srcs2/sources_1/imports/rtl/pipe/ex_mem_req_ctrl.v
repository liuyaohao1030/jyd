`include "../define.v"

module ex_mem_req_ctrl(
     input  wire                  ex1_ex2_valid
    ,input  wire                  ex2_stall
    ,input  wire [17:0]           ex1_ex2_exu_op
    ,input  wire [3:0]            ex1_ex2_ls_ctl
    ,input  wire [`KLDJ_DATA]     ex2_mem_addr_pre
    ,input  wire [`KLDJ_DATA]     ex2_store_wdata

    ,output wire [`KLDJ_DATA]     mem_addr
    ,output wire [`KLDJ_DATA]     mem_wdata
    ,output wire                  mem_we
    ,output wire [3:0]            mem_be
);

    wire       ex_req_load;
    wire       ex_req_store;
    wire       ex_req_mem;
    wire [1:0] ex_req_size;
    wire [3:0] ex_req_be;
    wire [`KLDJ_DATA] ex_req_wdata;

    assign ex_req_load  = (ex1_ex2_exu_op >= 18'h1d) && (ex1_ex2_exu_op <= 18'h21);
    assign ex_req_store = (ex1_ex2_exu_op >= 18'h22) && (ex1_ex2_exu_op <= 18'h24);
    assign ex_req_mem   = ex1_ex2_valid && !ex2_stall && (ex_req_load || ex_req_store);
    assign ex_req_size  = ex1_ex2_ls_ctl[1:0];
    assign ex_req_be    = (ex_req_size == 2'b00) ? (4'b0001 << ex2_mem_addr_pre[1:0]) :
                          (ex_req_size == 2'b01) ? (4'b0011 << {ex2_mem_addr_pre[1], 1'b0}) :
                          (ex_req_size == 2'b10) ? 4'b1111 : 4'b0000;
    assign ex_req_wdata = (ex_req_size == 2'b00) ? {4{ex2_store_wdata[7:0]}} :
                          (ex_req_size == 2'b01) ? {2{ex2_store_wdata[15:0]}} :
                          ex2_store_wdata;

    assign mem_addr  = ex_req_mem ? ex2_mem_addr_pre : `KLDJ_ZERO32;
    assign mem_wdata = (ex1_ex2_valid && !ex2_stall && ex_req_store) ? ex_req_wdata : `KLDJ_ZERO32;
    assign mem_we    = ex1_ex2_valid && !ex2_stall && ex_req_store;
    assign mem_be    = ex_req_mem ? ex_req_be : 4'b0000;

endmodule
