`include "../define.v"

module mem_stage_top #(
     parameter ENABLE_MEM2_LOAD_FWD = 1'b0
)(
     // from MEM1/MEM2 pipeline register
     input wire                  mem2_valid
    ,input wire                  mem2_load_op
    ,input wire [3:0]            mem2_ls_ctl
    ,input wire [`KLDJ_DATA]     mem2_exu_res
    ,input wire [1:0]            mem2_addr_low
    ,input wire [`KLDJ_DATA]     mem2_mem_rdata
    ,input wire [`KLDJ_DATA]     mem2_forward_data
    ,input wire                  mem2_wb_ctl
    // outputs to forwarding, WBU and MEM2/WB pipeline
    ,output wire [`KLDJ_DATA]    mem_stage_wb_data
    ,output wire                 mem_stage_wb_ctl
);

    generate
        if (ENABLE_MEM2_LOAD_FWD) begin : g_registered_load_data
            // pipe_mem1_mem2 already selected/extended the load before its
            // output register.  WB and EX forwarding therefore share exactly
            // the same architectural value.
            assign mem_stage_wb_data = mem2_forward_data;
        end else begin : g_legacy_mem2_format
            wire [`KLDJ_DATA] lsu_res;

            KLDJ_lsu lsu3(
                 .ls_ctl       (mem2_ls_ctl           )
                ,.addr_low     (mem2_addr_low         )
                ,.mem_rdata    (mem2_mem_rdata        )
                ,.lsu_res      (lsu_res               )
            );

            assign mem_stage_wb_data = mem2_load_op ? lsu_res : mem2_exu_res;
        end
    endgenerate

    assign mem_stage_wb_ctl  = mem2_valid && mem2_wb_ctl;

endmodule
