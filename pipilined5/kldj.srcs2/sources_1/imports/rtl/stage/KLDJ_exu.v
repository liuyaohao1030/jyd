`include "../define.v"

module KLDJ_exu(
     input  wire                clk
    ,input  wire                rst
    ,input  wire                valid
     ,input  wire [`KLDJ_DATA]   data1
    ,input  wire [`KLDJ_DATA]   data2
    ,input  wire [`KLDJ_DATA]   data3
    ,input  wire [`KLDJ_DATA]   data4
    // Registered control-flow operand paths.  These use ID-predecoded
    // forwarding selects and intentionally bypass the generic EX mux cone.
    ,input  wire [`KLDJ_DATA]   ctrl_rs1_data
    ,input  wire [`KLDJ_DATA]   ctrl_rs2_data
    // JALR immediate bypasses the generic EX operand-2 forwarding mux.
    ,input  wire [`KLDJ_DATA]   jalr_imm
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
    ,output wire [`KLDJ_DATA]   ex_mem_addr
    ,output wire                div_stall
    ,output wire                mul_stall
);

    wire is_branch_op = (exu_op >= 18'h14) && (exu_op <= 18'h19);
    wire is_jalr_op   = (exu_op == 18'h9);
    wire controlflow_uses_dedicated_operands = is_branch_op || is_jalr_op;
    wire [`KLDJ_DATA] generic_alu_data1 = controlflow_uses_dedicated_operands ?
                                             `KLDJ_ZERO32 : data1;
    wire [`KLDJ_DATA] generic_alu_data2 = controlflow_uses_dedicated_operands ?
                                             `KLDJ_ZERO32 : data2;
    wire [`KLDJ_DATA] alu_res;
    wire [3:0] generic_cmp_res;

    KLDJ_alu u_KLDJ_alu(
         .op1    (generic_alu_data1)
        ,.op2    (generic_alu_data2)
        ,.alu_op (alu_ctrl)
        ,.alu_res(alu_res)
        ,.cmp_res(generic_cmp_res)
    );

    wire is_mul_op = (exu_op == 18'h25) ||
                     (exu_op == 18'h26) ||
                     (exu_op == 18'h27) ||
                     (exu_op == 18'h28);
    wire [1:0] mul_op = (exu_op == 18'h25) ? 2'b00 :
                        (exu_op == 18'h26) ? 2'b01 :
                        (exu_op == 18'h27) ? 2'b10 :
                        (exu_op == 18'h28) ? 2'b11 :
                        2'b00;
    wire        mul_busy;
    wire        mul_done;
    wire [31:0] mul_result;
    wire        mul_start = valid && is_mul_op && !mul_busy && !mul_done;

    mul_ip_wrapper u_mul_ip_wrapper(
         .clk    (clk)
        ,.rst    (rst)
        ,.start  (mul_start)
        ,.op     (mul_op)
        ,.rs1    (data1)
        ,.rs2    (data2)
        ,.busy   (mul_busy)
        ,.done   (mul_done)
        ,.result (mul_result)
    );

    wire is_div_op = (exu_op == 18'h29) ||
                     (exu_op == 18'h2a) ||
                     (exu_op == 18'h2b) ||
                     (exu_op == 18'h2c);
    wire [1:0] div_op = (exu_op == 18'h29) ? 2'b00 :
                        (exu_op == 18'h2a) ? 2'b01 :
                        (exu_op == 18'h2b) ? 2'b10 :
                        (exu_op == 18'h2c) ? 2'b11 :
                        2'b00;
    wire        div_busy;
    wire        div_done;
    wire [31:0] div_result;
    wire        div_start = valid && is_div_op && !div_busy && !div_done;

    div_ip_wrapper u_div_ip_wrapper(
         .clk    (clk)
        ,.rst    (rst)
        ,.start  (div_start)
        ,.op     (div_op)
        ,.rs1    (data1)
        ,.rs2    (data2)
        ,.busy   (div_busy)
        ,.done   (div_done)
        ,.result (div_result)
    );

    assign mul_stall = valid && is_mul_op && !mul_done;
    assign div_stall = valid && is_div_op && !div_done;  
    
    // Keep conditional-branch resolution off the generic forwarding and ALU
    // result cone.  The select bits for ctrl_rs*_data were captured in ID/EX.
    wire branch_unsigned = (exu_op == 18'h18) || (exu_op == 18'h19);
    wire [`KLDJ_DATA] branch_cmp_unused;
    wire branch_is_lt;
    wire branch_is_equ;
    wire branch_is_ne;
    wire branch_is_ge;

    alu_add u_branch_cmp(
         .a          (ctrl_rs1_data)
        ,.b          (ctrl_rs2_data)
        ,.is_sub     (1'b1)
        ,.is_unsigned(branch_unsigned)
        ,.out        (branch_cmp_unused)
        ,.lt         (branch_is_lt)
        ,.equ        (branch_is_equ)
        ,.ne         (branch_is_ne)
        ,.ge         (branch_is_ge)
    );

    wire branch_taken =
        (exu_op == 18'h14 && branch_is_equ) | // beq
        (exu_op == 18'h15 && branch_is_ne)  | // bne
        (exu_op == 18'h16 && branch_is_lt)  | // blt
        (exu_op == 18'h17 && branch_is_ge)  | // bge
        (exu_op == 18'h18 && branch_is_lt)  | // bltu
        (exu_op == 18'h19 && branch_is_ge)  ; // bgeu
    
    wire is_load_or_store = (exu_op >= 18'h1d) && (exu_op <= 18'h24);

    wire [`KLDJ_DATA] load_store_addr = data1 + data2;
    wire [`KLDJ_DATA] branch_target   = data3 + data4;
    wire [`KLDJ_DATA] jal_target      = data1 + data2;
    // JALR uses the registered immediate and the independently selected
    // control-flow rs1 operand, not either generic EX forwarding operand.
    wire [`KLDJ_DATA] jalr_sum        = ctrl_rs1_data + jalr_imm;
    wire [`KLDJ_DATA] jalr_target     = {jalr_sum[31:1], 1'b0};

    assign ex_mem_addr = is_load_or_store ? load_store_addr : `KLDJ_ZERO32;

    // CSR instruction detection
    wire is_csrrw  = (exu_op == `KLDJ_EXU_CSRRW);
    wire is_csrrs  = (exu_op == `KLDJ_EXU_CSRRS);
    wire is_csrrc  = (exu_op == `KLDJ_EXU_CSRRC);
    wire is_csrrwi = (exu_op == `KLDJ_EXU_CSRRWI);
    wire is_csrrsi = (exu_op == `KLDJ_EXU_CSRRSI);
    wire is_csrrci = (exu_op == `KLDJ_EXU_CSRRCI);

    // ecall/mret detection
    assign is_ecall = (exu_op == `KLDJ_EXU_ECALL);
    assign is_mret  = (exu_op == `KLDJ_EXU_MRET);

    // CSR write enable and data
    assign csr_we = csr_op;
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
    assign exu_res = is_mul_op ? mul_result : 
                     is_div_op ? div_result : 
                     (is_jalr_op | exu_op == 18'h1c) ? data3 :
                     csr_op ? csr_rdata :
                     is_load_or_store ? load_store_addr : 
                     alu_res;

    // mret also triggers a jump
    assign exu_jump = (is_jalr_op | exu_op == 18'h1c) | branch_taken | is_mret;
    assign exu_jump_pc = is_jalr_op ? jalr_target :
                         (exu_op == 18'h1c) ? alu_res :
                         (branch_taken) ? branch_target :
                         is_mret ? mret_pc :
                         32'b0;

endmodule
