`include "../define.v"

// DRAM/bridge response boundary.  The optional early formatter turns the
// synchronous response into a registered MEM2 forwarding value, so the EX
// stage never receives a live BRAM/bridge response.
module pipe_mem1_mem2 #(
     parameter ENABLE_MEM2_LOAD_FWD = 1'b0,
     parameter ENABLE_FAST_DRAM_LW_FWD = 1'b0
)(
     input wire                  clk
    ,input wire                  rst
    // from EX/MEM (MEM1 control) and the synchronous memory response
    ,input wire                  ex_mem_valid
    ,input wire [`KLDJ_PC]       ex_mem_pc
    ,input wire [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,input wire                  ex_mem_wb_ctl
    ,input wire                  ex_mem_load_op
    ,input wire [3:0]            ex_mem_ls_ctl
    ,input wire [`KLDJ_DATA]     ex_mem_exu_res
    ,input wire [1:0]            ex_mem_addr_low
    ,input wire [`KLDJ_DATA]     mem_rdata
    ,input wire                  ex_mem_fast_lw
    // MEM2 pipeline state
    ,output reg                  mem2_valid
    ,output reg [`KLDJ_PC]       mem2_pc
    ,output reg [`KLDJ_REGADDR]  mem2_rd_addr
    ,output reg                  mem2_wb_ctl
    ,output reg                  mem2_load_op
    ,output reg [3:0]            mem2_ls_ctl
    ,output reg [`KLDJ_DATA]     mem2_exu_res
    ,output reg [1:0]            mem2_addr_low
    ,output reg [`KLDJ_DATA]     mem2_mem_rdata
    // Registered value used by MEM2 forwarding.  In the optimized mode this
    // is the fully formatted load result; non-load producers always carry
    // their EX result.
    ,output reg [`KLDJ_DATA]     mem2_forward_data
    ,output reg                  mem2_forward_valid
    ,output reg                  mem2_fast_lw
);

    wire [`KLDJ_DATA] mem1_load_data;
    wire [`KLDJ_DATA] mem1_forward_data;

    // In fast mode the load response is registered beside perip_bridge and is
    // consumed directly during MEM2.  This register carries only pipeline
    // metadata and non-load EX results; sampling the bridge register here
    // would make the response one cycle late.
    generate
        if (ENABLE_MEM2_LOAD_FWD && ENABLE_FAST_DRAM_LW_FWD) begin : g_fast_dram_lw
            assign mem1_load_data    = `KLDJ_ZERO32;
            assign mem1_forward_data = ex_mem_exu_res;
        end else if (ENABLE_MEM2_LOAD_FWD) begin : g_early_load_format
            KLDJ_lsu u_mem1_load_format(
                 .ls_ctl   (ex_mem_ls_ctl )
                ,.addr_low (ex_mem_addr_low)
                ,.mem_rdata(mem_rdata      )
                ,.lsu_res  (mem1_load_data )
            );
            assign mem1_forward_data = ex_mem_load_op ? mem1_load_data :
                                      ex_mem_exu_res;
        end else begin : g_no_early_load_format
            assign mem1_load_data = `KLDJ_ZERO32;
            assign mem1_forward_data = ex_mem_exu_res;
        end
    endgenerate

    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            mem2_valid         <= 1'b0;
            mem2_pc            <= `KLDJ_ZERO32;
            mem2_rd_addr       <= 5'd0;
            mem2_wb_ctl        <= 1'b0;
            mem2_load_op       <= 1'b0;
            mem2_ls_ctl        <= 4'd0;
            mem2_exu_res       <= `KLDJ_ZERO32;
            mem2_addr_low      <= 2'b00;
            mem2_mem_rdata     <= `KLDJ_ZERO32;
            mem2_forward_data  <= `KLDJ_ZERO32;
            mem2_forward_valid <= 1'b0;
            mem2_fast_lw       <= 1'b0;
        end else begin
            mem2_valid         <= ex_mem_valid;
            mem2_pc            <= ex_mem_pc;
            mem2_rd_addr       <= ex_mem_rd_addr;
            mem2_wb_ctl        <= ex_mem_wb_ctl;
            mem2_load_op       <= ex_mem_load_op;
            mem2_ls_ctl        <= ex_mem_ls_ctl;
            mem2_exu_res       <= ex_mem_exu_res;
            mem2_addr_low      <= ex_mem_addr_low;
            mem2_mem_rdata     <= mem_rdata;
            mem2_forward_data  <= mem1_forward_data;
            mem2_forward_valid <= ex_mem_valid && ex_mem_wb_ctl &&
                                  (ex_mem_rd_addr != 5'd0) &&
                                  (!ex_mem_load_op ||
                                   !ENABLE_FAST_DRAM_LW_FWD || ex_mem_fast_lw);
            mem2_fast_lw       <= ex_mem_fast_lw;
        end
    end

endmodule

module pipe_mem_wb(
     input wire                  clk
    ,input wire                  rst
    // from MEM2 stage
    ,input wire                  mem2_valid
    ,input wire [`KLDJ_PC]       mem2_pc
    ,input wire [`KLDJ_REGADDR]  mem2_rd_addr
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
            mem_wb_valid   <= mem2_valid;
            mem_wb_pc      <= mem2_pc;
            mem_wb_rd_addr <= mem2_rd_addr;
            mem_wb_wb_ctl  <= mem_stage_wb_ctl;
            mem_wb_wb_data <= wb_reg_rd_data;
        end
    end

endmodule
