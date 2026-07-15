`include "../define.v"

// Forwarding-source predecode for control-flow operands.
//
// The source instruction is in IF/ID while this block is evaluated.  At the
// following edge the current ID/EX producer advances to EX/MEM, and the
// current EX/MEM producer advances to MEM/WB.  The select values therefore
// describe the sources that will be visible to the newly captured ID/EX
// control-flow instruction in its EX cycle.
module ctrl_forward_sel(
     input  wire                  ctrl_rs1_ren
    ,input  wire                  ctrl_rs2_ren
    ,input  wire [`KLDJ_REGADDR]  id_rs1_addr
    ,input  wire [`KLDJ_REGADDR]  id_rs2_addr
    // Current EX-stage producer, becomes EX/MEM after this edge.
    ,input  wire                  id_ex_valid
    ,input  wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input  wire                  id_ex_wb_ctl
    ,input  wire                  id_ex_load_op
    // Current MEM-stage producer, becomes MEM/WB after this edge.
    ,input  wire [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,input  wire                  mem_stage_wb_ctl
    ,output reg  [1:0]            ctrl_rs1_fwd_sel
    ,output reg  [1:0]            ctrl_rs2_fwd_sel
);

    localparam [1:0] FWD_REGFILE = 2'b00;
    localparam [1:0] FWD_EX_MEM  = 2'b01;
    localparam [1:0] FWD_MEM_WB  = 2'b10;

    // A load result is not ready when its instruction leaves EX.  A direct
    // load-use dependency is held in ID by the existing load_use_stall path;
    // a current MEM-stage load is legal because its data enters MEM/WB on the
    // same edge as the select register.
    wire ex_can_forward = id_ex_valid && id_ex_wb_ctl && !id_ex_load_op &&
                          (id_ex_rd_addr != 5'd0);
    wire mem_can_forward = mem_stage_wb_ctl && (ex_mem_rd_addr != 5'd0);

    always @(*) begin
        ctrl_rs1_fwd_sel = FWD_REGFILE;
        if (ctrl_rs1_ren) begin
            if (ex_can_forward && (id_rs1_addr == id_ex_rd_addr))
                ctrl_rs1_fwd_sel = FWD_EX_MEM;
            else if (mem_can_forward && (id_rs1_addr == ex_mem_rd_addr))
                ctrl_rs1_fwd_sel = FWD_MEM_WB;
        end

        ctrl_rs2_fwd_sel = FWD_REGFILE;
        if (ctrl_rs2_ren) begin
            if (ex_can_forward && (id_rs2_addr == id_ex_rd_addr))
                ctrl_rs2_fwd_sel = FWD_EX_MEM;
            else if (mem_can_forward && (id_rs2_addr == ex_mem_rd_addr))
                ctrl_rs2_fwd_sel = FWD_MEM_WB;
        end
    end

endmodule
