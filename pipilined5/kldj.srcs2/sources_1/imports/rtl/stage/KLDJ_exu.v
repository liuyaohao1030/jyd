`include "../define.v"

module KLDJ_exu(
     input  wire [`KLDJ_DATA]   data1
    ,input  wire [`KLDJ_DATA]   data2
    ,input  wire [`KLDJ_DATA]   data3
    ,input  wire [`KLDJ_DATA]   data4
    ,input  wire [17:0]         exu_op
    ,input  wire [9:0]          alu_ctrl
    // CSR interface
    ,input  wire [11:0]         csr_addr
    ,input  wire                csr_op
    ,input  wire [4:0]          csr_zimm
    ,input  wire [`KLDJ_DATA]   csr_rdata
    ,output wire                csr_we
    ,output wire [`KLDJ_DATA]   csr_wdata
    // ecall/mret interface
    ,output wire                is_ecall
    ,output wire                is_mret
    ,input  wire [`KLDJ_DATA]   mret_pc
    // original outputs
    ,output wire                exu_jump
    ,output wire [`KLDJ_DATA]   exu_jump_pc
    ,output wire [`KLDJ_DATA]   exu_res
);

    wire [`KLDJ_DATA] alu_res;
    wire [3:0] cmp_res;

    KLDJ_alu u_KLDJ_alu(
         .op1    (data1)
        ,.op2    (data2)
        ,.alu_op (alu_ctrl)
        ,.alu_res(alu_res)
        ,.cmp_res(cmp_res)
    );

    wire is_ge_res  = cmp_res[3];
    wire is_ne_res  = cmp_res[2];
    wire is_equ_res = cmp_res[1];
    wire is_lt_res  = cmp_res[0];

    wire branch_taken =
        (exu_op == 18'h14 && is_equ_res) | // beq
        (exu_op == 18'h15 && is_ne_res)  | // bne
        (exu_op == 18'h16 && is_lt_res)  | // blt
        (exu_op == 18'h17 && is_ge_res)  | // bge
        (exu_op == 18'h18 && is_lt_res)  | // bltu
        (exu_op == 18'h19 && is_ge_res)  ; // bgeu

    wire [`KLDJ_DATA] branch_target = data3 + data4;

    // CSR instruction detection
    wire is_csrrw  = (exu_op == `KLDJ_EXU_CSRRW);
    wire is_csrrs  = (exu_op == `KLDJ_EXU_CSRRS);
    wire is_csrrc  = (exu_op == `KLDJ_EXU_CSRRC);
    wire is_csrrwi = (exu_op == `KLDJ_EXU_CSRRWI);
    wire is_csrrsi = (exu_op == `KLDJ_EXU_CSRRSI);
    wire is_csrrci = (exu_op == `KLDJ_EXU_CSRRCI);
    wire is_csr = is_csrrw | is_csrrs | is_csrrc | is_csrrwi | is_csrrsi | is_csrrci;

    // ecall/mret detection
    assign is_ecall = (exu_op == `KLDJ_EXU_ECALL);
    assign is_mret  = (exu_op == `KLDJ_EXU_MRET);

    // CSR write enable and data
    assign csr_we = is_csr;
    assign csr_wdata = is_csrrw  ? data1 :                     // CSRRW: write rs1/zimm
                       is_csrrs  ? (csr_rdata | data1) :       // CSRRS: set bits
                       is_csrrc  ? (csr_rdata & ~data1) :      // CSRRC: clear bits
                       is_csrrwi ? data1 :                     // CSRRWI: write zimm
                       is_csrrsi ? (csr_rdata | data1) :       // CSRRSI: set bits
                       is_csrrci ? (csr_rdata & ~data1) :      // CSRRCI: clear bits
                       32'b0;

    // 对于普通指令和访存指令（基址计算），输出 ALU 的计算结果
    // 对于 JAL/JALR，输出 data3 (即 snpc)
    // 对于 CSR 指令，输出旧 CSR 值 (写入 rd)
    assign exu_res = (exu_op == 18'h9 | exu_op == 18'h1c) ? data3 :
                     is_csr ? csr_rdata :
                     alu_res;

    // mret also triggers a jump
    assign exu_jump = (exu_op == 18'h9 | exu_op == 18'h1c) | branch_taken | is_mret;
    assign exu_jump_pc = (exu_op == 18'h9) ? {alu_res[31:1], 1'b0} :
                         (exu_op == 18'h1c) ? alu_res :
                         (branch_taken) ? branch_target :
                         is_mret ? mret_pc :
                         32'b0;

endmodule
