`include "define.v"

module KLDJ_exu(
     input  wire [`KLDJ_DATA]   data1
    ,input  wire [`KLDJ_DATA]   data2
    ,input  wire [`KLDJ_DATA]   data3
    ,input  wire [`KLDJ_DATA]   data4
    ,input  wire [17:0]         exu_op
    ,input  wire [9:0]          alu_ctrl
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

    // 对于普通指令和访存指令（基址计算），输出 ALU 的计算结果
    // 对于 JAL/JALR，输出 data3 (即 snpc)
    assign exu_res = (exu_op == 18'h9 | exu_op == 18'h1c) ? data3 : alu_res;

    assign exu_jump = (exu_op == 18'h9 | exu_op == 18'h1c) | branch_taken;
    assign exu_jump_pc = (exu_op == 18'h9) ? {alu_res[31:1], 1'b0} :
                         (exu_op == 18'h1c) ? alu_res :
                         (branch_taken) ? data3 : 32'b0;

endmodule
