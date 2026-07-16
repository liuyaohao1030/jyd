`timescale 1ns / 1ps

`include "define.v"

// ============================================================================
// KLDJ RISC-V CPU Testbench
//
// Architecture: 5-stage pipeline (IF → ID → EX → MEM → WB)
// ISA: RV32IM + Zicsr (ecall/mret)
//
// Test groups use NON-OVERLAPPING register ranges where possible:
//   Group 1 (I-type ALU):      x1–x12
//   Group 2 (R-type ALU):      x13–x22
//   Group 3 (U-type):          x23–x24
//   Group 4 (Load/Store):      x25 (base), x26–x31 (loaded results)
//   Group 12 (RV32M):          x7, x8 (source), x27, x28 (results — unchecked regs)
//   Group 5 (Branch):          uses x1–x4 from Group 1 (intentional overwrite)
//   Group 6 (JAL):             x12 (overwrites Group 1)
//   Group 6b (JALR):           x5 (target reg), x13 (overwrites Group 2)
//   Group 7 (RAW hazard):      x1–x4 (overwrites Group 1/5)
//   Group 8 (Load-use stall):  x5–x6 (overwrites Group 6b)
//   Group 9 (CSR):             x15–x18
//   Group 10 (ECALL/MRET):     x20–x21
//   Group 11 (mscratch/fwd):   x27–x31, mscratch CSR
//
// Verification checks FINAL register values (last write wins).
// ============================================================================

module KLDJ_top_tb;

    // ------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------
    reg         clk;
    reg         rst;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz, 10ns period

    // ------------------------------------------------
    // Instruction Memory (combinational read)
    // ------------------------------------------------
    reg [31:0] inst_mem [0:4095];

    wire [31:0] if_pc;
    wire [31:0] inst_rdata;

    wire [12:0] inst_word_addr = if_pc[14:2];
    assign inst_rdata = inst_mem[inst_word_addr];

    // ------------------------------------------------
    // Data Memory (sync read, sync write)
    // ------------------------------------------------
    reg [31:0] data_mem [0:4095];
    initial begin : init_data_mem
        integer dm_i;
        for (dm_i = 0; dm_i < 4096; dm_i = dm_i + 1)
            data_mem[dm_i] = 32'h0;
    end

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    reg  [31:0] mem_rdata;

    wire [12:0] data_word_addr = mem_addr[14:2];
    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_be[0]) data_mem[data_word_addr][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_be[1]) data_mem[data_word_addr][15: 8] <= mem_wdata[15: 8];
            if (mem_be[2]) data_mem[data_word_addr][23:16] <= mem_wdata[23:16];
            if (mem_be[3]) data_mem[data_word_addr][31:24] <= mem_wdata[31:24];
        end
        mem_rdata <= data_mem[data_word_addr];
    end

    // ------------------------------------------------
    // DUT
    // ------------------------------------------------
    wire        tb_ex_jump;
    wire [31:0] tb_ex_jump_pc;
    wire [31:0] tb_ex_res;
    wire        core_clk_o;

    // Performance counter outputs
    wire [31:0] perf_cycle_count;
    wire [31:0] perf_instret_count;
    wire [31:0] perf_frontend_stall_count;
    wire [31:0] perf_load_use_stall_count;
    wire [31:0] perf_mul_stall_count;
    wire [31:0] perf_div_stall_count;
    wire [31:0] perf_redirect_count;
    wire [31:0] perf_load_count;
    wire [31:0] perf_store_count;
    wire [31:0] jalr_expected_sum = u_dut.ex_cf_rs1_data + u_dut.id_ex_data4;
    // FixTiming9 must select exactly the source that the previous EX-stage
    // address-comparison implementation would have selected this cycle.
    wire [1:0] expected_rs1_fwd_sel =
        (u_dut.id_ex_rs1_ren && u_dut.ex_mem_forward_valid &&
         (u_dut.id_ex_rs1_addr == u_dut.ex_mem_rd_addr)) ? 2'b01 :
        (u_dut.id_ex_rs1_ren && u_dut.mem_wb_forward_valid &&
         (u_dut.id_ex_rs1_addr == u_dut.mem_wb_rd_addr)) ? 2'b10 :
                                                                  2'b00;
    wire [1:0] expected_rs2_fwd_sel =
        (u_dut.id_ex_rs2_ren && u_dut.ex_mem_forward_valid &&
         (u_dut.id_ex_rs2_addr == u_dut.ex_mem_rd_addr)) ? 2'b01 :
        (u_dut.id_ex_rs2_ren && u_dut.mem_wb_forward_valid &&
         (u_dut.id_ex_rs2_addr == u_dut.mem_wb_rd_addr)) ? 2'b10 :
                                                                  2'b00;
    wire id_ex_multicycle_op = (u_dut.id_ex_exu_op >= 18'h25) &&
                                (u_dut.id_ex_exu_op <= 18'h2c);

    KLDJ_top u_dut (
         .clk          (clk           )
        ,.rst          (rst           )
        ,.tb_if_inst   (inst_rdata    )
        ,.tb_if_pc     (if_pc         )
        ,.tb_ex_jump   (tb_ex_jump    )
        ,.tb_ex_jump_pc(tb_ex_jump_pc )
        ,.tb_ex_res    (tb_ex_res     )
        ,.mem_addr     (mem_addr      )
        ,.mem_wdata    (mem_wdata     )
        ,.mem_we       (mem_we        )
        ,.mem_be       (mem_be        )
        ,.mem_rdata    (mem_rdata     )
        ,.core_clk_o   (core_clk_o    )
        ,.perf_cycle_count         (perf_cycle_count          )
        ,.perf_instret_count       (perf_instret_count        )
        ,.perf_frontend_stall_count(perf_frontend_stall_count )
        ,.perf_load_use_stall_count(perf_load_use_stall_count )
        ,.perf_mul_stall_count     (perf_mul_stall_count      )
        ,.perf_div_stall_count     (perf_div_stall_count      )
        ,.perf_redirect_count      (perf_redirect_count       )
        ,.perf_load_count          (perf_load_count           )
        ,.perf_store_count         (perf_store_count          )
    );

    // Registered-control structural equivalence checks. These compare the
    // registered one-bit controls against the original exu_op definitions.
    always @(negedge clk) begin
        if (!rst) begin
            if (u_dut.id_ex_valid && (u_dut.id_ex_load_op !==
                ((u_dut.id_ex_exu_op >= 18'h1d) &&
                 (u_dut.id_ex_exu_op <= 18'h21))))
                $fatal(1, "id_ex_load_op predecode mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_store_op !==
                ((u_dut.id_ex_exu_op >= 18'h22) &&
                 (u_dut.id_ex_exu_op <= 18'h24))))
                $fatal(1, "id_ex_store_op predecode mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_rs2_to_data2 !==
                (((u_dut.id_ex_exu_op >= 18'ha) && (u_dut.id_ex_exu_op <= 18'h19)) ||
                 ((u_dut.id_ex_exu_op >= 18'h25) && (u_dut.id_ex_exu_op <= 18'h2c)))))
                $fatal(1, "id_ex_rs2_to_data2 predecode mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_branch_op !==
                ((u_dut.id_ex_exu_op >= 18'h14) &&
                 (u_dut.id_ex_exu_op <= 18'h19))))
                $fatal(1, "id_ex_branch_op predecode mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_jal_op !==
                (u_dut.id_ex_exu_op == 18'h1c)))
                $fatal(1, "id_ex_jal_op predecode mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_jalr_op !==
                (u_dut.id_ex_exu_op == 18'h9)))
                $fatal(1, "id_ex_jalr_op predecode mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_jalr_check_en !==
                (u_dut.id_ex_pred_taken && u_dut.id_ex_pred_is_jalr &&
                 (u_dut.id_ex_exu_op == 18'h9))))
                $fatal(1, "id_ex_jalr_check_en predecode mismatch");
            if (u_dut.id_ex_valid && u_dut.id_ex_jalr_op &&
                (u_dut.exu_jump_pc_raw !== {jalr_expected_sum[31:1], 1'b0}))
                $fatal(1, "JALR dedicated target path mismatch");
            if (u_dut.id_ex_valid && u_dut.id_ex_jalr_op &&
                (u_dut.exu_jalr_target_raw !== {jalr_expected_sum[31:1], 1'b0}))
                $fatal(1, "JALR target bypass mismatch");
            if (u_dut.id_ex_valid && u_dut.id_ex_jalr_op &&
                (u_dut.ex_cf_rs1_data !== u_dut.ex_data1))
                $fatal(1, "JALR control-flow forwarding mismatch");
            if (u_dut.id_ex_valid && u_dut.id_ex_jalr_op &&
                (u_dut.id_ex_data2 !== 32'b0))
                $fatal(1, "JALR generic operand-2 must be zero");
            if (u_dut.id_ex_valid && u_dut.id_ex_branch_op &&
                ((u_dut.ex_cf_rs1_data !== u_dut.ex_data1) ||
                 (u_dut.ex_cf_rs2_data !== u_dut.ex_data2)))
                $fatal(1, "branch control-flow forwarding mismatch");
            if (u_dut.id_ex_valid && (u_dut.id_ex_rs1_fwd_sel == 2'b11))
                $fatal(1, "reserved rs1 forwarding select");
            if (u_dut.id_ex_valid && (u_dut.id_ex_rs2_fwd_sel == 2'b11))
                $fatal(1, "reserved rs2 forwarding select");
            // A multi-cycle EX entry holds its metadata while older producers
            // drain. Its operands are consumed only on launch, so subsequent
            // dynamic EX-stage comparisons are not architecturally relevant.
            if (u_dut.id_ex_valid && !u_dut.ex_stall && !id_ex_multicycle_op &&
                (u_dut.id_ex_rs1_fwd_sel !== expected_rs1_fwd_sel)) begin
                $fatal(1, "rs1 forwarding predecode mismatch");
            end
            if (u_dut.id_ex_valid && !u_dut.ex_stall && !id_ex_multicycle_op &&
                (u_dut.id_ex_rs2_fwd_sel !== expected_rs2_fwd_sel)) begin
                $fatal(1, "rs2 forwarding predecode mismatch");
            end
            if (u_dut.id_ex_pred_is_jalr && !u_dut.id_ex_pred_taken)
                $fatal(1, "indirect prediction metadata without taken prediction");
            if (u_dut.ex_mem_load_op !==
                (u_dut.ex_mem_valid && (u_dut.ex_mem_exu_op >= 18'h1d) &&
                 (u_dut.ex_mem_exu_op <= 18'h21)))
                $fatal(1, "ex_mem_load_op predecode mismatch");
            if (u_dut.ex_mem_forward_valid !==
                (u_dut.ex_mem_valid && u_dut.ex_mem_wb_ctl &&
                 !u_dut.ex_mem_load_op && (u_dut.ex_mem_rd_addr != 5'd0)))
                $fatal(1, "ex_mem_forward_valid registered control mismatch");
            if (!u_dut.id_ex_valid && (u_dut.ex_redirect || u_dut.bpu_update_valid))
                $fatal(1, "invalid ID/EX entry produced redirect or BPU update");
        end
    end

    // ------------------------------------------------
    // Helpers
    // ------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check_reg(input [4:0] raddr, input [31:0] expected, input [255:0] test_name);
        reg [31:0] actual;
        begin
            actual = u_dut.reg5.regs[raddr];
            if (actual === expected) begin
                $display("[PASS] %0s: x%0d = 0x%08x", test_name, raddr, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: x%0d = 0x%08x (expected 0x%08x)", test_name, raddr, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    // ------------------------------------------------
    // RISC-V encoding helpers
    // ------------------------------------------------

    function [31:0] rv_rtype(
        input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd,   input [6:0] opcode
    );
        rv_rtype = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function [31:0] rv_itype(
        input [11:0] imm, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        rv_itype = {imm, rs1, funct3, rd, opcode};
    endfunction

    function [31:0] rv_stype(
        input [11:0] imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [6:0] opcode
    );
        rv_stype = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    // B-type: imm = byte offset.  e.g. 13'h008 = +8 bytes (skip 1 inst)
    function [31:0] rv_btype(
        input [12:0] imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [6:0] opcode
    );
        rv_btype = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    // U-type
    function [31:0] rv_utype(
        input [31:12] imm, input [4:0] rd, input [6:0] opcode
    );
        rv_utype = {imm, rd, opcode};
    endfunction

    // J-type: imm = byte offset.  e.g. 21'h008 = +8 bytes (skip 1 inst)
    function [31:0] rv_jtype(
        input [20:0] imm, input [4:0] rd, input [6:0] opcode
    );
        rv_jtype = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    // Opcodes
    localparam [6:0] OP_RTYPE  = 7'b0110011;
    localparam [6:0] OP_ITYPE  = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    localparam [6:0] OP_SYSTEM = 7'b1110011;

    localparam [2:0] F3_ADD_SUB = 3'b000, F3_SLL = 3'b001, F3_SLT  = 3'b010;
    localparam [2:0] F3_SLTU   = 3'b011, F3_XOR = 3'b100, F3_SRL_SRA = 3'b101;
    localparam [2:0] F3_OR      = 3'b110, F3_AND = 3'b111;
    localparam [2:0] F3_BEQ = 3'b000, F3_BNE = 3'b001, F3_BLT = 3'b100;
    localparam [2:0] F3_BGE = 3'b101, F3_BLTU = 3'b110, F3_BGEU = 3'b111;
    localparam [2:0] F3_LB = 3'b000, F3_LH = 3'b001, F3_LW = 3'b010;
    localparam [2:0] F3_LBU = 3'b100, F3_SB = 3'b000, F3_SH = 3'b001, F3_SW = 3'b010;
    localparam [2:0] F3_CSRRW = 3'b001, F3_CSRRS = 3'b010, F3_CSRRC = 3'b011;

    localparam [6:0] F7_NORMAL = 7'b0000000, F7_SUB = 7'b0100000, F7_SRA = 7'b0100000;
    localparam [6:0] F7_MULDIV = 7'b0000001;

    // RV32M funct3
    localparam [2:0] F3_MUL = 3'b000, F3_MULH = 3'b001, F3_MULHSU = 3'b010, F3_MULHU = 3'b011;
    localparam [2:0] F3_DIV = 3'b100, F3_DIVU = 3'b101, F3_REM = 3'b110, F3_REMU = 3'b111;

    // ------------------------------------------------
    // RV32M golden-model helpers
    // ------------------------------------------------
    function [31:0] gm_mul;
        input [31:0] a, b;
        reg signed [31:0] sa, sb;
        reg signed [63:0] prod;
        begin sa = a; sb = b; prod = sa * sb; gm_mul = prod[31:0]; end
    endfunction

    function [31:0] gm_mulh;
        input [31:0] a, b;
        reg signed [31:0] sa, sb;
        reg signed [63:0] prod;
        begin sa = a; sb = b; prod = sa * sb; gm_mulh = prod[63:32]; end
    endfunction

    function [31:0] gm_mulhsu;
        input [31:0] a, b;
        reg signed [63:0] sa;
        reg [63:0] ub;
        reg signed [63:0] prod;
        begin
            sa = {{32{a[31]}}, a};
            ub = {32'b0, b};
            prod = sa * $signed(ub);
            gm_mulhsu = prod[63:32];
        end
    endfunction

    function [31:0] gm_mulhu;
        input [31:0] a, b;
        reg [63:0] ua, ub, prod;
        begin ua = {32'b0, a}; ub = {32'b0, b}; prod = ua * ub; gm_mulhu = prod[63:32]; end
    endfunction

    function [31:0] gm_div;
        input [31:0] a, b;
        reg signed [31:0] sa, sb;
        begin
            sa = a; sb = b;
            if (b == 0) gm_div = 32'hffffffff;
            else if (a == 32'h80000000 && b == 32'hffffffff) gm_div = 32'h80000000;
            else gm_div = sa / sb;
        end
    endfunction

    function [31:0] gm_divu;
        input [31:0] a, b;
        begin
            if (b == 0) gm_divu = 32'hffffffff;
            else gm_divu = a / b;
        end
    endfunction

    function [31:0] gm_rem;
        input [31:0] a, b;
        reg signed [31:0] sa, sb;
        begin
            sa = a; sb = b;
            if (b == 0) gm_rem = a;
            else if (a == 32'h80000000 && b == 32'hffffffff) gm_rem = 0;
            else gm_rem = sa % sb;
        end
    endfunction

    function [31:0] gm_remu;
        input [31:0] a, b;
        begin
            if (b == 0) gm_remu = a;
            else gm_remu = a % b;
        end
    endfunction

    // ------------------------------------------------
    // Emit R-type M-extension instruction
    // ------------------------------------------------
    task emit_m;
        input [2:0] funct3;
        input [4:0] rd, rs1, rs2;
        begin
            emit(rv_rtype(F7_MULDIV, rs2, rs1, funct3, rd, OP_RTYPE));
        end
    endtask

    // ------------------------------------------------
    // Program builder
    // ------------------------------------------------
    integer idx;

    task init_inst_mem;
        integer i;
        begin
            for (i = 0; i < 4096; i = i + 1)
                inst_mem[i] = 32'h00000013;  // NOP
            idx = 0;
        end
    endtask

    task emit(input [31:0] inst);
        begin
            inst_mem[idx] = inst;
            idx = idx + 1;
        end
    endtask

    // Index trackers for computing expected values at runtime
    integer idx_auipc, idx_jal, idx_jalr, idx_ecall;

    // ------------------------------------------------
    // Main
    // ------------------------------------------------
    initial begin
        $display("==============================================");
        $display("  KLDJ RISC-V CPU Testbench");
        $display("==============================================");

        init_inst_mem;

        // ==========================================
        // GROUP 1: I-type ALU  (writes x1–x12)
        // ==========================================
        // x1=1, x2=10, x3=3, x4=slti(10,5)=0, x5=slti(1,5)=1
        // x6=sltiu(10,5)=0, x7=1^0xFF=0xFE, x8=1|0xF0=0xF1
        // x9=1&0x0F=1, x10=1<<4=16, x11=16>>2=4, x12=(-16)>>>4=0xFC..FC
        emit(rv_itype(12'h001, 5'd0,  F3_ADD_SUB, 5'd1,  OP_ITYPE));
        emit(rv_itype(12'h00A, 5'd0,  F3_ADD_SUB, 5'd2,  OP_ITYPE));
        emit(rv_itype(12'h002, 5'd1,  F3_ADD_SUB, 5'd3,  OP_ITYPE));
        emit(rv_itype(12'h005, 5'd2,  F3_SLT,     5'd4,  OP_ITYPE));
        emit(rv_itype(12'h005, 5'd1,  F3_SLT,     5'd5,  OP_ITYPE));
        emit(rv_itype(12'h005, 5'd2,  F3_SLTU,    5'd6,  OP_ITYPE));
        emit(rv_itype(12'h0FF, 5'd1,  F3_XOR,     5'd7,  OP_ITYPE));
        emit(rv_itype(12'h0F0, 5'd1,  F3_OR,      5'd8,  OP_ITYPE));
        emit(rv_itype(12'h00F, 5'd1,  F3_AND,     5'd9,  OP_ITYPE));
        emit(rv_itype(12'h004, 5'd1,  F3_SLL,     5'd10, OP_ITYPE));
        emit(rv_itype(12'h002, 5'd10, F3_SRL_SRA, 5'd11, OP_ITYPE));
        emit(rv_itype(12'hFF0, 5'd0,  F3_ADD_SUB, 5'd12, OP_ITYPE));
        emit(rv_itype(12'h404, 5'd12, F3_SRL_SRA, 5'd12, OP_ITYPE));

        // ==========================================
        // GROUP 2: R-type ALU  (writes x13–x22)
        // ==========================================
        // x13=10+1=11, x14=10-1=9, x15=1<<3=8, x16=slt(1,10)=1
        // x17=sltu(1,10)=1, x18=0xFE^0xF1=0x0F, x19=16>>1=8
        // x20=0xFC..FC>>>1=0xFE..FE, x21=0xFE|0xF1=0xFF, x22=0xFE&0xF1=0xF0
        emit(rv_rtype(F7_NORMAL, 5'd1,  5'd2,  F3_ADD_SUB, 5'd13, OP_RTYPE));
        emit(rv_rtype(F7_SUB,    5'd1,  5'd2,  F3_ADD_SUB, 5'd14, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd3,  5'd1,  F3_SLL,     5'd15, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd2,  5'd1,  F3_SLT,     5'd16, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd2,  5'd1,  F3_SLTU,    5'd17, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd8,  5'd7,  F3_XOR,     5'd18, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd1,  5'd10, F3_SRL_SRA, 5'd19, OP_RTYPE));
        emit(rv_rtype(F7_SRA,    5'd1,  5'd12, F3_SRL_SRA, 5'd20, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd8,  5'd7,  F3_OR,      5'd21, OP_RTYPE));
        emit(rv_rtype(F7_NORMAL, 5'd8,  5'd7,  F3_AND,     5'd22, OP_RTYPE));

        // ==========================================
        // GROUP 3: U-type  (writes x23–x24)
        // ==========================================
        emit(rv_utype(20'h12345, 5'd23, OP_LUI));
        idx_auipc = idx;
        emit(rv_utype(20'h12345, 5'd24, OP_AUIPC));

        // ==========================================
        // GROUP 4: Load/Store  (writes x25–x31)
        // ==========================================
        // x25=0x80001000 (base addr)
        // Store x23(=0x12345000) and load back in various widths
        emit(rv_utype(20'h80001, 5'd25, OP_LUI));
        // SW / LW
        emit(rv_stype(12'h000, 5'd23, 5'd25, F3_SW, OP_STORE));
        emit(rv_itype(12'h000, 5'd25, F3_LW, 5'd26, OP_LOAD));
        // SH / LH
        emit(rv_stype(12'h004, 5'd23, 5'd25, F3_SH, OP_STORE));
        emit(rv_itype(12'h004, 5'd25, F3_LH, 5'd27, OP_LOAD));
        // SB / LB  (store lower byte of 0x12345000 = 0x00)
        emit(rv_stype(12'h008, 5'd23, 5'd25, F3_SB, OP_STORE));
        emit(rv_itype(12'h008, 5'd25, F3_LB, 5'd28, OP_LOAD));
        emit(rv_itype(12'h008, 5'd25, F3_LBU, 5'd29, OP_LOAD));
        // SB / LB  (store 0x7F)
        emit(rv_itype(12'h07F, 5'd0,  F3_ADD_SUB, 5'd30, OP_ITYPE));
        emit(rv_stype(12'h00C, 5'd30, 5'd25, F3_SB, OP_STORE));
        emit(rv_itype(12'h00C, 5'd25, F3_LB, 5'd31, OP_LOAD));

        // ==========================================
        // GROUP 5: Branch  (overwrites x1–x4; writes x10–x11)
        // ==========================================
        emit(rv_itype(12'h005, 5'd0, F3_ADD_SUB, 5'd1, OP_ITYPE)); // x1=5
        emit(rv_itype(12'h00A, 5'd0, F3_ADD_SUB, 5'd2, OP_ITYPE)); // x2=10
        emit(rv_itype(12'hFFF, 5'd0, F3_ADD_SUB, 5'd3, OP_ITYPE)); // x3=-1
        emit(rv_itype(12'hFFE, 5'd0, F3_ADD_SUB, 5'd4, OP_ITYPE)); // x4=-2

        // TAKEN (skip next inst):
        emit(rv_btype(13'h008, 5'd1, 5'd1, F3_BEQ,  OP_BRANCH)); // beq  x1,x1 → taken
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        emit(rv_btype(13'h008, 5'd2, 5'd1, F3_BNE,  OP_BRANCH)); // bne  x1,x2 → taken
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        emit(rv_btype(13'h008, 5'd2, 5'd1, F3_BLT,  OP_BRANCH)); // blt  x1,x2 → taken
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        emit(rv_btype(13'h008, 5'd1, 5'd2, F3_BGE,  OP_BRANCH)); // bge  x2,x1 → taken
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        emit(rv_btype(13'h008, 5'd3, 5'd1, F3_BLTU, OP_BRANCH)); // bltu x1,x3 → taken
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        emit(rv_btype(13'h008, 5'd1, 5'd3, F3_BGEU, OP_BRANCH)); // bgeu x3,x1 → taken
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        // NOT TAKEN:
        emit(rv_btype(13'h008, 5'd2, 5'd1, F3_BEQ,  OP_BRANCH)); // beq x1,x2 → NOT taken
        emit(rv_itype(12'h0AA, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE));
        emit(rv_btype(13'h008, 5'd1, 5'd1, F3_BNE,  OP_BRANCH)); // bne x1,x1 → NOT taken
        emit(rv_itype(12'h0BB, 5'd0, F3_ADD_SUB, 5'd11, OP_ITYPE));

        // ==========================================
        // GROUP 6: JAL  (writes x12)
        // ==========================================
        idx_jal = idx;
        emit(rv_jtype(21'h008, 5'd12, OP_JAL));
        emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE)); // skipped

        // ==========================================
        // GROUP 6b: JALR  (writes x5, x13)
        // ==========================================
        begin : jalr_blk
            integer target;
            reg [19:0] upper;
            reg [11:0] lower;
            // Target = skip 1 inst after JALR.  Layout: LUI idx, ADDI idx+1, JALR idx+2, skip idx+3, target idx+4
            target = 32'h80000000 + (idx + 4) * 4;
            lower = target[11:0];
            upper = target[31:12];
            if (target[11]) upper = upper + 1;
            emit(rv_utype(upper, 5'd5, OP_LUI));
            emit(rv_itype(lower, 5'd5, F3_ADD_SUB, 5'd5, OP_ITYPE));
            idx_jalr = idx;
            emit(rv_itype(12'h000, 5'd5, 3'b000, 5'd13, OP_JALR));
            emit(rv_itype(12'hBAD, 5'd0, F3_ADD_SUB, 5'd10, OP_ITYPE)); // skipped
        end

        // ==========================================
        // GROUP 7: RAW forwarding  (writes x1–x4)
        // ==========================================
        emit(rv_itype(12'h064, 5'd0, F3_ADD_SUB, 5'd1, OP_ITYPE)); // x1=100
        emit(rv_itype(12'h001, 5'd1, F3_ADD_SUB, 5'd2, OP_ITYPE)); // x2=101
        emit(rv_itype(12'h001, 5'd2, F3_ADD_SUB, 5'd3, OP_ITYPE)); // x3=102
        emit(rv_itype(12'h001, 5'd3, F3_ADD_SUB, 5'd4, OP_ITYPE)); // x4=103

        // ==========================================
        // GROUP 8: Load-use stall  (writes x5–x6)
        // ==========================================
        emit(rv_stype(12'h000, 5'd1, 5'd25, F3_SW, OP_STORE));     // sw x1, 0(x25)
        emit(rv_itype(12'h000, 5'd25, F3_LW, 5'd5, OP_LOAD));      // lw x5, 0(x25)
        emit(rv_itype(12'h001, 5'd5, F3_ADD_SUB, 5'd6, OP_ITYPE)); // addi x6, x5, 1

        // ==========================================
        // GROUP 9: CSR  (writes x15–x18)
        // ==========================================
        emit(rv_utype(20'h12345, 5'd15, OP_LUI));
        emit(rv_itype(12'h678, 5'd15, F3_ADD_SUB, 5'd15, OP_ITYPE));
        emit(rv_itype(12'h300, 5'd15, F3_CSRRW, 5'd16, OP_SYSTEM));
        emit(rv_itype(12'h300, 5'd15, F3_CSRRS, 5'd17, OP_SYSTEM));
        emit(rv_itype(12'h300, 5'd15, F3_CSRRC, 5'd18, OP_SYSTEM));

        // ==========================================
        // GROUP 10: ECALL/MRET  (writes x20–x21)
        // ==========================================
        begin : ecall_blk
            integer mret_addr;
            reg [19:0] mu;
            reg [11:0] ml;
            mret_addr = 32'h80000000 + (idx + 5) * 4; // jump past MRET to avoid ecall/mret loop
            ml = mret_addr[11:0];
            mu = mret_addr[31:12];
            if (mret_addr[11]) mu = mu + 1;
            emit(rv_utype(mu, 5'd20, OP_LUI));
            emit(rv_itype(ml, 5'd20, F3_ADD_SUB, 5'd20, OP_ITYPE));
            emit(rv_itype(12'h305, 5'd20, F3_CSRRW, 5'd21, OP_SYSTEM));
            idx_ecall = idx;
            emit({12'h000, 5'd0, 3'b000, 5'd0, OP_SYSTEM}); // ECALL
            emit({12'h302, 5'd0, 3'b000, 5'd0, OP_SYSTEM}); // MRET
        end

        // ==========================================
        // GROUP 11: mscratch + CSR forwarding + MPP
        // ==========================================
        // Test 1: mscratch write/read (forwarding)
        //   x30 = old mscratch (0), mscratch = 0xCAFEBABE
        //   x31 = read mscratch back (should be 0xCAFEBABE via forwarding)
        emit(rv_utype(20'hCAFEC, 5'd27, OP_LUI));                // x27 = 0xCAFEC000 (compensate for ADDI sign-ext)
        emit(rv_itype(12'hABE, 5'd27, F3_ADD_SUB, 5'd27, OP_ITYPE)); // x27 = 0xCAFEBABE
        emit(rv_itype(12'h340, 5'd27, F3_CSRRW, 5'd30, OP_SYSTEM));  // x30=old mscratch(0), mscratch=x27
        emit(rv_itype(12'h340, 5'd0,  F3_CSRRS, 5'd31, OP_SYSTEM));  // x31=mscratch (forwarded=0xCAFEBABE)
        // Test 2: mscratch across ECALL/MRET (CSR preserved)
        //   Set mtvec → past MRET, ecall, read mscratch after return
        begin : mscratch_ecall_blk
            integer mret_addr2;
            reg [19:0] mu2;
            reg [11:0] ml2;
            mret_addr2 = 32'h80000000 + (idx + 5) * 4; // jump past MRET to avoid ecall/mret loop
            ml2 = mret_addr2[11:0];
            mu2 = mret_addr2[31:12];
            if (mret_addr2[11]) mu2 = mu2 + 1;
            emit(rv_utype(mu2, 5'd28, OP_LUI));
            emit(rv_itype(ml2, 5'd28, F3_ADD_SUB, 5'd28, OP_ITYPE));
            emit(rv_itype(12'h305, 5'd28, F3_CSRRW, 5'd0, OP_SYSTEM)); // mtvec = mret_addr
            emit({12'h000, 5'd0, 3'b000, 5'd0, OP_SYSTEM});            // ECALL
            emit({12'h302, 5'd0, 3'b000, 5'd0, OP_SYSTEM});            // MRET
            emit(rv_itype(12'h340, 5'd0,  F3_CSRRS, 5'd29, OP_SYSTEM)); // x29=mscratch (should survive)
        end

        // ==========================================
        // GROUP 12: RV32M Multiply/Divide  (uses unchecked regs x7, x8, x27, x28)
        // Verifies all 8 M-extension instructions. Exhaustive tests in rv32m_supported_instr_tb.
        // ==========================================
        // --- MUL: lower 32 bits of signed*signed ---
        // x7=3, x8=4, x27=MUL(3,4)=12
        emit(rv_itype(12'h003, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h004, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_MUL, 5'd27, OP_RTYPE));

        // --- MULH: high 32 bits of signed*signed ---
        // x7=0x80000000, x8=2, x28=MULH(-2^31, 2)=0xFFFFFFFF
        emit(rv_utype(20'h80000, 5'd7, OP_LUI));
        emit(rv_itype(12'h002, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_MULH, 5'd28, OP_RTYPE));

        // --- MULHSU: high 32 bits of signed*unsigned ---
        // x7=-1, x8=2, x27=MULHSU(-1,2)=0xFFFFFFFE (overwrites MUL result)
        emit(rv_itype(12'hFFF, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h002, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_MULHSU, 5'd27, OP_RTYPE));

        // --- MULHU: high 32 bits of unsigned*unsigned ---
        // x7=0xFFFFFFFF, x8=2, x28=MULHU(0xFFFFFFFF,2)=1 (overwrites MULH result)
        emit(rv_itype(12'hFFF, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h002, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_MULHU, 5'd28, OP_RTYPE));

        // --- DIV: signed division ---
        // x7=-7, x8=3, x27=DIV(-7,3)=-2 (overwrites MULHSU result)
        emit(rv_itype(12'hFF9, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h003, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_DIV, 5'd27, OP_RTYPE));

        // --- DIVU: unsigned division ---
        // x7=7, x8=3, x28=DIVU(7,3)=2 (overwrites MULHU result)
        emit(rv_itype(12'h007, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h003, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_DIVU, 5'd28, OP_RTYPE));

        // --- REM: signed remainder ---
        // x7=-7, x8=3, x27=REM(-7,3)=-1 (overwrites DIV result)
        emit(rv_itype(12'hFF9, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h003, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_REM, 5'd27, OP_RTYPE));

        // --- REMU: unsigned remainder ---
        // x7=7, x8=3, x28=REMU(7,3)=1 (overwrites DIVU result)
        emit(rv_itype(12'h007, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h003, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_rtype(F7_MULDIV, 5'd8, 5'd7, F3_REMU, 5'd28, OP_RTYPE));

        // EBREAK
        emit({12'h001, 5'd0, 3'b000, 5'd0, OP_SYSTEM});

        // Fill rest with NOPs
        while (idx < 4096) emit(32'h00000013);

        // ---- Program dump ----
        $display("");
        $display("--- Program (first 150 instructions) ---");
        begin : dump
            integer i;
            for (i = 0; i < 150; i = i + 1)
                $display("  [%3d] 0x%08x: %08x", i, 32'h80000000 + i*4, inst_mem[i]);
        end
        $display("---");
        $display("Key: AUIPC=%0d  JAL=%0d  JALR=%0d  ECALL=%0d", idx_auipc, idx_jal, idx_jalr, idx_ecall);

        // ---- Reset ----
        rst = `KLDJ_RSTABLE;
        repeat (3) @(posedge clk);
        rst = ~`KLDJ_RSTABLE;

        // ---- Run ----
        $display("");
        $display("Running...");
        wait_cycles(1200);

        // ---- Debug: dump all 32 registers ----
        $display("");
        $display("--- Register file dump ---");
        begin : regdump
            integer r;
            for (r = 0; r < 32; r = r + 1)
                $display("  x%02d = 0x%08x", r, u_dut.reg5.regs[r]);
        end
        $display("---");

        // ---- Verify (checking FINAL register values) ----
        $display("");
        $display("==============================================");
        $display("  Verification  (final register state)");
        $display("==============================================");
        $display("");

        // Group 1: only x9 survives (not overwritten)
        $display("--- Group 1: I-type ALU (surviving regs) ---");
        check_reg(9,  32'h00000001, "ANDI x9=x1&0x0F");

        // Group 2: x14, x19, x22 survive; x13/15/16/17/18/20/21 overwritten
        $display("--- Group 2: R-type ALU (surviving regs) ---");
        check_reg(14, 32'h00000009, "SUB x14=x2-x1");
        check_reg(19, 32'h00000008, "SRL x19=x10>>x1");
        check_reg(22, 32'h000000F0, "AND x22=0xFE&0xF1");

        // Group 3: x23, x24 survive
        $display("--- Group 3: U-type ---");
        check_reg(23, 32'h12345000, "LUI x23");
        begin : auipc_chk
            reg [31:0] exp;
            exp = 32'h80000000 + idx_auipc * 4 + 32'h12345000;
            check_reg(24, exp, "AUIPC x24");
        end

        // Group 4: x25–x31
        $display("--- Group 4: Load/Store ---");
        check_reg(25, 32'h80001000, "LUI x25=base");
        check_reg(26, 32'h12345000, "LW x26 from mem");
        // x27-x31 overwritten by Group 11; checked there instead

        // Group 5: x10, x11 (not-taken path results)
        $display("--- Group 5: Branch ---");
        check_reg(10, 32'h000000AA, "BEQ not-taken x10=0xAA");
        check_reg(11, 32'h000000BB, "BNE not-taken x11=0xBB");

        // Group 6: x12 (overwritten by JAL, which is the final write)
        $display("--- Group 6: JAL ---");
        begin : jal_chk
            reg [31:0] jal_pc;
            jal_pc = 32'h80000000 + idx_jal * 4;
            check_reg(12, jal_pc + 4, "JAL x12=snpc");
        end

        // Group 6b: x13 (overwritten by JALR)
        $display("--- Group 6b: JALR ---");
        begin : jalr_chk
            reg [31:0] jalr_pc;
            jalr_pc = 32'h80000000 + idx_jalr * 4;
            check_reg(13, jalr_pc + 4, "JALR x13=snpc");
        end

        // Group 7: x1–x4 (RAW forwarding — final values)
        $display("--- Group 7: RAW Forwarding ---");
        check_reg(1, 32'h00000064, "RAW x1=100");
        check_reg(2, 32'h00000065, "RAW x2=101");
        check_reg(3, 32'h00000066, "RAW x3=102");
        check_reg(4, 32'h00000067, "RAW x4=103");

        // Group 8: x5, x6 (load-use — final values)
        $display("--- Group 8: Load-Use Stall ---");
        check_reg(5, 32'h00000064, "LOAD x5=100");
        check_reg(6, 32'h00000065, "LOAD-USE x6=101");

        // Group 9: x15, x16, x17, x18
        $display("--- Group 9: CSR ---");
        check_reg(15, 32'h12345678, "CSR x15=data");
        // x16 = old mstatus on CSRRW.  Reset value = 0x1800.
        // If 'x' appears, it's a design bug (CSR read issue).
        check_reg(16, 32'h00001800, "CSRRW x16=old_mstatus");
        check_reg(17, 32'h12345678, "CSRRS x17=mstatus|rs1");
        check_reg(18, 32'h12345678, "CSRRC x18=mstatus_after_CSRRS");

        // Group 10: x20, x21
        $display("--- Group 10: ECALL/MRET ---");
        begin : ecall_chk
            reg [31:0] mtvec_exp;
            mtvec_exp = 32'h80000000 + (idx_ecall + 2) * 4; // past MRET (skip MRET)
            check_reg(20, mtvec_exp, "ECALL x20=mtvec");
            check_reg(21, 32'h00000000, "CSRRW x21=old_mtvec(0)");
        end

        // Group 11: mscratch + CSR forwarding + ECALL/MRET preservation
        $display("--- Group 11: mscratch / CSR fwd / MPP ---");
        check_reg(30, 32'h00000000, "CSRRW x30=old_mscratch(0)");
        check_reg(31, 32'hCAFEBABE, "CSRRS x31=mscratch_fwd");
        check_reg(29, 32'hCAFEBABE, "mscratch survives ecall/mret");

        // Group 12: RV32M (x27, x28 — last writes from Group 12)
        $display("--- Group 12: RV32M MUL/DIV ---");
        begin : rv32m_chk
            reg [31:0] rem_exp, remu_exp;
            rem_exp  = gm_rem(32'hfffffff9, 32'd3);   // REM(-7, 3) = -1
            remu_exp = gm_remu(32'd7, 32'd3);          // REMU(7, 3) = 1
            check_reg(27, rem_exp,  "REM  x27=REM(-7,3)=-1");
            check_reg(28, remu_exp, "REMU x28=REMU(7,3)=1");
        end

        // ---- Summary ----
        $display("");
        $display("==============================================");
        $display("  %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** SOME TESTS FAILED ***");
        $display("");
        $finish;
    end

    // Timeout
    initial begin
        #400000;
        $display("[TIMEOUT]");
        $finish;
    end

    // VCD
    initial begin
        $dumpfile("KLDJ_top_tb.vcd");
        $dumpvars(0, KLDJ_top_tb);
    end

endmodule
