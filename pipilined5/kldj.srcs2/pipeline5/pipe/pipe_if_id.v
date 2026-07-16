`include "../define.v"

module pipe_if_id #(
     parameter BPU_INDEX_WIDTH = 6
)(
     input wire                  clk
    ,input wire                  rst
    ,input wire [`KLDJ_INST]     if_inst
    ,input wire [`KLDJ_PC]       if_pc
    ,input wire [`KLDJ_PC]       if_snpc
    ,input wire                  if_pred_taken
    ,input wire                  if_pred_is_jalr
    ,input wire [`KLDJ_PC]       if_pred_target
    ,input wire [BPU_INDEX_WIDTH-1:0] if_pred_pht_idx
    ,input wire                  ex_redirect
    ,input wire                  load_use_stall
    ,output reg                  if_id_valid
    ,output reg [`KLDJ_INST]     if_id_inst
    ,output reg [`KLDJ_PC]       if_id_pc
    ,output reg [`KLDJ_PC]       if_id_snpc
    ,output reg                  if_id_pred_taken
    ,output reg                  if_id_pred_is_jalr
    ,output reg [`KLDJ_PC]       if_id_pred_target
    ,output reg [BPU_INDEX_WIDTH-1:0] if_id_pred_pht_idx
);

    localparam [`KLDJ_INST] KLDJ_NOP = 32'h00000013;

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            if_id_valid <= 1'b0;
            if_id_pred_taken <= 1'b0;
            if_id_pred_is_jalr <= 1'b0;
        end else if(ex_redirect) begin
            if_id_valid <= 1'b0;
            // Valid marks the bubble; prediction metadata is don't-care
            // while invalid and is kept off the redirect clear cone.
        end else if(!load_use_stall) begin
            if_id_valid <= 1'b1;
            if_id_pred_taken <= if_pred_taken;
            if_id_pred_is_jalr <= if_pred_is_jalr;
        end
    end

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            if_id_inst  <= KLDJ_NOP;
            if_id_pc    <= `KLDJ_STARTPC;
            if_id_snpc  <= `KLDJ_STARTPC + `KLDJ_PLUS4;
            if_id_pred_target <= `KLDJ_ZERO32;
            if_id_pred_pht_idx <= {BPU_INDEX_WIDTH{1'b0}};
        end else if(!load_use_stall) begin
            if_id_inst  <= if_inst;
            if_id_pc    <= if_pc;
            if_id_snpc  <= if_snpc;
            if_id_pred_target <= if_pred_target;
            if_id_pred_pht_idx <= if_pred_pht_idx;
        end
    end

endmodule
