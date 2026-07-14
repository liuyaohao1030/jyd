`timescale 1ns/1ps
`include "define.v"

// Directed integration test for the MEM-response pipeline stage.
//
// The test uses the real perip_bridge, dram_driver and DRAM_TDP behavioral
// model so that response alignment and byte-level store forwarding are tested
// together with the CPU hazard/forwarding logic.
module mem_response_pipeline_tb;

    localparam [31:0] NOP      = 32'h0000_0013;
    localparam [31:0] START_PC = `KLDJ_STARTPC;
    localparam [31:0] DRAM_BASE = 32'h8010_0000;

    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_IMM    = 7'b0010011;
    localparam [6:0] OP_REG    = 7'b0110011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;

    reg clk;
    reg cnt_clk;
    reg rst;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial cnt_clk = 1'b0;
    always #10 cnt_clk = ~cnt_clk;

    reg [31:0] inst_mem [0:255];
    wire [31:0] if_pc;
    wire [31:0] inst_rdata;
    wire [7:0] inst_index = if_pc[9:2];

    assign inst_rdata = (^if_pc === 1'bx) ? NOP : inst_mem[inst_index];

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire [31:0] mem_rdata;

    wire [39:0] virtual_seg;
    wire [31:0] virtual_led;

    wire [31:0] perf_cycle_count;
    wire [31:0] perf_instret_count;
    wire [31:0] perf_frontend_stall_count;
    wire [31:0] perf_load_use_stall_count;
    wire [31:0] perf_mul_stall_count;
    wire [31:0] perf_div_stall_count;
    wire [31:0] perf_redirect_count;
    wire [31:0] perf_load_count;
    wire [31:0] perf_store_count;

    KLDJ_top dut (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.tb_if_inst                (inst_rdata)
        ,.tb_if_pc                  (if_pc)
        ,.tb_ex_jump                ()
        ,.tb_ex_jump_pc             ()
        ,.tb_ex_res                 ()
        ,.mem_addr                  (mem_addr)
        ,.mem_wdata                 (mem_wdata)
        ,.mem_we                    (mem_we)
        ,.mem_be                    (mem_be)
        ,.mem_rdata                 (mem_rdata)
        ,.core_clk_o                ()
        ,.perf_cycle_count          (perf_cycle_count)
        ,.perf_instret_count        (perf_instret_count)
        ,.perf_frontend_stall_count (perf_frontend_stall_count)
        ,.perf_load_use_stall_count (perf_load_use_stall_count)
        ,.perf_mul_stall_count      (perf_mul_stall_count)
        ,.perf_div_stall_count      (perf_div_stall_count)
        ,.perf_redirect_count       (perf_redirect_count)
        ,.perf_load_count           (perf_load_count)
        ,.perf_store_count          (perf_store_count)
    );

    perip_bridge bridge (
         .clk                (clk)
        ,.cnt_clk            (cnt_clk)
        ,.rst                (rst)
        ,.perip_addr         (mem_addr)
        ,.perip_wdata        (mem_wdata)
        ,.perip_wen          (mem_we)
        ,.perip_be           (mem_be)
        ,.perip_rdata        (mem_rdata)
        ,.virtual_sw_input   (64'd0)
        ,.virtual_key_input  (8'd0)
        ,.virtual_seg_output (virtual_seg)
        ,.virtual_led_output (virtual_led)
    );

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

    function [31:0] rv_utype;
        input [19:0] imm;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            rv_utype = {imm, rd, opcode};
        end
    endfunction

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = NOP;

        // x1 = 0x8010_0000, the address range decoded by perip_bridge as DRAM.
        inst_mem[ 0] = rv_utype(20'h80100, 5'd1, OP_LUI);

        // Direct load-use dependency.
        inst_mem[ 1] = rv_itype(12'd4, 5'd1, 3'b010, 5'd5, OP_LOAD);
        inst_mem[ 2] = rv_itype(12'd1, 5'd5, 3'b000, 5'd6, OP_IMM);

        // Back-to-back loads followed by a two-source consumer.
        inst_mem[ 3] = rv_itype(12'd8,  5'd1, 3'b010, 5'd7, OP_LOAD);
        inst_mem[ 4] = rv_itype(12'd12, 5'd1, 3'b010, 5'd8, OP_LOAD);
        inst_mem[ 5] = rv_rtype(7'd0, 5'd8, 5'd7, 3'b000, 5'd9, OP_REG);

        // Partial-byte store forwarding: 0x11223344 -> 0x1122aa44.
        inst_mem[ 6] = rv_itype(12'd170, 5'd0, 3'b000, 5'd10, OP_IMM);
        inst_mem[ 7] = rv_stype(12'd17, 5'd10, 5'd1, 3'b000, OP_STORE);
        inst_mem[ 8] = rv_itype(12'd16, 5'd1, 3'b010, 5'd11, OP_LOAD);
        inst_mem[ 9] = rv_itype(12'd17, 5'd1, 3'b100, 5'd12, OP_LOAD);

        // Byte/halfword lane and sign-extension alignment.
        inst_mem[10] = rv_itype(12'd23, 5'd1, 3'b000, 5'd13, OP_LOAD);
        inst_mem[11] = rv_itype(12'd23, 5'd1, 3'b100, 5'd14, OP_LOAD);
        inst_mem[12] = rv_itype(12'd22, 5'd1, 3'b001, 5'd15, OP_LOAD);
        inst_mem[13] = rv_itype(12'd22, 5'd1, 3'b101, 5'd16, OP_LOAD);

        // Full-word store forwarding and a dependent consumer.
        inst_mem[14] = rv_itype(12'hfff, 5'd0, 3'b000, 5'd17, OP_IMM);
        inst_mem[15] = rv_stype(12'd24, 5'd17, 5'd1, 3'b010, OP_STORE);
        inst_mem[16] = rv_itype(12'd24, 5'd1, 3'b010, 5'd18, OP_LOAD);
        inst_mem[17] = rv_itype(12'd1, 5'd18, 3'b000, 5'd19, OP_IMM);

        // Load result forwarded into store data, then read back.
        inst_mem[18] = rv_itype(12'd28, 5'd1, 3'b010, 5'd20, OP_LOAD);
        inst_mem[19] = rv_stype(12'd32, 5'd20, 5'd1, 3'b010, OP_STORE);
        inst_mem[20] = rv_itype(12'd32, 5'd1, 3'b010, 5'd21, OP_LOAD);

        // Two writers to the same rd: the MEM_RESP value from the younger
        // load must override any older MEM/WB value.
        inst_mem[21] = rv_itype(12'd44, 5'd1, 3'b010, 5'd25, OP_LOAD);
        inst_mem[22] = rv_itype(12'd48, 5'd1, 3'b010, 5'd25, OP_LOAD);
        inst_mem[23] = rv_itype(12'd3, 5'd25, 3'b000, 5'd26, OP_IMM);

        // Load result used immediately as the base of the next load.
        inst_mem[24] = rv_itype(12'd52, 5'd1, 3'b010, 5'd27, OP_LOAD);
        inst_mem[25] = rv_itype(12'd0, 5'd27, 3'b010, 5'd28, OP_LOAD);

        // Load-to-branch dependency.  The wrong-path store must be flushed.
        inst_mem[26] = rv_itype(12'd36, 5'd1, 3'b010, 5'd22, OP_LOAD);
        inst_mem[27] = rv_btype(13'd8, 5'd0, 5'd22, 3'b000, OP_BRANCH);
        inst_mem[28] = rv_stype(12'd40, 5'd17, 5'd1, 3'b010, OP_STORE);
        inst_mem[29] = rv_itype(12'd40, 5'd1, 3'b010, 5'd23, OP_LOAD);
        inst_mem[30] = rv_itype(12'd1, 5'd0, 3'b000, 5'd24, OP_IMM);
        inst_mem[31] = 32'h0000_006f; // jal x0, 0
    end

    integer pass_count;
    integer fail_count;
    integer alignment_fail_count;
    integer sim_cycle;
    integer lw7_commit_cycle;
    integer lw8_commit_cycle;
    integer retire_unique_count;
    integer observed_load_requests;
    integer observed_store_requests;
    integer observed_dependency_stalls;
    integer retire_idx;
    reg [30:0] retire_seen;
    reg saw_byte_forward;
    reg saw_word_forward;

    task check_reg;
        input [4:0] raddr;
        input [31:0] expected;
        input [255:0] name;
        reg [31:0] actual;
        begin
            actual = dut.reg5.regs[raddr];
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s: x%0d = 0x%08x", name, raddr, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s: x%0d = 0x%08x, expected 0x%08x",
                         name, raddr, actual, expected);
            end
        end
    endtask

    task check_value;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] name;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s: 0x%08x", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s: 0x%08x, expected 0x%08x",
                         name, actual, expected);
            end
        end
    endtask

    task alignment_error;
        input [255:0] name;
        begin
            alignment_fail_count = alignment_fail_count + 1;
            if (alignment_fail_count <= 8)
                $display("[ALIGN-FAIL] cycle=%0d %0s", sim_cycle, name);
        end
    endtask

    reg                         prev_ex2_valid;
    reg [`KLDJ_PC]              prev_ex2_pc;
    reg [`KLDJ_REGADDR]         prev_ex2_rd_addr;
    reg                         prev_ex2_wb_ctl;
    reg [17:0]                  prev_ex2_exu_op;
    reg [3:0]                   prev_ex2_ls_ctl;
    reg [`KLDJ_DATA]            prev_ex2_exu_res;
    reg [`KLDJ_DATA]            prev_ex2_mem_addr;
    reg [`KLDJ_DATA]            prev_mem_rdata;

    reg                         prev_resp_valid;
    reg [`KLDJ_PC]              prev_resp_pc;
    reg [`KLDJ_REGADDR]         prev_resp_rd_addr;
    reg                         prev_stage_wb_ctl;
    reg [`KLDJ_DATA]            prev_stage_wb_data;

    // Cycle-accurate alignment assertions for EX2/MEM -> MEM_RESP -> MEM/WB.
    always @(posedge clk) begin
        #1;
        if (rst) begin
            sim_cycle              = 0;
            prev_ex2_valid         = 1'b0;
            prev_ex2_pc            = `KLDJ_ZERO32;
            prev_ex2_rd_addr       = 5'd0;
            prev_ex2_wb_ctl        = 1'b0;
            prev_ex2_exu_op        = 18'd0;
            prev_ex2_ls_ctl        = 4'd0;
            prev_ex2_exu_res       = `KLDJ_ZERO32;
            prev_ex2_mem_addr      = `KLDJ_ZERO32;
            prev_mem_rdata         = mem_rdata;
            prev_resp_valid        = 1'b0;
            prev_resp_pc           = `KLDJ_ZERO32;
            prev_resp_rd_addr      = 5'd0;
            prev_stage_wb_ctl      = 1'b0;
            prev_stage_wb_data     = `KLDJ_ZERO32;
        end else begin
            sim_cycle = sim_cycle + 1;

            if (dut.mem_resp_valid !== prev_ex2_valid)
                alignment_error("mem_resp_valid is not previous ex2_mem_valid");
            if (prev_ex2_valid) begin
                if (dut.mem_resp_pc !== prev_ex2_pc)
                    alignment_error("mem_resp_pc metadata mismatch");
                if (dut.mem_resp_rd_addr !== prev_ex2_rd_addr)
                    alignment_error("mem_resp_rd_addr metadata mismatch");
                if (dut.u_mem_stage_top.mem_resp_wb_ctl !==
                    (prev_ex2_valid && prev_ex2_wb_ctl))
                    alignment_error("mem_resp_wb_ctl metadata mismatch");
                if (dut.u_mem_stage_top.mem_resp_exu_op !== prev_ex2_exu_op)
                    alignment_error("mem_resp_exu_op metadata mismatch");
                if (dut.u_mem_stage_top.mem_resp_ls_ctl !== prev_ex2_ls_ctl)
                    alignment_error("mem_resp_ls_ctl metadata mismatch");
                if (dut.u_mem_stage_top.mem_resp_exu_res !== prev_ex2_exu_res)
                    alignment_error("mem_resp_exu_res metadata mismatch");
                if (dut.u_mem_stage_top.mem_resp_mem_addr !== prev_ex2_mem_addr)
                    alignment_error("mem_resp_mem_addr metadata mismatch");
                if ((prev_ex2_exu_op >= 18'h1d) &&
                    (prev_ex2_exu_op <= 18'h21) &&
                    (dut.u_mem_stage_top.mem_resp_rdata !== prev_mem_rdata))
                    alignment_error("raw memory response was not registered in alignment");
            end

            if (dut.mem_wb_valid !== prev_resp_valid)
                alignment_error("mem_wb_valid is not previous mem_resp_valid");
            if (prev_resp_valid) begin
                if (dut.mem_wb_pc !== prev_resp_pc)
                    alignment_error("mem_wb_pc metadata mismatch");
                if (dut.mem_wb_rd_addr !== prev_resp_rd_addr)
                    alignment_error("mem_wb_rd_addr metadata mismatch");
                if (dut.mem_wb_wb_ctl !== prev_stage_wb_ctl)
                    alignment_error("mem_wb_wb_ctl mismatch");
                if (dut.mem_wb_wb_data !== prev_stage_wb_data)
                    alignment_error("mem_wb_wb_data mismatch");
            end

            prev_ex2_valid     = dut.ex2_mem_valid;
            prev_ex2_pc        = dut.ex2_mem_pc;
            prev_ex2_rd_addr   = dut.ex2_mem_rd_addr;
            prev_ex2_wb_ctl    = dut.ex2_mem_wb_ctl;
            prev_ex2_exu_op    = dut.ex2_mem_exu_op;
            prev_ex2_ls_ctl    = dut.ex2_mem_ls_ctl;
            prev_ex2_exu_res   = dut.ex2_mem_exu_res;
            prev_ex2_mem_addr  = dut.ex2_mem_mem_addr;
            prev_mem_rdata     = mem_rdata;

            prev_resp_valid    = dut.mem_resp_valid;
            prev_resp_pc       = dut.mem_resp_pc;
            prev_resp_rd_addr  = dut.mem_resp_rd_addr;
            prev_stage_wb_ctl  = dut.mem_stage_wb_ctl;
            prev_stage_wb_data = dut.mem_stage_wb_data;
        end
    end

    // Commit/order checks and observation of the real DRAM store buffer.
    always @(posedge clk) begin
        #2;
        if (!rst) begin
            if (mem_we)
                observed_store_requests = observed_store_requests + 1;
            else if (mem_addr[31:18] == 14'h2004)
                observed_load_requests = observed_load_requests + 1;

            if (dut.ex1_dependency_stall)
                observed_dependency_stalls = observed_dependency_stalls + 1;

            if (bridge.dram_driver_inst.fwd_byte_en_r == 4'b0010)
                saw_byte_forward = 1'b1;
            if (bridge.dram_driver_inst.fwd_byte_en_r == 4'b1111)
                saw_word_forward = 1'b1;

            if (dut.wb_commit_valid) begin
                retire_idx = (dut.wb_commit_pc - START_PC) >> 2;
                if ((retire_idx >= 0) && (retire_idx <= 30)) begin
                    if (retire_seen[retire_idx]) begin
                        fail_count = fail_count + 1;
                        $display("[FAIL] duplicate retirement at instruction %0d", retire_idx);
                    end else begin
                        retire_seen[retire_idx] = 1'b1;
                        retire_unique_count = retire_unique_count + 1;
                    end
                end

                if (dut.wb_commit_pc == START_PC + 32'd12) begin
                    lw7_commit_cycle = sim_cycle;
                    if ((dut.wb_commit_rd_addr !== 5'd7) ||
                        (dut.wb_commit_wb_data !== 32'h1122_3344))
                        alignment_error("first back-to-back load committed wrong rd/data");
                end
                if (dut.wb_commit_pc == START_PC + 32'd16) begin
                    lw8_commit_cycle = sim_cycle;
                    if ((dut.wb_commit_rd_addr !== 5'd8) ||
                        (dut.wb_commit_wb_data !== 32'h5566_7788))
                        alignment_error("second back-to-back load committed wrong rd/data");
                end
            end
        end
    end

    initial begin
        rst                  = 1'b1;
        pass_count           = 0;
        fail_count           = 0;
        alignment_fail_count = 0;
        sim_cycle            = 0;
        lw7_commit_cycle     = -1;
        lw8_commit_cycle     = -1;
        retire_unique_count  = 0;
        observed_load_requests = 0;
        observed_store_requests = 0;
        observed_dependency_stalls = 0;
        retire_seen          = 31'd0;
        saw_byte_forward     = 1'b0;
        saw_word_forward     = 1'b0;

        // Wait until DRAM_TDP's own zero-fill initial block has completed.
        #1;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 1] = 32'h1122_3344;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 2] = 32'h1122_3344;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 3] = 32'h5566_7788;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 4] = 32'h1122_3344;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 5] = 32'h80ff_7f01;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 6] = 32'h0000_0000;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 7] = 32'hcafe_babe;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 8] = 32'h0000_0000;
        bridge.dram_driver_inst.u_dram_tdp.mem[ 9] = 32'h0000_0000;
        bridge.dram_driver_inst.u_dram_tdp.mem[10] = 32'h1234_5678;
        bridge.dram_driver_inst.u_dram_tdp.mem[11] = 32'h1111_1111;
        bridge.dram_driver_inst.u_dram_tdp.mem[12] = 32'h2222_2222;
        bridge.dram_driver_inst.u_dram_tdp.mem[13] = DRAM_BASE + 32'd56;
        bridge.dram_driver_inst.u_dram_tdp.mem[14] = 32'hdead_beef;

        repeat (6) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
    end

    integer timeout_cycles;
    initial begin
        wait (rst == 1'b0);
        for (timeout_cycles = 0; timeout_cycles < 500; timeout_cycles = timeout_cycles + 1) begin
            @(posedge clk);
            #3;
            if (dut.reg5.regs[24] === 32'd1) begin
                repeat (12) @(posedge clk);
                #3;

                check_reg(5'd5,  32'h1122_3344, "direct load value");
                check_reg(5'd6,  32'h1122_3345, "load-use forwarding");
                check_reg(5'd7,  32'h1122_3344, "back-to-back load 0");
                check_reg(5'd8,  32'h5566_7788, "back-to-back load 1");
                check_reg(5'd9,  32'h6688_aacc, "two-source load consumer");
                check_reg(5'd11, 32'h1122_aa44, "partial store then word load");
                check_reg(5'd12, 32'h0000_00aa, "partial store then byte load");
                check_reg(5'd13, 32'hffff_ff80, "signed byte lane alignment");
                check_reg(5'd14, 32'h0000_0080, "unsigned byte lane alignment");
                check_reg(5'd15, 32'hffff_80ff, "signed halfword alignment");
                check_reg(5'd16, 32'h0000_80ff, "unsigned halfword alignment");
                check_reg(5'd18, 32'hffff_ffff, "full-word store forwarding");
                check_reg(5'd19, 32'h0000_0000, "forwarded load consumer");
                check_reg(5'd21, 32'hcafe_babe, "load-to-store data forwarding");
                check_reg(5'd25, 32'h2222_2222, "youngest same-rd load wins");
                check_reg(5'd26, 32'h2222_2225, "MEM_RESP priority over MEM/WB");
                check_reg(5'd27, DRAM_BASE + 32'd56, "load-to-load base forwarding");
                check_reg(5'd28, 32'hdead_beef, "dependent address load");
                check_reg(5'd23, 32'h1234_5678, "wrong-path store was flushed");

                check_value(bridge.dram_driver_inst.u_dram_tdp.mem[4],
                            32'h1122_aa44, "byte store memory image");
                check_value(bridge.dram_driver_inst.u_dram_tdp.mem[6],
                            32'hffff_ffff, "word store memory image");
                check_value(bridge.dram_driver_inst.u_dram_tdp.mem[8],
                            32'hcafe_babe, "load-to-store memory image");
                check_value(bridge.dram_driver_inst.u_dram_tdp.mem[10],
                            32'h1234_5678, "flushed store memory image");
                check_value(observed_load_requests, 32'd18, "issued load count");
                check_value(observed_store_requests, 32'd3, "issued store count");
                check_value(retire_unique_count, 32'd30, "unique retired instructions");

                if (!saw_byte_forward) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] DRAM byte-level store forwarding was not observed");
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] DRAM byte-level store forwarding observed");
                end

                if (!saw_word_forward) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] DRAM word-level store forwarding was not observed");
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] DRAM word-level store forwarding observed");
                end

                if ((lw7_commit_cycle < 0) ||
                    (lw8_commit_cycle != lw7_commit_cycle + 1)) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] back-to-back loads did not commit on consecutive cycles (%0d, %0d)",
                             lw7_commit_cycle, lw8_commit_cycle);
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] back-to-back load response throughput is one per cycle");
                end

                if (retire_seen[28]) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] wrong-path store instruction retired");
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] wrong-path store instruction did not retire");
                end

                if (alignment_fail_count != 0) begin
                    fail_count = fail_count + alignment_fail_count;
                    $display("[FAIL] MEM-response alignment failures: %0d",
                             alignment_fail_count);
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] MEM-response metadata/data alignment assertions");
                end

                if (observed_dependency_stalls == 0) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] no dependency stall was observed");
                end else begin
                    pass_count = pass_count + 1;
                    $display("[PASS] dependency stalls observed: %0d",
                             observed_dependency_stalls);
                end

                $display("[SUMMARY] pass=%0d fail=%0d cycles=%0d stalls=%0d",
                         pass_count, fail_count, sim_cycle,
                         observed_dependency_stalls);
                if (fail_count == 0) begin
                    $display("MEM RESPONSE PIPELINE TEST PASSED");
                    $finish;
                end else begin
                    $fatal(1, "MEM RESPONSE PIPELINE TEST FAILED");
                end
            end
        end

        $fatal(1, "timeout waiting for directed MEM-response program");
    end

endmodule
