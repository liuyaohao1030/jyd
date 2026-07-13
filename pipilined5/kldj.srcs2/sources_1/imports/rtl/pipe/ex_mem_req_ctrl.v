`include "../define.v"

module ex_mem_req_ctrl(
    input  wire                  id_ex_valid
    ,input  wire                  ex_stall
    ,input  wire                  id_ex_load_op
    ,input  wire                  id_ex_store_op
    ,input  wire [3:0]            id_ex_ls_ctl
    ,input  wire [`KLDJ_DATA]     ex_mem_addr_pre
    ,input  wire [`KLDJ_DATA]     ex_store_wdata

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

    assign ex_req_load  = id_ex_load_op;
    assign ex_req_store = id_ex_store_op;
    assign ex_req_mem   = id_ex_valid && !ex_stall && (ex_req_load || ex_req_store);
    assign ex_req_size  = id_ex_ls_ctl[1:0];
    assign ex_req_be    = (ex_req_size == 2'b00) ? (4'b0001 << ex_mem_addr_pre[1:0]) :
                          (ex_req_size == 2'b01) ? (4'b0011 << {ex_mem_addr_pre[1], 1'b0}) :
                          (ex_req_size == 2'b10) ? 4'b1111 : 4'b0000;
    assign ex_req_wdata = (ex_req_size == 2'b00) ? {4{ex_store_wdata[7:0]}} :
                          (ex_req_size == 2'b01) ? {2{ex_store_wdata[15:0]}} :
                          ex_store_wdata;

    assign mem_addr  = ex_req_mem ? ex_mem_addr_pre : `KLDJ_ZERO32;
    assign mem_wdata = (id_ex_valid && !ex_stall && ex_req_store) ? ex_req_wdata : `KLDJ_ZERO32;
    assign mem_we    = id_ex_valid && !ex_stall && ex_req_store;
    assign mem_be    = ex_req_mem ? ex_req_be : 4'b0000;

endmodule
