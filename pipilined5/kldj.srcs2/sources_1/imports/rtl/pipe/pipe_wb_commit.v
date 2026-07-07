`include "../define.v"

module pipe_wb_commit(
     input wire                  clk
    ,input wire                  rst
    ,input wire                  mem_wb_valid
    ,input wire [`KLDJ_PC]       mem_wb_pc
    ,input wire [`KLDJ_REGADDR]  mem_wb_rd_addr
    ,input wire                  mem_wb_wb_ctl
    ,input wire [`KLDJ_DATA]     mem_wb_wb_data
    ,output reg                  wb_commit_valid
    ,output reg [`KLDJ_PC]       wb_commit_pc
    ,output reg [`KLDJ_REGADDR]  wb_commit_rd_addr
    ,output reg                  wb_commit_wb_ctl
    ,output reg [`KLDJ_DATA]     wb_commit_wb_data
);

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            wb_commit_valid   <= 1'b0;
            wb_commit_pc      <= `KLDJ_ZERO32;
            wb_commit_rd_addr <= 5'd0;
            wb_commit_wb_ctl  <= 1'b0;
            wb_commit_wb_data <= `KLDJ_ZERO32;
        end else begin
            wb_commit_valid   <= mem_wb_valid;
            wb_commit_pc      <= mem_wb_pc;
            wb_commit_rd_addr <= mem_wb_rd_addr;
            wb_commit_wb_ctl  <= mem_wb_wb_ctl;
            wb_commit_wb_data <= mem_wb_wb_data;
        end
    end

endmodule
