`include "define.v"

module mem_stage_top(
     // from EX/MEM pipeline register
     input wire                  ex_mem_valid
    ,input wire [17:0]           ex_mem_exu_op
    ,input wire [3:0]            ex_mem_ls_ctl
    ,input wire [`KLDJ_DATA]     ex_mem_exu_res
    ,input wire [`KLDJ_DATA]     ex_mem_mem_addr
    ,input wire [`KLDJ_DATA]     ex_mem_store_wdata
    ,input wire                  ex_mem_wb_ctl
    // external memory interface
    ,input wire [`KLDJ_DATA]     mem_rdata
    ,output wire [`KLDJ_DATA]    mem_addr
    ,output wire [`KLDJ_DATA]    mem_wdata
    ,output wire                 mem_we
    ,output wire [3:0]           mem_be
    // outputs to WBU and MEM/WB pipeline
    ,output wire [`KLDJ_DATA]    mem_stage_wb_data
    ,output wire                 mem_stage_wb_ctl
);

    // LSU internal wires
    wire [`KLDJ_DATA]            lsu_mem_addr;
    wire [`KLDJ_DATA]            lsu_mem_wdata;
    wire                         lsu_mem_we;
    wire [3:0]                   lsu_mem_be;
    wire [`KLDJ_DATA]            lsu_res;
    wire                         lsu_is_load;

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

endmodule
