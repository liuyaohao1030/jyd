`include "../define.v"

module mem_stage_top(
     input wire                  clk
    ,input wire                  rst
    // from EX2/MEM pipeline register
    ,input wire                  ex_mem_valid
    ,input wire [`KLDJ_PC]       ex_mem_pc
    ,input wire [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,input wire [17:0]           ex_mem_exu_op
    ,input wire [3:0]            ex_mem_ls_ctl
    ,input wire [`KLDJ_DATA]     ex_mem_exu_res
    ,input wire [`KLDJ_DATA]     ex_mem_mem_addr
    ,input wire [`KLDJ_DATA]     ex_mem_store_wdata
    ,input wire                  ex_mem_wb_ctl
    // Final bridge response.  This already includes DRAM store forwarding
    // and the DRAM/MMIO response selection.
    ,input wire [`KLDJ_DATA]     mem_rdata
    // MEM-response metadata used by forwarding and the MEM/WB register.
    ,output reg                  mem_resp_valid
    ,output reg [`KLDJ_PC]       mem_resp_pc
    ,output reg [`KLDJ_REGADDR]  mem_resp_rd_addr
    ,output wire                 mem_resp_forward_valid
    // Response-stage result sent to WBU and MEM/WB.
    ,output wire [`KLDJ_DATA]    mem_stage_wb_data
    ,output wire                 mem_stage_wb_ctl
);

    // ------------------------------------------------------------------
    // MEM-response pipeline register
    //
    // The synchronous memory response is aligned with ex_mem_* during the
    // cycle after the EX2 request.  Registering both the raw response and all
    // instruction metadata here breaks the BRAM/bridge -> LSU -> MEM/WB path
    // without losing alignment for back-to-back requests.
    //
    // This stage always drains.  It must not be flushed by a younger redirect
    // or held by an EX2 multi-cycle stall; pipe_ex_mem already inserts the
    // corresponding bubble.
    // ------------------------------------------------------------------
    reg                          mem_resp_wb_ctl;
    reg [17:0]                   mem_resp_exu_op;
    reg [3:0]                    mem_resp_ls_ctl;
    reg [`KLDJ_DATA]             mem_resp_exu_res;
    reg [`KLDJ_DATA]             mem_resp_mem_addr;
    reg [`KLDJ_DATA]             mem_resp_store_wdata;
    reg [`KLDJ_DATA]             mem_resp_rdata;

    // Only validity/control need reset.  The data bundle is ignored whenever
    // mem_resp_valid is low, so leaving it reset-free avoids adding a wide
    // bank of loads to the already high-fanout core reset network.
    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            mem_resp_valid  <= 1'b0;
            mem_resp_wb_ctl <= 1'b0;
        end else begin
            mem_resp_valid  <= ex_mem_valid;
            mem_resp_wb_ctl <= ex_mem_valid && ex_mem_wb_ctl;
        end
    end

    always @(posedge clk) begin
        mem_resp_pc          <= ex_mem_pc;
        mem_resp_rd_addr     <= ex_mem_rd_addr;
        mem_resp_exu_op      <= ex_mem_exu_op;
        mem_resp_ls_ctl      <= ex_mem_ls_ctl;
        mem_resp_exu_res     <= ex_mem_exu_res;
        mem_resp_mem_addr    <= ex_mem_mem_addr;
        mem_resp_store_wdata <= ex_mem_store_wdata;
        mem_resp_rdata       <= mem_rdata;
    end

    // LSU internal wires
    wire [`KLDJ_DATA]            lsu_mem_addr;
    wire [`KLDJ_DATA]            lsu_mem_wdata;
    wire                         lsu_mem_we;
    wire [3:0]                   lsu_mem_be;
    wire [`KLDJ_DATA]            lsu_res;
    wire                         lsu_is_load;

    KLDJ_lsu lsu3(
         .exu_op      (mem_resp_exu_op       )
        ,.id_ls_ctl   (mem_resp_ls_ctl       )
        ,.ls_addr     (mem_resp_mem_addr     )
        ,.ls_wdata    (mem_resp_store_wdata  )
        ,.mem_addr    (lsu_mem_addr          )
        ,.mem_wdata   (lsu_mem_wdata         )
        ,.mem_we      (lsu_mem_we            )
        ,.mem_be      (lsu_mem_be            )
        ,.mem_rdata   (mem_resp_rdata        )
        ,.lsu_res     (lsu_res               )
        ,.is_load     (lsu_is_load           )
    );

    // Memory requests are issued directly from EX2 by ex_mem_req_ctrl.  The
    // LSU request outputs above are intentionally unused in this response
    // stage; only load formatting and writeback selection remain here.
    assign mem_stage_wb_data = lsu_is_load ? lsu_res : mem_resp_exu_res;
    assign mem_stage_wb_ctl = mem_resp_valid && mem_resp_wb_ctl;
    assign mem_resp_forward_valid = mem_resp_valid && mem_resp_wb_ctl &&
                                    (mem_resp_rd_addr != 5'd0);

endmodule
