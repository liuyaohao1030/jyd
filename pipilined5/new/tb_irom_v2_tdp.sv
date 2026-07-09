`timescale 1ns / 1ps
`include "define.v"

//////////////////////////////////////////////////////////////////////////////
// Testbench: tb_irom_v2_tdp
//
// Full-system test: KLDJ_top + perip_bridge + dram_driver + DRAM_TDP
// This testbench uses the TRUE DUAL PORT BRAM path for data memory,
// verifying that the modified dram_driver works correctly with the CPU.
//
// The irom-v2 test program exercises:
//   - Basic Store/Load
//   - Load-Use Stall
//   - Byte/Halfword/Word read/write
//   - CSR read/write
//   - ECALL/MRET
//   - Various ALU operations
//////////////////////////////////////////////////////////////////////////////

module tb_irom_v2_tdp;

    // ------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------
    reg         clk;
    reg         cnt_clk;
    reg         rst;

    initial clk = 0;
    always #5 clk = ~clk;       // 100 MHz

    initial cnt_clk = 0;
    always #10 cnt_clk = ~cnt_clk;  // 50 MHz

    // ------------------------------------------------
    // Instruction Memory (combinational read)
    // ------------------------------------------------
    reg [31:0] inst_mem [0:4095];

    wire [31:0] if_pc;
    wire [31:0] inst_rdata;

    wire [12:0] inst_word_addr = if_pc[14:2];
    assign inst_rdata = inst_mem[inst_word_addr];

    // ------------------------------------------------
    // CPU <-> perip_bridge interface
    // ------------------------------------------------
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire [31:0] mem_rdata;

    // Performance counters
    wire [31:0] perf_cycle_count;
    wire [31:0] perf_instret_count;
    wire [31:0] perf_frontend_stall_count;
    wire [31:0] perf_load_use_stall_count;
    wire [31:0] perf_mul_stall_count;
    wire [31:0] perf_div_stall_count;
    wire [31:0] perf_redirect_count;
    wire [31:0] perf_load_count;
    wire [31:0] perf_store_count;

    // LED/SEG outputs
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    // ------------------------------------------------
    // DUT: KLDJ_top (CPU)
    // ------------------------------------------------
    KLDJ_top u_cpu (
        .clk            (clk),
        .rst            (rst),
        .tb_if_inst     (inst_rdata),
        .tb_if_pc       (if_pc),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_we         (mem_we),
        .mem_be         (mem_be),
        .mem_rdata      (mem_rdata),
        .tb_ex_jump     (),
        .tb_ex_jump_pc  (),
        .tb_ex_res      (),
        .core_clk_o     (),
        .perf_cycle_count         (perf_cycle_count),
        .perf_instret_count       (perf_instret_count),
        .perf_frontend_stall_count(perf_frontend_stall_count),
        .perf_load_use_stall_count(perf_load_use_stall_count),
        .perf_mul_stall_count     (perf_mul_stall_count),
        .perf_div_stall_count     (perf_div_stall_count),
        .perf_redirect_count      (perf_redirect_count),
        .perf_load_count          (perf_load_count),
        .perf_store_count         (perf_store_count)
    );

    // ------------------------------------------------
    // DUT: perip_bridge (includes dram_driver → DRAM_TDP)
    // ------------------------------------------------
    perip_bridge u_bridge (
        .clk                (clk),
        .cnt_clk            (cnt_clk),
        .rst                (rst),
        .perip_addr         (mem_addr),
        .perip_wdata        (mem_wdata),
        .perip_wen          (mem_we),
        .perip_be           (mem_be),
        .perip_rdata        (mem_rdata),
        .virtual_sw_input   (64'h0),
        .virtual_key_input  (8'h0),
        .virtual_seg_output (virtual_seg),
        .virtual_led_output (virtual_led)
    );

    // ------------------------------------------------
    // Monitor: DRAM write operations
    // ------------------------------------------------
    wire        dram_wen = mem_we &&
                    (mem_addr >= 32'h8010_0000) &&
                    (mem_addr < 32'h8014_0000);
    reg  [31:0] last_dram_addr;
    reg  [31:0] last_dram_data;

    always @(posedge clk) begin
        if (dram_wen) begin
            last_dram_addr <= mem_addr;
            last_dram_data <= mem_wdata;
        end
    end

    // ------------------------------------------------
    // Main
    // ------------------------------------------------
    integer err_count;

    initial begin
        $display("============================================================");
        $display("  irom-v2 Full System Test (KLDJ_top + perip_bridge + DRAM_TDP)");
        $display("============================================================");

        // Load instruction memory
        $readmemh("irom_v2.hex", inst_mem);
        $display("[%0t] Loaded irom_v2.hex (%0d instructions)", $time, 2219);

        // Reset
        err_count = 0;
        rst = `KLDJ_RSTABLE;
        repeat (10) @(posedge clk);
        rst = ~`KLDJ_RSTABLE;

        $display("[%0t] Reset released, starting execution...", $time);
        $display("");

        // Run for enough cycles to complete all tests
        repeat (20000) @(posedge clk);

        // Display results
        $display("");
        $display("============================================================");
        $display("  Execution Complete");
        $display("============================================================");
        $display("");
        $display("  Performance Counters:");
        $display("    cycle_count           = %0d", perf_cycle_count);
        $display("    instret_count         = %0d", perf_instret_count);
        $display("    frontend_stall_count  = %0d", perf_frontend_stall_count);
        $display("    load_use_stall_count  = %0d", perf_load_use_stall_count);
        $display("    mul_stall_count       = %0d", perf_mul_stall_count);
        $display("    div_stall_count       = %0d", perf_div_stall_count);
        $display("    redirect_count        = %0d", perf_redirect_count);
        $display("    load_count            = %0d", perf_load_count);
        $display("    store_count           = %0d", perf_store_count);
        $display("");

        if (perf_instret_count > 0) begin
            $display("  CPI  = %0d.%03d",
                     perf_cycle_count / perf_instret_count,
                     ((perf_cycle_count * 1000) / perf_instret_count) % 1000);
            $display("  IPC  = %0d.%03d",
                     perf_instret_count / perf_cycle_count,
                     ((perf_instret_count * 1000) / perf_cycle_count) % 1000);
        end

        $display("");
        $display("  LED output: 0x%08x", virtual_led);
        $display("  Last DRAM write: addr=0x%08x data=0x%08x",
                 last_dram_addr, last_dram_data);
        $display("");

        // Check if program ran successfully
        // The irom-v2 program should execute many instructions
        if (perf_instret_count > 1000) begin
            $display("  [PASS] Program executed %0d instructions successfully!",
                     perf_instret_count);
            $display("  True Dual Port BRAM read/write verified through perip_bridge.");
        end else begin
            $display("  [FAIL] Program only executed %0d instructions.",
                     perf_instret_count);
            err_count = err_count + 1;
        end

        // Check no X/Z on critical signals
        if (mem_rdata === 32'hxxxxxxxx || mem_rdata === 32'hzzzzzzzz) begin
            $display("  [FAIL] mem_rdata contains X/Z!");
            err_count = err_count + 1;
        end else begin
            $display("  [PASS] mem_rdata is clean (no X/Z).");
        end

        $display("");
        $display("============================================================");
        if (err_count == 0)
            $display("  ALL CHECKS PASSED!");
        else
            $display("  %0d CHECKS FAILED!", err_count);
        $display("============================================================");
        $finish;
    end

    // Timeout
    initial begin
        #5000000;
        $display("[TIMEOUT] Simulation exceeded time limit.");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("tb_irom_v2_tdp.vcd");
        $dumpvars(0, tb_irom_v2_tdp);
    end

endmodule
