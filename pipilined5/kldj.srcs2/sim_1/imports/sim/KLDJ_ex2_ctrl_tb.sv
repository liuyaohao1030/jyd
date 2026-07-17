`timescale 1ns/1ps

`include "define.v"

// -----------------------------------------------------------------------------
// EX2 control-transfer regression
//
// Branches and JALR retain the direct EX/MEM forwarding selector, but their
// redirect is produced from the registered EX2 result on the following cycle.
// The JALR sequence also puts a store immediately behind the jump: it reaches
// EX when EX2 redirects and must be squashed before it can touch memory.
// -----------------------------------------------------------------------------
module KLDJ_ex2_ctrl_tb;

    localparam [6:0] OP_ITYPE  = 7'b0010011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [2:0] F3_ADD    = 3'b000;
    localparam [2:0] F3_BEQ    = 3'b000;
    localparam [2:0] F3_SW     = 3'b010;
    localparam [1:0] FWD_EX_MEM = 2'b01;

    reg clk;
    reg rst;
    reg [31:0] inst_mem [0:63];
    reg [31:0] data_mem [0:63];
    reg [31:0] mem_rdata;

    wire [31:0] if_pc;
    wire [31:0] inst_rdata = inst_mem[if_pc[7:2]];
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;

    reg [31:0] branch_rs1_pc;
    reg [31:0] branch_rs2_pc;
    reg [31:0] jalr_pc;
    reg [31:0] jalr_target_pc;
    reg [31:0] squashed_store_pc;
    integer branch_rs1_fwd_seen;
    integer branch_rs2_fwd_seen;
    integer jalr_ex_seen;
    integer jalr_ex2_seen;
    integer squashed_store_seen;
    integer failure_count;
    integer idx;
    integer i;

    // Exercise the board-facing six-stage profile as well as the EX2 logic.
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

    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_be[0]) data_mem[mem_addr[7:2]][7:0]   <= mem_wdata[7:0];
            if (mem_be[1]) data_mem[mem_addr[7:2]][15:8]  <= mem_wdata[15:8];
            if (mem_be[2]) data_mem[mem_addr[7:2]][23:16] <= mem_wdata[23:16];
            if (mem_be[3]) data_mem[mem_addr[7:2]][31:24] <= mem_wdata[31:24];
        end
        mem_rdata <= data_mem[mem_addr[7:2]];
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

    function [31:0] rv_stype;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            rv_stype = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
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

    // Observe after pipeline state has settled for each cycle.  Both branch
    // source paths and JALR must use the zero-bubble EX/MEM selector again.
    always @(negedge clk) begin
        if (rst != `KLDJ_RSTABLE) begin
            if (dut.id_ex_valid && (dut.id_ex_pc == branch_rs1_pc)) begin
                branch_rs1_fwd_seen = branch_rs1_fwd_seen + 1;
                if (dut.id_ex_rs1_fwd_sel !== FWD_EX_MEM) begin
                    $display("[EX2_CTRL_FAIL] branch rs1 selector=%b, expected FWD_EX_MEM",
                             dut.id_ex_rs1_fwd_sel);
                    failure_count = failure_count + 1;
                end
            end

            if (dut.id_ex_valid && (dut.id_ex_pc == branch_rs2_pc)) begin
                branch_rs2_fwd_seen = branch_rs2_fwd_seen + 1;
                if (dut.id_ex_rs2_fwd_sel !== FWD_EX_MEM) begin
                    $display("[EX2_CTRL_FAIL] branch rs2 selector=%b, expected FWD_EX_MEM",
                             dut.id_ex_rs2_fwd_sel);
                    failure_count = failure_count + 1;
                end
            end

            if (dut.id_ex_valid && (dut.id_ex_pc == jalr_pc)) begin
                jalr_ex_seen = jalr_ex_seen + 1;
                if (dut.id_ex_rs1_fwd_sel !== FWD_EX_MEM) begin
                    $display("[EX2_CTRL_FAIL] JALR selector=%b, expected FWD_EX_MEM",
                             dut.id_ex_rs1_fwd_sel);
                    failure_count = failure_count + 1;
                end
                if (dut.ex_redirect) begin
                    $display("[EX2_CTRL_FAIL] JALR redirected before reaching EX2");
                    failure_count = failure_count + 1;
                end
            end

            if (dut.ex2_valid && (dut.ex2_pc == jalr_pc)) begin
                jalr_ex2_seen = jalr_ex2_seen + 1;
                if (!dut.ex_redirect) begin
                    $display("[EX2_CTRL_FAIL] JALR did not redirect from EX2");
                    failure_count = failure_count + 1;
                end
                if (dut.ex_correct_pc !== jalr_target_pc) begin
                    $display("[EX2_CTRL_FAIL] JALR redirect target=0x%08x expected 0x%08x",
                             dut.ex_correct_pc, jalr_target_pc);
                    failure_count = failure_count + 1;
                end
            end

            if (dut.id_ex_valid && (dut.id_ex_pc == squashed_store_pc) &&
                dut.ex_redirect) begin
                squashed_store_seen = squashed_store_seen + 1;
                if (mem_we !== 1'b0) begin
                    $display("[EX2_CTRL_FAIL] wrong-path store asserted mem_we");
                    failure_count = failure_count + 1;
                end
            end

            if (mem_we && (mem_addr == 32'd0)) begin
                $display("[EX2_CTRL_FAIL] a wrong-path store reached address zero: data=0x%08x",
                         mem_wdata);
                failure_count = failure_count + 1;
            end
        end
    end

    initial begin : run_test
        rst                   = `KLDJ_RSTABLE;
        mem_rdata             = 32'd0;
        branch_rs1_fwd_seen   = 0;
        branch_rs2_fwd_seen   = 0;
        jalr_ex_seen          = 0;
        jalr_ex2_seen         = 0;
        squashed_store_seen   = 0;
        failure_count         = 0;

        for (i = 0; i < 64; i = i + 1) begin
            inst_mem[i] = 32'h00000013; // NOP
            data_mem[i] = 32'd0;
        end

        idx = 0;
        // ALU -> BEQ through rs1.  A stale x1=0 would take the bad path.
        emit(rv_itype(12'd1, 5'd0, F3_ADD, 5'd1, OP_ITYPE));
        branch_rs1_pc = pc_for_index(idx);
        emit(rv_btype(13'd12, 5'd0, 5'd1, F3_BEQ, OP_BRANCH));
        emit(rv_itype(12'h011, 5'd0, F3_ADD, 5'd10, OP_ITYPE)); // correct
        emit(rv_jtype(21'd8, 5'd0, OP_JAL));                     // skip bad
        emit(rv_itype(12'h022, 5'd0, F3_ADD, 5'd10, OP_ITYPE)); // bad

        // ALU -> BEQ through rs2.  A stale x3=0 would take the bad path.
        emit(rv_itype(12'd1, 5'd0, F3_ADD, 5'd3, OP_ITYPE));
        branch_rs2_pc = pc_for_index(idx);
        emit(rv_btype(13'd12, 5'd3, 5'd0, F3_BEQ, OP_BRANCH));
        emit(rv_itype(12'h055, 5'd0, F3_ADD, 5'd12, OP_ITYPE)); // correct
        emit(rv_jtype(21'd8, 5'd0, OP_JAL));                     // skip bad
        emit(rv_itype(12'h066, 5'd0, F3_ADD, 5'd12, OP_ITYPE)); // bad

        // Produce a target in x2 immediately before JALR.  The immediate
        // wrong-path SW becomes the younger EX instruction at EX2 redirect.
        emit(rv_utype(20'h80000, 5'd2, OP_LUI));
        emit(rv_itype(12'h06a, 5'd0, F3_ADD, 5'd6, OP_ITYPE));
        emit(rv_itype(12'd80, 5'd2, F3_ADD, 5'd2, OP_ITYPE));
        jalr_pc = pc_for_index(idx);
        emit(rv_itype(12'd0, 5'd2, F3_ADD, 5'd0, OP_JALR));
        squashed_store_pc = pc_for_index(idx);
        emit(rv_stype(12'd0, 5'd6, 5'd0, F3_SW, OP_STORE));
        emit(rv_itype(12'h033, 5'd0, F3_ADD, 5'd11, OP_ITYPE)); // wrong path
        emit(rv_itype(12'h077, 5'd0, F3_ADD, 5'd11, OP_ITYPE)); // wrong path
        while (idx < 20)
            emit(32'h00000013);

        jalr_target_pc = pc_for_index(idx);
        emit(rv_itype(12'h044, 5'd0, F3_ADD, 5'd11, OP_ITYPE)); // target
        emit(rv_jtype(21'd0, 5'd0, OP_JAL));                     // terminal loop

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = ~`KLDJ_RSTABLE;

        repeat (140) @(posedge clk);
        #1;

        if (dut.reg5.regs[10] !== 32'h00000011) begin
            $display("[EX2_CTRL_FAIL] branch rs1 result x10=0x%08x expected 0x00000011",
                     dut.reg5.regs[10]);
            failure_count = failure_count + 1;
        end
        if (dut.reg5.regs[12] !== 32'h00000055) begin
            $display("[EX2_CTRL_FAIL] branch rs2 result x12=0x%08x expected 0x00000055",
                     dut.reg5.regs[12]);
            failure_count = failure_count + 1;
        end
        if (dut.reg5.regs[11] !== 32'h00000044) begin
            $display("[EX2_CTRL_FAIL] JALR target result x11=0x%08x expected 0x00000044",
                     dut.reg5.regs[11]);
            failure_count = failure_count + 1;
        end
        if (data_mem[0] !== 32'd0) begin
            $display("[EX2_CTRL_FAIL] wrong-path store changed memory[0] to 0x%08x",
                     data_mem[0]);
            failure_count = failure_count + 1;
        end
        if (branch_rs1_fwd_seen != 1 || branch_rs2_fwd_seen != 1 ||
            jalr_ex_seen != 1 || jalr_ex2_seen != 1 ||
            squashed_store_seen != 1) begin
            $display("[EX2_CTRL_FAIL] observations branch-rs1=%0d branch-rs2=%0d jalr-ex=%0d jalr-ex2=%0d squashed-store=%0d",
                     branch_rs1_fwd_seen, branch_rs2_fwd_seen, jalr_ex_seen,
                     jalr_ex2_seen, squashed_store_seen);
            failure_count = failure_count + 1;
        end

        if (failure_count != 0)
            $fatal(1, "EX2_CTRL_PIPELINE_FAIL failures=%0d", failure_count);

        $display("EX2_CTRL_PIPELINE_PASS branch-rs1=%0d branch-rs2=%0d jalr-ex2=%0d squashed-store=%0d",
                 branch_rs1_fwd_seen, branch_rs2_fwd_seen, jalr_ex2_seen,
                 squashed_store_seen);
        $finish;
    end

    initial begin : timeout_watchdog
        repeat (300) @(posedge clk);
        $fatal(1, "EX2_CTRL_PIPELINE_TIMEOUT pc=0x%08x", if_pc);
    end

endmodule
