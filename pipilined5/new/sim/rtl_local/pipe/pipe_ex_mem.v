`include "define.v"

module pipe_ex_mem(
     input wire                  clk
    ,input wire                  rst
    // from EX stage
    ,input wire                  id_ex_valid
    ,input wire [`KLDJ_PC]       id_ex_pc
    ,input wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input wire                  id_ex_wb_ctl
    ,input wire [17:0]           id_ex_exu_op
    ,input wire [3:0]            id_ex_ls_ctl
    ,input wire [`KLDJ_DATA]     exu_data
    ,input wire [`KLDJ_DATA]     ex_mem_addr_i
    ,input wire [`KLDJ_DATA]     ex_store_wdata
    ,input wire                  ex_stall
    // pipeline register outputs
    ,output reg                  ex_mem_valid
    ,output reg [`KLDJ_PC]       ex_mem_pc
    ,output reg [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,output reg                  ex_mem_wb_ctl
    ,output reg [17:0]           ex_mem_exu_op
    ,output reg [3:0]            ex_mem_ls_ctl
    ,output reg [`KLDJ_DATA]     ex_mem_exu_res
    ,(* keep = "true" *) output reg [`KLDJ_DATA] ex_mem_mem_addr
    ,output reg [`KLDJ_DATA]     ex_mem_store_wdata
    // combinational derived outputs
    ,output wire                 ex_mem_load_op
    ,output wire                 ex_mem_forward_valid
);

    assign ex_mem_load_op = (ex_mem_exu_op >= 18'h1d) && (ex_mem_exu_op <= 18'h21);
    assign ex_mem_forward_valid = ex_mem_valid && ex_mem_wb_ctl && !ex_mem_load_op &&
                                  (ex_mem_rd_addr != 5'd0);

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            ex_mem_valid       <= 1'b0;
            ex_mem_pc          <= `KLDJ_ZERO32;
            ex_mem_rd_addr     <= 5'd0;
            ex_mem_wb_ctl      <= 1'b0;
            ex_mem_exu_op      <= 18'd0;
            ex_mem_ls_ctl      <= 4'd0;
            ex_mem_exu_res     <= `KLDJ_ZERO32;
            ex_mem_mem_addr    <= `KLDJ_ZERO32;
            ex_mem_store_wdata <= `KLDJ_ZERO32;
        end else if(ex_stall) begin
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
            ex_mem_mem_addr    <= ex_mem_addr_i;
            ex_mem_store_wdata <= ex_store_wdata;
        end
    end

endmodule