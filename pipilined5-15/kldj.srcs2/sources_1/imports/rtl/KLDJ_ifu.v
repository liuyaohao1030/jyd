 `include "define.v"

module KLDJ_ifu (
  input  wire                        clk
 ,input  wire                        rst
 ,input  wire                        hold
 ,input  wire                        jump
 ,input  wire     [`KLDJ_PC]         jump_pc
 ,input  wire    [`KLDJ_INST]        inst_i

 ,output wire     [`KLDJ_INST]       inst_o
 ,output wire    [`KLDJ_PC]          pc_o
 ,output wire    [`KLDJ_PC]          snpc
 );

 reg  [`KLDJ_PC] pc_reg;
 wire [`KLDJ_PC] dnpc;

 assign snpc = pc_o + 4;
 assign dnpc = jump ? jump_pc : snpc;

 always@(posedge clk) begin
    if(rst == `KLDJ_RSTABLE)begin
        pc_reg <= `KLDJ_STARTPC;
    end
    else if(hold) begin
        pc_reg <= pc_reg;
    end
    else begin
        pc_reg <= dnpc;
    end
end

 assign inst_o = inst_i;
 assign pc_o   = pc_reg;

endmodule
