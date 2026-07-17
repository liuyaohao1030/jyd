`timescale 1ns / 1ps

`include "define.v"

// -----------------------------------------------------------------------------
// Six-stage load-dependency regression
//
// This bench intentionally uses a synchronous data RAM.  It is therefore a
// correctness and cycle-contract guard for the forced MEM1 -> MEM2
// formatted-load forwarding path, not a behavioural-array shortcut.
// -----------------------------------------------------------------------------
module KLDJ_load_dep_tb;

    localparam [31:0] DATA_BASE = 32'h8000_1000;
    localparam [31:0] DONE_ADDR = DATA_BASE + 32'h0000_0044;

    localparam [6:0] OP_RTYPE  = 7'b0110011;
    localparam [6:0] OP_ITYPE  = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;

    localparam [2:0] F3_ADD_SUB = 3'b000;
    localparam [2:0] F3_BEQ     = 3'b000;
    localparam [2:0] F3_LB      = 3'b000;
    localparam [2:0] F3_LH      = 3'b001;
    localparam [2:0] F3_LW      = 3'b010;
    localparam [2:0] F3_LBU     = 3'b100;
    localparam [2:0] F3_LHU     = 3'b101;
    localparam [2:0] F3_SW      = 3'b010;

    localparam integer EXPECT_LOAD_USE_STALLS = 9;
    localparam [1:0] EXPECT_LOAD_FWD_SEL = 2'b10; // FWD_MEM2

    reg clk;
    reg rst;
    reg [31:0] inst_mem [0:255];
    reg [31:0] data_mem [0:255];
    reg [31:0] mem_rdata;

    wire [31:0] if_pc;
    wire [31:0] inst_rdata;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire        tb_ex_jump;
    wire [31:0] tb_ex_jump_pc;
    wire [31:0] tb_ex_res;

    reg done;
    integer cycle_count;
    integer load_use_stall_count;
    integer id_ex_load_use_count;
    integer ex_mem_load_use_count;
    integer consumer_seen_count;
    integer failure_count;

    reg [31:0] pc_lw_alu_consumer;
    reg [31:0] pc_store_data_consumer;
    reg [31:0] pc_store_addr_consumer;
    reg [31:0] pc_branch_consumer;
    reg [31:0] pc_jalr_consumer;
    reg [31:0] pc_independent_consumer;
    reg [31:0] pc_lb_consumer;
    reg [31:0] pc_lbu_consumer;
    reg [31:0] pc_lh_consumer;
    reg [31:0] pc_lhu_consumer;

    integer idx;
    integer jalr_wrong_jump_idx;
    integer jalr_target_idx;
    integer jalr_after_idx;
    integer i;

    assign inst_rdata = inst_mem[if_pc[9:2]];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    KLDJ_top u_dut (
         .clk          (clk          )
        ,.rst          (rst          )
        ,.tb_if_inst   (inst_rdata   )
        ,.tb_if_pc     (if_pc        )
        ,.tb_ex_jump   (tb_ex_jump   )
        ,.tb_ex_jump_pc(tb_ex_jump_pc)
        ,.tb_ex_res    (tb_ex_res    )
        ,.mem_addr     (mem_addr     )
        ,.mem_wdata    (mem_wdata    )
        ,.mem_we       (mem_we       )
        ,.mem_be       (mem_be       )
        ,.mem_rdata    (mem_rdata    )
        ,.core_clk_o   (             )
        ,.perf_cycle_count          (             )
        ,.perf_instret_count        (             )
        ,.perf_frontend_stall_count (             )
        ,.perf_load_use_stall_count (             )
        ,.perf_mul_stall_count      (             )
        ,.perf_div_stall_count      (             )
        ,.perf_redirect_count       (             )
        ,.perf_load_count           (             )
        ,.perf_store_count          (             )
    );

    // Same class of synchronous read used by the board-facing regression.
    // Stores update byte lanes on the edge and reads return the previous
    // addressed word through mem_rdata for the following cycle.
    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_be[0]) data_mem[mem_addr[9:2]][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_be[1]) data_mem[mem_addr[9:2]][15: 8] <= mem_wdata[15: 8];
            if (mem_be[2]) data_mem[mem_addr[9:2]][23:16] <= mem_wdata[23:16];
            if (mem_be[3]) data_mem[mem_addr[9:2]][31:24] <= mem_wdata[31:24];
        end
        mem_rdata <= data_mem[mem_addr[9:2]];
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

    function [31:0] rv_rtype;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            rv_rtype = {funct7, rs2, rs1, funct3, rd, opcode};
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

    function [31:0] pc_for_index;
        input integer word_index;
        begin
            pc_for_index = `KLDJ_STARTPC + (word_index * 4);
        end
    endfunction

    function is_rs2_load_consumer;
        input [31:0] pc;
        begin
            is_rs2_load_consumer = (pc == pc_store_data_consumer);
        end
    endfunction

    function is_load_consumer;
        input [31:0] pc;
        begin
            is_load_consumer = (pc == pc_lw_alu_consumer) ||
                               (pc == pc_store_data_consumer) ||
                               (pc == pc_store_addr_consumer) ||
                               (pc == pc_branch_consumer) ||
                               (pc == pc_jalr_consumer) ||
                               (pc == pc_independent_consumer) ||
                               (pc == pc_lb_consumer) ||
                               (pc == pc_lbu_consumer) ||
                               (pc == pc_lh_consumer) ||
                               (pc == pc_lhu_consumer);
        end
    endfunction

    task emit;
        input [31:0] inst;
        begin
            inst_mem[idx] = inst;
            idx = idx + 1;
        end
    endtask

    task check_word;
        input integer word_index;
        input [31:0] expected;
        input [8*48-1:0] name;
        reg [31:0] actual;
        begin
            actual = data_mem[word_index];
            if (actual !== expected) begin
                $display("[LOAD_DEP_FAIL] %0s: got 0x%08x expected 0x%08x",
                         name, actual, expected);
                failure_count = failure_count + 1;
            end else begin
                $display("[LOAD_DEP_PASS] %0s: 0x%08x", name, actual);
            end
        end
    endtask

    // Count both the architectural stall signal and its two raw causes.  The
    // latter stays observable even when the optimized configuration stops
    // blocking on the EX/MEM case.
    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            cycle_count          <= 0;
            load_use_stall_count <= 0;
            id_ex_load_use_count <= 0;
            ex_mem_load_use_count <= 0;
            done                 <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            load_use_stall_count <= load_use_stall_count + u_dut.load_use_stall;
            id_ex_load_use_count <= id_ex_load_use_count +
                                    u_dut.u_ex_forward.id_ex_load_use;
            ex_mem_load_use_count <= ex_mem_load_use_count +
                                     u_dut.u_ex_forward.ex_mem_load_use;
            if (mem_we && (mem_addr == DONE_ADDR) && (mem_wdata == 32'd1) &&
                (mem_be == 4'b1111))
                done <= 1'b1;
        end
    end

    // The consumer's forwarding selector is registered in ID/EX.  This makes
    // the expected one-bubble (FWD_MEM2) versus two-bubble (FWD_MEM_WB)
    // contract explicit, in addition to checking final architectural data.
    always @(negedge clk) begin
        if ((rst != `KLDJ_RSTABLE) && u_dut.id_ex_valid &&
            is_load_consumer(u_dut.id_ex_pc)) begin
            consumer_seen_count = consumer_seen_count + 1;
            if (is_rs2_load_consumer(u_dut.id_ex_pc)) begin
                if (u_dut.id_ex_rs2_fwd_sel !== EXPECT_LOAD_FWD_SEL) begin
                    $display("[LOAD_DEP_FAIL] rs2 selector at PC 0x%08x: got %b expected %b",
                             u_dut.id_ex_pc, u_dut.id_ex_rs2_fwd_sel,
                             EXPECT_LOAD_FWD_SEL);
                    failure_count = failure_count + 1;
                end
            end else if (u_dut.id_ex_rs1_fwd_sel !== EXPECT_LOAD_FWD_SEL) begin
                $display("[LOAD_DEP_FAIL] rs1 selector at PC 0x%08x: got %b expected %b",
                         u_dut.id_ex_pc, u_dut.id_ex_rs1_fwd_sel,
                         EXPECT_LOAD_FWD_SEL);
                failure_count = failure_count + 1;
            end
        end
    end

    initial begin : build_and_check
        rst = `KLDJ_RSTABLE;
        done = 1'b0;
        failure_count = 0;
        consumer_seen_count = 0;

        for (i = 0; i < 256; i = i + 1) begin
            inst_mem[i] = 32'h0000_0013; // NOP
            data_mem[i] = 32'd0;
        end
        mem_rdata = 32'd0;

        // Sources.  The byte layout of word 0 is [80 ff 7f 01].
        data_mem[0] = 32'h80ff_7f01;
        data_mem[1] = 32'd1;             // branch true
        data_mem[2] = DATA_BASE + 32'h48; // store-address target

        idx = 0;
        // x1 = DATA_BASE
        emit({20'h80001, 5'd1, OP_LUI});

        // lw -> ALU
        emit(rv_itype(12'h000, 5'd1, F3_LW, 5'd2, OP_LOAD));
        pc_lw_alu_consumer = pc_for_index(idx);
        emit(rv_itype(12'h007, 5'd2, F3_ADD_SUB, 5'd3, OP_ITYPE));
        emit(rv_stype(12'h020, 5'd3, 5'd1, F3_SW, OP_STORE));

        // lw -> store data
        emit(rv_itype(12'h000, 5'd1, F3_LW, 5'd2, OP_LOAD));
        pc_store_data_consumer = pc_for_index(idx);
        emit(rv_stype(12'h024, 5'd2, 5'd1, F3_SW, OP_STORE));

        // lw -> store address
        emit(rv_itype(12'h066, 5'd0, F3_ADD_SUB, 5'd3, OP_ITYPE));
        emit(rv_itype(12'h008, 5'd1, F3_LW, 5'd2, OP_LOAD));
        pc_store_addr_consumer = pc_for_index(idx);
        emit(rv_stype(12'h000, 5'd3, 5'd2, F3_SW, OP_STORE));

        // lw -> branch
        emit(rv_itype(12'h001, 5'd0, F3_ADD_SUB, 5'd7, OP_ITYPE));
        emit(rv_itype(12'h000, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_itype(12'h004, 5'd1, F3_LW, 5'd2, OP_LOAD));
        pc_branch_consumer = pc_for_index(idx);
        emit(rv_btype(13'h008, 5'd7, 5'd2, F3_BEQ, OP_BRANCH));
        emit(rv_itype(12'h001, 5'd0, F3_ADD_SUB, 5'd8, OP_ITYPE));
        emit(rv_stype(12'h028, 5'd8, 5'd1, F3_SW, OP_STORE));

        // lw -> JALR.  data_mem[3] is patched with jalr_target_idx below.
        emit(rv_itype(12'h00c, 5'd1, F3_LW, 5'd2, OP_LOAD));
        pc_jalr_consumer = pc_for_index(idx);
        emit(rv_itype(12'h000, 5'd2, F3_ADD_SUB, 5'd0, OP_JALR));
        emit(rv_itype(12'h001, 5'd0, F3_ADD_SUB, 5'd9, OP_ITYPE));
        jalr_wrong_jump_idx = idx;
        emit(32'h0000_0013); // patched after the correct-path label is known
        jalr_target_idx = idx;
        emit(rv_itype(12'h000, 5'd0, F3_ADD_SUB, 5'd9, OP_ITYPE));
        jalr_after_idx = idx;
        emit(rv_stype(12'h02c, 5'd9, 5'd1, F3_SW, OP_STORE));

        // lw; independent instruction; use
        emit(rv_itype(12'h000, 5'd1, F3_LW, 5'd2, OP_LOAD));
        emit(rv_itype(12'h007, 5'd0, F3_ADD_SUB, 5'd4, OP_ITYPE));
        pc_independent_consumer = pc_for_index(idx);
        emit(rv_rtype(7'b0000000, 5'd4, 5'd2, F3_ADD_SUB, 5'd3, OP_RTYPE));
        emit(rv_stype(12'h030, 5'd3, 5'd1, F3_SW, OP_STORE));

        // Signed/unsigned byte and halfword load forwarding.
        emit(rv_itype(12'h003, 5'd1, F3_LB, 5'd2, OP_LOAD));
        pc_lb_consumer = pc_for_index(idx);
        emit(rv_itype(12'h001, 5'd2, F3_ADD_SUB, 5'd3, OP_ITYPE));
        emit(rv_stype(12'h034, 5'd3, 5'd1, F3_SW, OP_STORE));

        emit(rv_itype(12'h002, 5'd1, F3_LBU, 5'd2, OP_LOAD));
        pc_lbu_consumer = pc_for_index(idx);
        emit(rv_itype(12'h001, 5'd2, F3_ADD_SUB, 5'd3, OP_ITYPE));
        emit(rv_stype(12'h038, 5'd3, 5'd1, F3_SW, OP_STORE));

        emit(rv_itype(12'h002, 5'd1, F3_LH, 5'd2, OP_LOAD));
        pc_lh_consumer = pc_for_index(idx);
        emit(rv_itype(12'h001, 5'd2, F3_ADD_SUB, 5'd3, OP_ITYPE));
        emit(rv_stype(12'h03c, 5'd3, 5'd1, F3_SW, OP_STORE));

        emit(rv_itype(12'h002, 5'd1, F3_LHU, 5'd2, OP_LOAD));
        pc_lhu_consumer = pc_for_index(idx);
        emit(rv_itype(12'h001, 5'd2, F3_ADD_SUB, 5'd3, OP_ITYPE));
        emit(rv_stype(12'h040, 5'd3, 5'd1, F3_SW, OP_STORE));

        // Completion store followed by a stable self-loop.
        emit(rv_itype(12'h001, 5'd0, F3_ADD_SUB, 5'd31, OP_ITYPE));
        emit(rv_stype(12'h044, 5'd31, 5'd1, F3_SW, OP_STORE));
        emit(rv_jtype(21'd0, 5'd0, OP_JAL));

        inst_mem[jalr_wrong_jump_idx] =
            rv_jtype((jalr_after_idx - jalr_wrong_jump_idx) * 4, 5'd0, OP_JAL);
        data_mem[3] = pc_for_index(jalr_target_idx);

        $display("[LOAD_DEP] running MEM2 formatted-load forwarding contract");
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = ~`KLDJ_RSTABLE;

        wait (done == 1'b1);
        #1;
        check_word(8,  32'h80ff_7f08, "lw-to-alu");
        check_word(9,  32'h80ff_7f01, "lw-to-store-data");
        check_word(18, 32'h0000_0066, "lw-to-store-address");
        check_word(10, 32'h0000_0000, "lw-to-branch");
        check_word(11, 32'h0000_0000, "lw-to-jalr");
        check_word(12, 32'h80ff_7f08, "one-independent-then-use");
        check_word(13, 32'hffff_ff81, "lb-signed");
        check_word(14, 32'h0000_0100, "lbu");
        check_word(15, 32'hffff_8100, "lh-signed");
        check_word(16, 32'h0000_8100, "lhu");

        if (consumer_seen_count != 10) begin
            $display("[LOAD_DEP_FAIL] observed %0d load consumers, expected 10",
                     consumer_seen_count);
            failure_count = failure_count + 1;
        end
        if (id_ex_load_use_count != 9) begin
            $display("[LOAD_DEP_FAIL] ID/EX hazards=%0d, expected 9",
                     id_ex_load_use_count);
            failure_count = failure_count + 1;
        end
        if (ex_mem_load_use_count != 10) begin
            $display("[LOAD_DEP_FAIL] raw EX/MEM hazards=%0d, expected 10",
                     ex_mem_load_use_count);
            failure_count = failure_count + 1;
        end
        if (load_use_stall_count != EXPECT_LOAD_USE_STALLS) begin
            $display("[LOAD_DEP_FAIL] load-use stalls=%0d, expected %0d",
                     load_use_stall_count, EXPECT_LOAD_USE_STALLS);
            failure_count = failure_count + 1;
        end

        if (failure_count != 0)
            $fatal(1, "LOAD_DEP_REGRESSION_FAIL failures=%0d cycles=%0d",
                   failure_count, cycle_count);

        $display("LOAD_DEP_REGRESSION_PASS cycles=%0d load_use=%0d id_ex=%0d ex_mem_raw=%0d",
                 cycle_count, load_use_stall_count, id_ex_load_use_count,
                 ex_mem_load_use_count);
        $finish;
    end

    initial begin : timeout_watchdog
        wait (rst != `KLDJ_RSTABLE);
        repeat (1000) @(posedge clk);
        if (!done)
            $fatal(1, "LOAD_DEP_REGRESSION_TIMEOUT last_pc=0x%08x",
                   u_dut.wb_commit_pc);
    end

endmodule
