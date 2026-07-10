`include "define.v"

module pipe_if_id(
     input wire                  clk
    ,input wire                  rst
    ,input wire [`KLDJ_INST]     if_inst
    ,input wire [`KLDJ_PC]       if_pc
    ,input wire [`KLDJ_PC]       if_snpc
    ,input wire                  ex_redirect
    ,input wire                  load_use_stall
    ,output reg                  if_id_valid
    ,output reg [`KLDJ_INST]     if_id_inst
    ,output reg [`KLDJ_PC]       if_id_pc
    ,output reg [`KLDJ_PC]       if_id_snpc
);

    localparam [`KLDJ_INST] KLDJ_NOP = 32'h00000013;

    always@(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            if_id_valid <= 1'b0;
            if_id_inst  <= KLDJ_NOP;
            if_id_pc    <= `KLDJ_STARTPC;
            if_id_snpc  <= `KLDJ_STARTPC + `KLDJ_PLUS4;
        end else if(ex_redirect) begin
            if_id_valid <= 1'b0;
            if_id_inst  <= KLDJ_NOP;
            if_id_pc    <= `KLDJ_ZERO32;
            if_id_snpc  <= `KLDJ_ZERO32;
        end else if(!load_use_stall) begin
            if_id_valid <= 1'b1;
            if_id_inst  <= if_inst;
            if_id_pc    <= if_pc;
            if_id_snpc  <= if_snpc;
        end
    end

endmodule
