`include "../define.v"

module pipe_ex_mem(
     input wire                  clk
    ,input wire                  rst
    // from EX2 stage (renamed from id_ex_* to ex1_ex2_*)
    ,input wire                  ex1_ex2_valid
    ,input wire [`KLDJ_PC]       ex1_ex2_pc
    ,input wire [`KLDJ_REGADDR]  ex1_ex2_rd_addr
    ,input wire                  ex1_ex2_wb_ctl
    ,input wire [17:0]           ex1_ex2_exu_op
    ,input wire [3:0]            ex1_ex2_ls_ctl
    ,input wire [`KLDJ_DATA]     exu_data
    ,input wire [`KLDJ_DATA]     ex2_mem_addr_i
    ,input wire [`KLDJ_DATA]     ex2_store_wdata
    ,input wire                  ex2_stall
    // pipeline register outputs (renamed from ex_mem_* to ex2_mem_*)
    ,output reg                  ex2_mem_valid
    ,output reg [`KLDJ_PC]       ex2_mem_pc
    ,output reg [`KLDJ_REGADDR]  ex2_mem_rd_addr
    ,output reg                  ex2_mem_wb_ctl
    ,output reg [17:0]           ex2_mem_exu_op
    ,output reg [3:0]            ex2_mem_ls_ctl
    ,output reg [`KLDJ_DATA]     ex2_mem_exu_res
    ,(* keep = "true" *) output reg [`KLDJ_DATA] ex2_mem_mem_addr
    ,output reg [`KLDJ_DATA]     ex2_mem_store_wdata
    // combinational derived outputs
    ,output wire                 ex2_mem_load_op
    ,output wire                 ex2_mem_forward_valid
);

    assign ex2_mem_load_op = (ex2_mem_exu_op >= 18'h1d) && (ex2_mem_exu_op <= 18'h21);
    assign ex2_mem_forward_valid = ex2_mem_valid && ex2_mem_wb_ctl && !ex2_mem_load_op &&
                                   (ex2_mem_rd_addr != 5'd0);

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            ex2_mem_valid       <= 1'b0;
            ex2_mem_pc          <= `KLDJ_ZERO32;
            ex2_mem_rd_addr     <= 5'd0;
            ex2_mem_wb_ctl      <= 1'b0;
            ex2_mem_exu_op      <= 18'd0;
            ex2_mem_ls_ctl      <= 4'd0;
            ex2_mem_exu_res     <= `KLDJ_ZERO32;
            ex2_mem_mem_addr    <= `KLDJ_ZERO32;
            ex2_mem_store_wdata <= `KLDJ_ZERO32;
        end else if(ex2_stall) begin
            ex2_mem_valid       <= 1'b0;
            ex2_mem_pc          <= `KLDJ_ZERO32;
            ex2_mem_rd_addr     <= 5'd0;
            ex2_mem_wb_ctl      <= 1'b0;
            ex2_mem_exu_op      <= 18'd0;
            ex2_mem_ls_ctl      <= 4'd0;
            ex2_mem_exu_res     <= `KLDJ_ZERO32;
            ex2_mem_mem_addr    <= `KLDJ_ZERO32;
            ex2_mem_store_wdata <= `KLDJ_ZERO32;
        end else begin
            ex2_mem_valid       <= ex1_ex2_valid;
            ex2_mem_pc          <= ex1_ex2_pc;
            ex2_mem_rd_addr     <= ex1_ex2_rd_addr;
            ex2_mem_wb_ctl      <= ex1_ex2_valid && ex1_ex2_wb_ctl;
            ex2_mem_exu_op      <= ex1_ex2_exu_op;
            ex2_mem_ls_ctl      <= ex1_ex2_ls_ctl;
            ex2_mem_exu_res     <= exu_data;
            ex2_mem_mem_addr    <= ex2_mem_addr_i;
            ex2_mem_store_wdata <= ex2_store_wdata;
        end
    end

endmodule