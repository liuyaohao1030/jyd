`timescale 1ns / 1ps

`include "define.v"

// Program-driven branch-prediction and IPC benchmark.
// All profiling logic is testbench-only and has no synthesis impact.
module KLDJ_branch_perf_tb;

    localparam [31:0] START_PC      = 32'h8000_0000;
    localparam [31:0] TERMINAL_PC   = 32'h8000_0014;
    localparam [31:0] TERMINAL_INST = 32'h0000_006f; // jal x0, 0
    localparam [31:0] NOP_INST      = 32'h0000_0013;
    localparam integer IROM_DEPTH   = 4096;
    localparam integer DRAM_DEPTH   = 65536; // 256 KiB / 4 bytes

    reg clk;
    reg rst;
    reg stop_fetch;
    reg images_loaded;
    reg report_done;
    string report_reason;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // COE image loader
    // ------------------------------------------------------------------
    reg [31:0] inst_mem [0:IROM_DEPTH-1];
    reg [31:0] data_mem [0:DRAM_DEPTH-1];

    string irom_path;
    string dram_path;
    reg    use_jalr_baseline;
    integer irom_fd;
    integer dram_fd;
    integer load_rc;
    integer irom_words_loaded;
    integer dram_words_loaded;
    integer init_i;
    reg [1023:0] coe_line;
    reg [31:0] parsed_word;

    initial begin : load_program_images
        images_loaded = 1'b0;

        for (init_i = 0; init_i < IROM_DEPTH; init_i = init_i + 1)
            inst_mem[init_i] = NOP_INST;
        for (init_i = 0; init_i < DRAM_DEPTH; init_i = init_i + 1)
            data_mem[init_i] = 32'h0000_0000;

        use_jalr_baseline = $test$plusargs("JALR_BASELINE");
        if (use_jalr_baseline)
            irom_path = "../../Program/jalr_baseline_irom.txt";
        else if (!$value$plusargs("IROM_COE=%s", irom_path))
            irom_path = "../../Program/irom-v2.txt";
        if (use_jalr_baseline)
            dram_path = "../../Program/jalr_baseline_dram.txt";
        irom_fd = $fopen(irom_path, "r");
        if (irom_fd == 0) begin
            if (use_jalr_baseline)
                $fatal(1, "Cannot open JALR baseline IROM: %s", irom_path);
            irom_path = "Program/irom-v2.txt";
            irom_fd = $fopen(irom_path, "r");
        end
        if (irom_fd == 0) begin
            irom_path = "../Program/irom-v2.txt";
            irom_fd = $fopen(irom_path, "r");
        end
        if (irom_fd == 0)
            $fatal(1, "Cannot open IROM COE. Use +IROM_COE=<path>.");

        irom_words_loaded = 0;
        while (!$feof(irom_fd)) begin
            coe_line = {1024{1'b0}};
            load_rc = $fgets(coe_line, irom_fd);
            if ($sscanf(coe_line, "%h", parsed_word) == 1) begin
                if (irom_words_loaded >= IROM_DEPTH)
                    $fatal(1, "IROM image exceeds %0d words", IROM_DEPTH);
                inst_mem[irom_words_loaded] = parsed_word;
                irom_words_loaded = irom_words_loaded + 1;
            end
        end
        $fclose(irom_fd);

        if (!use_jalr_baseline &&
            !$value$plusargs("DRAM_COE=%s", dram_path))
            dram_path = "../../Program/dram.txt";
        dram_fd = $fopen(dram_path, "r");
        if (dram_fd == 0) begin
            if (use_jalr_baseline)
                $fatal(1, "Cannot open JALR baseline DRAM: %s", dram_path);
            dram_path = "Program/dram.txt";
            dram_fd = $fopen(dram_path, "r");
        end
        if (dram_fd == 0) begin
            dram_path = "../Program/dram.txt";
            dram_fd = $fopen(dram_path, "r");
        end
        if (dram_fd == 0)
            $fatal(1, "Cannot open DRAM COE. Use +DRAM_COE=<path>.");

        dram_words_loaded = 0;
        while (!$feof(dram_fd)) begin
            coe_line = {1024{1'b0}};
            load_rc = $fgets(coe_line, dram_fd);
            if ($sscanf(coe_line, "%h", parsed_word) == 1) begin
                if (dram_words_loaded >= DRAM_DEPTH)
                    $fatal(1, "DRAM image exceeds %0d words", DRAM_DEPTH);
                data_mem[dram_words_loaded] = parsed_word;
                dram_words_loaded = dram_words_loaded + 1;
            end
        end
        $fclose(dram_fd);

        if (irom_words_loaded == 0 || dram_words_loaded == 0)
            $fatal(1, "Program image is empty");

        $display("Loaded IROM: %0d words from %s", irom_words_loaded, irom_path);
        $display("Loaded DRAM: %0d words from %s", dram_words_loaded, dram_path);
        images_loaded = 1'b1;
    end

    // ------------------------------------------------------------------
    // Instruction and data memory models
    // ------------------------------------------------------------------
    wire [31:0] if_pc;
    wire [11:0] inst_word_addr = if_pc[13:2];
    wire        inst_addr_valid = (if_pc[31:14] == START_PC[31:14]);
    wire [31:0] inst_from_mem = inst_addr_valid ? inst_mem[inst_word_addr] : NOP_INST;
    wire [31:0] inst_rdata = stop_fetch ? NOP_INST : inst_from_mem;

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    reg  [31:0] mem_rdata;

    wire        mem_is_dram = (mem_addr[31:18] == 14'h2004);
    wire [15:0] data_word_addr = mem_addr[17:2];

    always @(posedge clk) begin
        if (mem_we && mem_is_dram) begin
            if (mem_be[0]) data_mem[data_word_addr][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_be[1]) data_mem[data_word_addr][15: 8] <= mem_wdata[15: 8];
            if (mem_be[2]) data_mem[data_word_addr][23:16] <= mem_wdata[23:16];
            if (mem_be[3]) data_mem[data_word_addr][31:24] <= mem_wdata[31:24];
        end
        mem_rdata <= mem_is_dram ? data_mem[data_word_addr] : 32'h0000_0000;
    end

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    wire        tb_ex_jump;
    wire [31:0] tb_ex_jump_pc;
    wire [31:0] tb_ex_res;
    wire        core_clk_o;

    wire [31:0] perf_cycle_count;
    wire [31:0] perf_instret_count;
    wire [31:0] perf_frontend_stall_count;
    wire [31:0] perf_load_use_stall_count;
    wire [31:0] perf_mul_stall_count;
    wire [31:0] perf_div_stall_count;
    wire [31:0] perf_redirect_count;
    wire [31:0] perf_load_count;
    wire [31:0] perf_store_count;

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
        ,.perf_cycle_count          (perf_cycle_count          )
        ,.perf_instret_count        (perf_instret_count        )
        ,.perf_frontend_stall_count (perf_frontend_stall_count )
        ,.perf_load_use_stall_count (perf_load_use_stall_count )
        ,.perf_mul_stall_count      (perf_mul_stall_count      )
        ,.perf_div_stall_count      (perf_div_stall_count      )
        ,.perf_redirect_count       (perf_redirect_count       )
        ,.perf_load_count           (perf_load_count           )
        ,.perf_store_count          (perf_store_count          )
    );

    // Allow the terminal jal to enter IF/ID exactly once. Subsequent fetches
    // become NOPs, so benchmark counters stop at a clean retirement boundary.
    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            stop_fetch <= 1'b0;
        end else if (!stop_fetch && if_pc == TERMINAL_PC &&
                     inst_from_mem == TERMINAL_INST) begin
            stop_fetch <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Testbench-only dynamic branch profiling
    // ------------------------------------------------------------------
    integer cond_branch_count;
    integer cond_taken_count;
    integer cond_direction_correct_count;
    integer cond_direction_miss_count;
    integer cond_target_miss_count;
    integer cond_prediction_correct_count;
    integer cond_prediction_miss_count;
    integer jal_count;
    integer jal_prediction_correct_count;
    integer jal_prediction_miss_count;
    integer jalr_count;
    integer jalr_predicted_count;
    integer jalr_prediction_correct_count;
    integer jalr_prediction_miss_count;
    integer ret_count;
    integer ret_predicted_count;
    integer ret_prediction_correct_count;
    integer control_redirect_count;
    integer ecall_count;
    integer mret_count;
    integer frontend_lookup_count;
    integer frontend_btb_hit_count;
    integer frontend_bpu_taken_count;
    integer next_heartbeat_cycle;
    integer measured_cycle_count;
    integer measured_instret_count;
    integer measured_frontend_stall_count;
    integer measured_load_use_stall_count;
    integer measured_mul_stall_count;
    integer measured_div_stall_count;
    integer measured_load_count;
    integer measured_store_count;
    integer measure_instret_limit;

    reg branch_actual_taken;
    reg branch_direction_correct;
    reg branch_target_correct;
    reg jalr_is_ret;

    task automatic clear_profile_counters;
        begin
            cond_branch_count = 0;
            cond_taken_count = 0;
            cond_direction_correct_count = 0;
            cond_direction_miss_count = 0;
            cond_target_miss_count = 0;
            cond_prediction_correct_count = 0;
            cond_prediction_miss_count = 0;
            jal_count = 0;
            jal_prediction_correct_count = 0;
            jal_prediction_miss_count = 0;
            jalr_count = 0;
            jalr_predicted_count = 0;
            jalr_prediction_correct_count = 0;
            jalr_prediction_miss_count = 0;
            ret_count = 0;
            ret_predicted_count = 0;
            ret_prediction_correct_count = 0;
            control_redirect_count = 0;
            ecall_count = 0;
            mret_count = 0;
            frontend_lookup_count = 0;
            frontend_btb_hit_count = 0;
            frontend_bpu_taken_count = 0;
            next_heartbeat_cycle = 1_000_000;
            measured_cycle_count = 0;
            measured_instret_count = 0;
            measured_frontend_stall_count = 0;
            measured_load_use_stall_count = 0;
            measured_mul_stall_count = 0;
            measured_div_stall_count = 0;
            measured_load_count = 0;
            measured_store_count = 0;
        end
    endtask

    task automatic report_profile;
        integer profile_miss_count;
        integer sig_i;
        reg [31:0] reg_signature;
        reg [31:0] dram_signature;
        real ipc;
        real cpi;
        real branch_accuracy;
        real jalr_accuracy;
        real ret_accuracy;
        real predictor_mpki;
        real redirect_mpki;
        begin
            profile_miss_count = cond_prediction_miss_count +
                                 jal_prediction_miss_count +
                                 jalr_prediction_miss_count;

            ipc = (measured_cycle_count != 0) ?
                  $itor(measured_instret_count) / $itor(measured_cycle_count) : 0.0;
            cpi = (measured_instret_count != 0) ?
                  $itor(measured_cycle_count) / $itor(measured_instret_count) : 0.0;
            branch_accuracy = (cond_branch_count != 0) ?
                  100.0 * $itor(cond_prediction_correct_count) /
                  $itor(cond_branch_count) : 0.0;
            jalr_accuracy = (jalr_count != 0) ?
                  100.0 * $itor(jalr_prediction_correct_count) /
                  $itor(jalr_count) : 0.0;
            ret_accuracy = (ret_count != 0) ?
                  100.0 * $itor(ret_prediction_correct_count) /
                  $itor(ret_count) : 0.0;
            predictor_mpki = (measured_instret_count != 0) ?
                  1000.0 * $itor(profile_miss_count) /
                  $itor(measured_instret_count) : 0.0;
            redirect_mpki = (measured_instret_count != 0) ?
                  1000.0 * $itor(control_redirect_count) /
                  $itor(measured_instret_count) : 0.0;

            reg_signature = 32'h0000_0000;
            for (sig_i = 0; sig_i < 32; sig_i = sig_i + 1)
                reg_signature = {reg_signature[30:0], reg_signature[31]} ^
                                u_dut.reg5.regs[sig_i] ^ sig_i;

            dram_signature = 32'h0000_0000;
            for (sig_i = 0; sig_i < DRAM_DEPTH; sig_i = sig_i + 1)
                dram_signature = {dram_signature[30:0], dram_signature[31]} ^
                                 data_mem[sig_i] ^ sig_i;

            $display("");
            $display("============================================================");
            $display("  KLDJ Branch Prediction / IPC Baseline");
            $display("============================================================");
            $display("measurement stop reason        : %s", report_reason);
            $display("cycles                         : %0d", measured_cycle_count);
            $display("instructions retired           : %0d", measured_instret_count);
            $display("IPC / CPI                      : %0.4f / %0.4f", ipc, cpi);
            $display("frontend/load-use/mul/div stall: %0d / %0d / %0d / %0d",
                     measured_frontend_stall_count, measured_load_use_stall_count,
                     measured_mul_stall_count, measured_div_stall_count);
            $display("loads / stores                 : %0d / %0d",
                     measured_load_count, measured_store_count);
            $display("");
            $display("conditional branches           : %0d (taken %0d)",
                     cond_branch_count, cond_taken_count);
            $display("direction correct / miss       : %0d / %0d",
                     cond_direction_correct_count, cond_direction_miss_count);
            $display("conditional target mismatches  : %0d", cond_target_miss_count);
            $display("conditional prediction accuracy: %0.3f%%", branch_accuracy);
            $display("JAL correct / total            : %0d / %0d",
                     jal_prediction_correct_count, jal_count);
            $display("JALR predicted/correct/total   : %0d / %0d / %0d",
                     jalr_predicted_count, jalr_prediction_correct_count,
                     jalr_count);
            $display("JALR prediction accuracy       : %0.3f%%", jalr_accuracy);
            $display("RET predicted/correct/total    : %0d / %0d / %0d",
                     ret_predicted_count, ret_prediction_correct_count,
                     ret_count);
            $display("RET prediction accuracy        : %0.3f%%", ret_accuracy);
            $display("ECALL / MRET                   : %0d / %0d", ecall_count, mret_count);
            $display("profiled predictor misses      : %0d", profile_miss_count);
            $display("control redirects              : %0d", control_redirect_count);
            $display("predictor MPKI / redirect MPKI : %0.3f / %0.3f",
                     predictor_mpki, redirect_mpki);
            $display("frontend lookups/BTB hits/taken: %0d / %0d / %0d",
                     frontend_lookup_count, frontend_btb_hit_count,
                     frontend_bpu_taken_count);
            $display("");
            $display("register signature             : %08x", reg_signature);
            $display("DRAM signature                 : %08x", dram_signature);
            $display("DRAM words [0..%0d]", dram_words_loaded-1);
            for (sig_i = 0; sig_i < dram_words_loaded; sig_i = sig_i + 1)
                $display("  dram[%0d] = %08x", sig_i, data_mem[sig_i]);
            $display("============================================================");
        end
    endtask

    always @(negedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            clear_profile_counters();
        end else if (!report_done) begin
            measured_cycle_count = measured_cycle_count + 1;
            if (u_dut.wb_commit_valid)
                measured_instret_count = measured_instret_count + 1;
            if (u_dut.frontend_stall)
                measured_frontend_stall_count = measured_frontend_stall_count + 1;
            if (u_dut.load_use_stall)
                measured_load_use_stall_count = measured_load_use_stall_count + 1;
            if (u_dut.mul_stall)
                measured_mul_stall_count = measured_mul_stall_count + 1;
            if (u_dut.div_stall)
                measured_div_stall_count = measured_div_stall_count + 1;
            if (u_dut.id_ex_valid && !u_dut.ex_stall && u_dut.id_ex_load_op)
                measured_load_count = measured_load_count + 1;
            if (u_dut.id_ex_valid && !u_dut.ex_stall && u_dut.id_ex_store_op)
                measured_store_count = measured_store_count + 1;

            if (measured_cycle_count >= next_heartbeat_cycle) begin
                $display("[progress] cycles=%0d instret=%0d PC=%08x redirects=%0d",
                         measured_cycle_count, measured_instret_count, if_pc,
                         control_redirect_count);
                next_heartbeat_cycle = next_heartbeat_cycle + 1_000_000;
            end

            if (!u_dut.frontend_stall && !u_dut.ex_redirect && !stop_fetch) begin
                frontend_lookup_count = frontend_lookup_count + 1;
                if (u_dut.if_btb_hit)
                    frontend_btb_hit_count = frontend_btb_hit_count + 1;
                if (u_dut.bpu_pred_taken)
                    frontend_bpu_taken_count = frontend_bpu_taken_count + 1;
            end

            if (u_dut.id_ex_valid) begin
                if (u_dut.ex_redirect)
                    control_redirect_count = control_redirect_count + 1;

                if (u_dut.id_ex_exu_op >= 18'h14 &&
                    u_dut.id_ex_exu_op <= 18'h19) begin
                    cond_branch_count = cond_branch_count + 1;
                    branch_actual_taken = u_dut.exu_jump_raw;
                    branch_direction_correct =
                        (u_dut.id_ex_pred_taken == branch_actual_taken);
                    branch_target_correct = !branch_actual_taken ||
                        (u_dut.id_ex_pred_taken &&
                         u_dut.id_ex_pred_target == u_dut.exu_jump_pc_raw);

                    if (branch_actual_taken)
                        cond_taken_count = cond_taken_count + 1;
                    if (branch_direction_correct)
                        cond_direction_correct_count =
                            cond_direction_correct_count + 1;
                    else
                        cond_direction_miss_count = cond_direction_miss_count + 1;
                    if (branch_actual_taken && u_dut.id_ex_pred_taken &&
                        !branch_target_correct)
                        cond_target_miss_count = cond_target_miss_count + 1;

                    if (branch_direction_correct && branch_target_correct)
                        cond_prediction_correct_count =
                            cond_prediction_correct_count + 1;
                    else
                        cond_prediction_miss_count =
                            cond_prediction_miss_count + 1;
                end else if (u_dut.id_ex_exu_op == 18'h1c) begin
                    jal_count = jal_count + 1;
                    if (u_dut.id_ex_pred_taken &&
                        u_dut.id_ex_pred_target == u_dut.exu_jump_pc_raw)
                        jal_prediction_correct_count =
                            jal_prediction_correct_count + 1;
                    else
                        jal_prediction_miss_count = jal_prediction_miss_count + 1;
                end else if (u_dut.id_ex_exu_op == 18'h9) begin
                    jalr_count = jalr_count + 1;
                    jalr_is_ret = (u_dut.id_ex_rd_addr == 5'd0) &&
                                  ((u_dut.id_ex_rs1_addr == 5'd1) ||
                                   (u_dut.id_ex_rs1_addr == 5'd5)) &&
                                  (u_dut.id_ex_data2 == 32'd0);

                    if (u_dut.id_ex_pred_taken && u_dut.id_ex_pred_is_jalr)
                        jalr_predicted_count = jalr_predicted_count + 1;
                    if (u_dut.id_ex_pred_taken && u_dut.id_ex_pred_is_jalr &&
                        u_dut.id_ex_pred_target == u_dut.exu_jump_pc_raw)
                        jalr_prediction_correct_count =
                            jalr_prediction_correct_count + 1;
                    else
                        jalr_prediction_miss_count =
                            jalr_prediction_miss_count + 1;

                    if (jalr_is_ret) begin
                        ret_count = ret_count + 1;
                        if (u_dut.id_ex_pred_taken && u_dut.id_ex_pred_is_jalr)
                            ret_predicted_count = ret_predicted_count + 1;
                        if (u_dut.id_ex_pred_taken && u_dut.id_ex_pred_is_jalr &&
                            u_dut.id_ex_pred_target == u_dut.exu_jump_pc_raw)
                            ret_prediction_correct_count =
                                ret_prediction_correct_count + 1;
                    end
                end else if (u_dut.id_ex_exu_op == `KLDJ_EXU_ECALL) begin
                    ecall_count = ecall_count + 1;
                end else if (u_dut.id_ex_exu_op == `KLDJ_EXU_MRET) begin
                    mret_count = mret_count + 1;
                end
            end

            if (u_dut.wb_commit_valid &&
                u_dut.wb_commit_pc == TERMINAL_PC) begin
                report_done = 1'b1;
                report_reason = "program terminal instruction retired";
                report_profile();
                $finish;
            end else if (measured_instret_count >= measure_instret_limit) begin
                report_done = 1'b1;
                report_reason = "fixed retired-instruction measurement window";
                report_profile();
                $finish;
            end
        end
    end

    // ------------------------------------------------------------------
    // Reset, timeout, and waveform
    // ------------------------------------------------------------------
    integer max_cycles;
    initial begin
        rst = `KLDJ_RSTABLE;
        stop_fetch = 1'b0;
        report_done = 1'b0;
        report_reason = "not completed";
        measure_instret_limit = 7_000_000;
        if ($value$plusargs("MEASURE_INSTRET=%d", measure_instret_limit)) begin end
        clear_profile_counters();

        wait (images_loaded == 1'b1);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = ~`KLDJ_RSTABLE;
        $display("Running branch-performance benchmark...");
    end

    initial begin : timeout_guard
        max_cycles = 20_000_000;
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin end
        wait (images_loaded == 1'b1);
        wait (rst != `KLDJ_RSTABLE);
        repeat (max_cycles) @(posedge clk);
        if (!report_done) begin
            report_profile();
            $fatal(1, "Benchmark timeout after %0d cycles, PC=%08x",
                   max_cycles, if_pc);
        end
    end

    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("KLDJ_branch_perf_tb.vcd");
            $dumpvars(1, KLDJ_branch_perf_tb);
            $dumpvars(0, u_dut);
        end
    end

endmodule
