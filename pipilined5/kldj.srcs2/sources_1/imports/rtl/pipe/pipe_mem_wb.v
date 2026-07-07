`include "../define.v"

module pipe_mem_wb(
     input wire                  clk
    ,input wire                  rst
    // from MEM stage
    ,input wire                  ex_mem_valid
    ,input wire [`KLDJ_PC]       ex_mem_pc
    ,input wire [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,input wire                  mem_stage_wb_ctl
    ,input wire [`KLDJ_DATA]     wb_reg_rd_data
    // pipeline register outputs
    ,output reg                  mem_wb_valid
    ,output reg [`KLDJ_PC]       mem_wb_pc
    ,output reg [`KLDJ_REGADDR]  mem_wb_rd_addr
    ,output reg                  mem_wb_wb_ctl
    ,output reg [`KLDJ_DATA]     mem_wb_wb_data
    // combinational derived outputs
    ,output wire                 mem_wb_forward_valid
);

    assign mem_wb_forward_valid = mem_wb_valid && mem_wb_wb_ctl && (mem_wb_rd_addr != 5'd0);

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            mem_wb_valid   <= 1'b0;
            mem_wb_pc      <= `KLDJ_ZERO32;
            mem_wb_rd_addr <= 5'd0;
            mem_wb_wb_ctl  <= 1'b0;
            mem_wb_wb_data <= `KLDJ_ZERO32;
        end else begin
            mem_wb_valid   <= ex_mem_valid;
            mem_wb_pc      <= ex_mem_pc;
            mem_wb_rd_addr <= ex_mem_rd_addr;
            mem_wb_wb_ctl  <= mem_stage_wb_ctl;
            mem_wb_wb_data <= wb_reg_rd_data;
        end
    end

endmodule