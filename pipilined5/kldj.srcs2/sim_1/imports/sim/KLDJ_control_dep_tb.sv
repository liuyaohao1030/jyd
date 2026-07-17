`timescale 1ns/1ps

`include "define.v"

// -----------------------------------------------------------------------------
// Direct EX/MEM forwarding into a control transfer
//
// The first two directed sequences are ALU -> BEQ through rs1 and rs2.  Without
// the interlock each BEQ observes an old zero value and takes its bad path.  The
// third is ALU -> JALR: it distinguishes the old base from the value produced
// immediately before the JALR.  All consumers must stall once and enter EX with
// FWD_MEM2 selected.
// -----------------------------------------------------------------------------
module KLDJ_control_dep_tb;

    localparam [6:0] OP_ITYPE  = 7'b0010011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [2:0] F3_ADD    = 3'b000;
    localparam [2:0] F3_BEQ    = 3'b000;
    localparam [1:0] FWD_MEM2  = 2'b10;

    reg clk;
    reg rst;
    reg [31:0] inst_mem [0:63];
    reg [31:0] mem_rdata;

    wire [31:0] if_pc;
    wire [31:0] inst_rdata = inst_mem[if_pc[7:2]];
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;

    reg [31:0] branch_pc;
    reg [31:0] branch_rs2_pc;
    reg [31:0] jalr_pc;
    integer branch_stall_count;
    integer branch_rs2_stall_count;
    integer jalr_stall_count;
    integer branch_selector_seen;
    integer branch_rs2_selector_seen;
    integer jalr_selector_seen;
    integer unexpected_stall_count;
    integer failure_count;
    integer idx;
    integer i;

    // Match the board-facing six-stage profile.  This test has no memory
    // response or canonical-return dependency, but keeps the P1 regression
    // exercised with the same feature switches as student_top.
    KLDJ_top #(
         .ENABLE_MEM2_LOAD_FWD(1'b1)
        ,.ENABLE_RAS_PRED     (1'b1)
    ) dut (
         .clk          (clk          )
        ,.rst          (rst          )
        ,.tb_if_inst   (inst_rdata   )
        ,.tb_if_pc     (if_pc        )
        ,.tb_ex_jump   (             )
        ,.tb_ex_jump_pc(             )
        ,.tb_ex_res    (             )
        ,.mem_addr     (mem_addr     )
        ,.mem_wdata    (mem_wdata    )
        ,.mem_we       (mem_we       )
        ,.mem_be       (mem_be       )
        ,.mem_rdata    (mem_rdata    )
        ,.core_clk_o   (             )
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // This test has no loads/stores, but retain the synchronous memory model
    // used by the processor regressions.
    always @(posedge clk) begin
        mem_rdata <= 32'b0;
    end

    function [31:0] rv_itype;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            rv_itype = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] rv_btype;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            rv_btype = {imm[12], imm[10:5], rs2, rs1, funct3,
                        imm[4:1], imm[11], opcode};
        end
    endfunction

    function [31:0] rv_jtype;
        input [20:0] imm;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            rv_jtype = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
        end
    endfunction

    function [31:0] rv_utype;
        input [19:0] imm;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            rv_utype = {imm, rd, opcode};
        end
    endfunction

    function [31:0] pc_for_index;
        input integer word_index;
        begin
            pc_for_index = `KLDJ_STARTPC + (word_index * 4);
        end
    endfunction

    task emit;
        input [31:0] inst;
        begin
            inst_mem[idx] = inst;
            idx = idx + 1;
        end
    endtask

    // Sample at the falling edge, after all pipeline registers have settled
    // for the current cycle and before the next active clock edge.
    always @(negedge clk) begin
        if (rst != `KLDJ_RSTABLE) begin
            if (dut.control_dep_stall) begin
                if (dut.if_id_valid && (dut.if_id_pc == branch_pc))
                    branch_stall_count = branch_stall_count + 1;
                else if (dut.if_id_valid && (dut.if_id_pc == branch_rs2_pc))
                    branch_rs2_stall_count = branch_rs2_stall_count + 1;
                else if (dut.if_id_valid && (dut.if_id_pc == jalr_pc))
                    jalr_stall_count = jalr_stall_count + 1;
                else begin
                    $display("[CONTROL_DEP_FAIL] unexpected control stall at IF/ID PC 0x%08x",
                             dut.if_id_pc);
                    unexpected_stall_count = unexpected_stall_count + 1;
                end
            end

            if (dut.id_ex_valid && (dut.id_ex_pc == branch_pc)) begin
                branch_selector_seen = branch_selector_seen + 1;
                if (dut.id_ex_rs1_fwd_sel !== FWD_MEM2) begin
                    $display("[CONTROL_DEP_FAIL] branch selector is %b, expected FWD_MEM2",
                             dut.id_ex_rs1_fwd_sel);
                    failure_count = failure_count + 1;
                end
            end

            if (dut.id_ex_valid && (dut.id_ex_pc == jalr_pc)) begin
                jalr_selector_seen = jalr_selector_seen + 1;
                if (dut.id_ex_rs1_fwd_sel !== FWD_MEM2) begin
                    $display("[CONTROL_DEP_FAIL] JALR selector is %b, expected FWD_MEM2",
                             dut.id_ex_rs1_fwd_sel);
                    failure_count = failure_count + 1;
                end
            end

            if (dut.id_ex_valid && (dut.id_ex_pc == branch_rs2_pc)) begin
                branch_rs2_selector_seen = branch_rs2_selector_seen + 1;
                if (dut.id_ex_rs2_fwd_sel !== FWD_MEM2) begin
                    $display("[CONTROL_DEP_FAIL] rs2 branch selector is %b, expected FWD_MEM2",
                             dut.id_ex_rs2_fwd_sel);
                    failure_count = failure_count + 1;
                end
            end
        end
    end

    initial begin : run_test
        rst                    = `KLDJ_RSTABLE;
        mem_rdata              = 32'b0;
        branch_stall_count     = 0;
        branch_rs2_stall_count = 0;
        jalr_stall_count       = 0;
        branch_selector_seen   = 0;
        branch_rs2_selector_seen = 0;
        jalr_selector_seen     = 0;
        unexpected_stall_count = 0;
        failure_count          = 0;

        for (i = 0; i < 64; i = i + 1)
            inst_mem[i] = 32'h00000013; // NOP

        idx = 0;
        // ALU -> BEQ (rs1).  The old x1 is zero and would take the bad path.
        emit(rv_itype(12'd1, 5'd0, F3_ADD, 5'd1, OP_ITYPE));
        branch_pc = pc_for_index(idx);
        emit(rv_btype(13'd12, 5'd0, 5'd1, F3_BEQ, OP_BRANCH));
        emit(rv_itype(12'h011, 5'd0, F3_ADD, 5'd10, OP_ITYPE)); // correct
        emit(rv_jtype(21'd8, 5'd0, OP_JAL));                     // skip bad
        emit(rv_itype(12'h022, 5'd0, F3_ADD, 5'd10, OP_ITYPE)); // bad

        // ALU -> BEQ (rs2).  The old x3 is zero and would take the bad path.
        emit(rv_itype(12'd1, 5'd0, F3_ADD, 5'd3, OP_ITYPE));
        branch_rs2_pc = pc_for_index(idx);
        emit(rv_btype(13'd12, 5'd3, 5'd0, F3_BEQ, OP_BRANCH));
        emit(rv_itype(12'h055, 5'd0, F3_ADD, 5'd12, OP_ITYPE)); // correct
        emit(rv_jtype(21'd8, 5'd0, OP_JAL));                     // skip bad
        emit(rv_itype(12'h066, 5'd0, F3_ADD, 5'd12, OP_ITYPE)); // bad

        // Set x2 to the wrong target (index 14), then produce the correct
        // target (index 18) immediately before JALR.
        emit(rv_utype(20'h80000, 5'd2, OP_LUI));
        emit(rv_itype(12'd56, 5'd2, F3_ADD, 5'd2, OP_ITYPE));
        emit(rv_itype(12'd16, 5'd2, F3_ADD, 5'd2, OP_ITYPE));
        jalr_pc = pc_for_index(idx);
        emit(rv_itype(12'd0, 5'd2, F3_ADD, 5'd0, OP_JALR));
        emit(rv_itype(12'h033, 5'd0, F3_ADD, 5'd11, OP_ITYPE)); // bad target
        emit(rv_jtype(21'd20, 5'd0, OP_JAL));                    // to terminal
        emit(32'h00000013);
        emit(32'h00000013);
        emit(rv_itype(12'h044, 5'd0, F3_ADD, 5'd11, OP_ITYPE)); // correct target
        emit(rv_jtype(21'd4, 5'd0, OP_JAL));                     // to terminal
        emit(rv_jtype(21'd0, 5'd0, OP_JAL));                     // terminal loop

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = ~`KLDJ_RSTABLE;

        repeat (100) @(posedge clk);
        #1;

        if (dut.reg5.regs[10] !== 32'h00000011) begin
            $display("[CONTROL_DEP_FAIL] branch result x10=0x%08x expected 0x00000011",
                     dut.reg5.regs[10]);
            failure_count = failure_count + 1;
        end
        if (dut.reg5.regs[11] !== 32'h00000044) begin
            $display("[CONTROL_DEP_FAIL] JALR result x11=0x%08x expected 0x00000044",
                     dut.reg5.regs[11]);
            failure_count = failure_count + 1;
        end
        if (dut.reg5.regs[12] !== 32'h00000055) begin
            $display("[CONTROL_DEP_FAIL] rs2 branch result x12=0x%08x expected 0x00000055",
                     dut.reg5.regs[12]);
            failure_count = failure_count + 1;
        end
        if (branch_stall_count != 1) begin
            $display("[CONTROL_DEP_FAIL] branch stalled %0d times, expected 1",
                     branch_stall_count);
            failure_count = failure_count + 1;
        end
        if (branch_rs2_stall_count != 1) begin
            $display("[CONTROL_DEP_FAIL] rs2 branch stalled %0d times, expected 1",
                     branch_rs2_stall_count);
            failure_count = failure_count + 1;
        end
        if (jalr_stall_count != 1) begin
            $display("[CONTROL_DEP_FAIL] JALR stalled %0d times, expected 1",
                     jalr_stall_count);
            failure_count = failure_count + 1;
        end
        if (branch_selector_seen != 1 || branch_rs2_selector_seen != 1 ||
            jalr_selector_seen != 1) begin
            $display("[CONTROL_DEP_FAIL] selector observations branch-rs1=%0d branch-rs2=%0d JALR=%0d",
                     branch_selector_seen, branch_rs2_selector_seen,
                     jalr_selector_seen);
            failure_count = failure_count + 1;
        end
        if (unexpected_stall_count != 0) begin
            $display("[CONTROL_DEP_FAIL] unexpected control stalls=%0d",
                     unexpected_stall_count);
            failure_count = failure_count + 1;
        end

        if (failure_count != 0)
            $fatal(1, "CONTROL_DEP_INTERLOCK_FAIL failures=%0d", failure_count);

        $display("CONTROL_DEP_INTERLOCK_PASS branch_rs1=%0d branch_rs2=%0d jalr=%0d",
                 branch_stall_count, branch_rs2_stall_count, jalr_stall_count);
        $finish;
    end

    initial begin : timeout_watchdog
        repeat (250) @(posedge clk);
        $fatal(1, "CONTROL_DEP_INTERLOCK_TIMEOUT pc=0x%08x", if_pc);
    end

endmodule
