`include "../define.v"

// EX1 hazard detection unit
// Detects RAW dependencies between ID/EX (EX1 stage) and EX1/EX2 or EX2/MEM
// Conservative strategy: stall 1 cycle for any dependency
module ex1_hazard(
    // from ID/EX pipeline register (EX1 stage)
    input wire                  id_ex_valid
    ,input wire [`KLDJ_REGADDR]  id_ex_rs1_addr
    ,input wire [`KLDJ_REGADDR]  id_ex_rs2_addr
    ,input wire                  id_ex_rs1_ren
    ,input wire                  id_ex_rs2_ren
    // from EX1/EX2 pipeline register
    ,input wire                  ex1_ex2_valid
    ,input wire [`KLDJ_REGADDR]  ex1_ex2_rd_addr
    ,input wire                  ex1_ex2_wb_ctl
    // from EX2/MEM pipeline register
    ,input wire                  ex2_mem_valid
    ,input wire [`KLDJ_REGADDR]  ex2_mem_rd_addr
    ,input wire                  ex2_mem_wb_ctl
    ,input wire                  ex2_mem_load_op
    // outputs
    ,output wire                 ex1_dependency_stall
);

    // Check if EX1 stage depends on EX2 stage (EX1/EX2 register)
    wire ex1_ex2_rs1_depend = id_ex_rs1_ren && ex1_ex2_valid && ex1_ex2_wb_ctl &&
                              (id_ex_rs1_addr != 5'd0) && (id_ex_rs1_addr == ex1_ex2_rd_addr);
    wire ex1_ex2_rs2_depend = id_ex_rs2_ren && ex1_ex2_valid && ex1_ex2_wb_ctl &&
                              (id_ex_rs2_addr != 5'd0) && (id_ex_rs2_addr == ex1_ex2_rd_addr);

    // Check if EX1 stage depends on MEM stage load (EX2/MEM register)
    // Non-load results in EX2/MEM can be forwarded, but loads must stall
    wire ex2_mem_rs1_depend = id_ex_rs1_ren && ex2_mem_valid && ex2_mem_wb_ctl &&
                              ex2_mem_load_op && (id_ex_rs1_addr != 5'd0) &&
                              (id_ex_rs1_addr == ex2_mem_rd_addr);
    wire ex2_mem_rs2_depend = id_ex_rs2_ren && ex2_mem_valid && ex2_mem_wb_ctl &&
                              ex2_mem_load_op && (id_ex_rs2_addr != 5'd0) &&
                              (id_ex_rs2_addr == ex2_mem_rd_addr);

    // Conservative stall: any dependency causes stall
    assign ex1_dependency_stall = id_ex_valid &&
                                  (ex1_ex2_rs1_depend || ex1_ex2_rs2_depend ||
                                   ex2_mem_rs1_depend || ex2_mem_rs2_depend);

endmodule
