`timescale 1ns / 1ps

`include "define.v"

// ============================================================================
// KLDJ irom-v2 Testbench with Performance Counters
//
// Loads the irom-v2 COE test program and runs it for a fixed number of cycles,
// then displays performance counter values and derived metrics (CPI, stall
// ratios, etc.).
// ============================================================================

module KLDJ_irom_v2_tb;

    // ------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------
    reg         clk;
    reg         rst;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz, 10ns period

    // ------------------------------------------------
    // Instruction Memory (combinational read)
    // Loaded from irom_v2.hex (extracted from irom-v2.md COE)
    // ------------------------------------------------
    reg [31:0] inst_mem [0:4095];

    wire [31:0] if_pc;
    wire [31:0] inst_rdata;

    wire [12:0] inst_word_addr = if_pc[14:2];
    assign inst_rdata = inst_mem[inst_word_addr];

    // ------------------------------------------------
    // Data Memory (sync write, registered read)
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
        ,.mem_load_rdata(mem_rdata    )
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

    // ------------------------------------------------
    // Main
    // ------------------------------------------------
    initial begin
        $display("==============================================");
        $display("  KLDJ irom-v2 Performance Counter Testbench");
        $display("==============================================");

        // Load instruction memory from hex file
        $readmemh("irom_v2.hex", inst_mem);

        // Reset
        rst = `KLDJ_RSTABLE;
        repeat (5) @(posedge clk);
        rst = ~`KLDJ_RSTABLE;

        // Run for a fixed number of cycles
        $display("");
        $display("Running irom-v2 program...");
        repeat (20000) @(posedge clk);

        // Display performance counters
        $display("");
        $display("==============================================");
        $display("  Performance Counters");
        $display("==============================================");
        $display("");
        $display("  cycle_count           = %0d", perf_cycle_count);
        $display("  instret_count         = %0d", perf_instret_count);
        $display("  frontend_stall_count  = %0d", perf_frontend_stall_count);
        $display("  load_use_stall_count  = %0d", perf_load_use_stall_count);
        $display("  mul_stall_count       = %0d", perf_mul_stall_count);
        $display("  div_stall_count       = %0d", perf_div_stall_count);
        $display("  redirect_count        = %0d", perf_redirect_count);
        $display("  load_count            = %0d", perf_load_count);
        $display("  store_count           = %0d", perf_store_count);

        // Derived metrics
        $display("");
        $display("==============================================");
        $display("  Derived Metrics");
        $display("==============================================");
        $display("");

        if (perf_instret_count > 0) begin
            $display("  CPI  = cycle / instret = %0d / %0d = %0d.%03d",
                     perf_cycle_count, perf_instret_count,
                     perf_cycle_count / perf_instret_count,
                     ((perf_cycle_count * 1000) / perf_instret_count) % 1000);
            $display("  IPC  = instret / cycle = %0d / %0d = %0d.%03d",
                     perf_instret_count, perf_cycle_count,
                     perf_instret_count / perf_cycle_count,
                     ((perf_instret_count * 1000) / perf_cycle_count) % 1000);
        end else begin
            $display("  CPI  = N/A (no instructions committed)");
        end

        if (perf_cycle_count > 0) begin
            $display("");
            $display("  load_use_stall / cycle = %0d / %0d = %0d.%03d%%",
                     perf_load_use_stall_count, perf_cycle_count,
                     (perf_load_use_stall_count * 100) / perf_cycle_count,
                     ((perf_load_use_stall_count * 100000) / perf_cycle_count) % 1000);
            $display("  mul_stall / cycle      = %0d / %0d = %0d.%03d%%",
                     perf_mul_stall_count, perf_cycle_count,
                     (perf_mul_stall_count * 100) / perf_cycle_count,
                     ((perf_mul_stall_count * 100000) / perf_cycle_count) % 1000);
            $display("  div_stall / cycle      = %0d / %0d = %0d.%03d%%",
                     perf_div_stall_count, perf_cycle_count,
                     (perf_div_stall_count * 100) / perf_cycle_count,
                     ((perf_div_stall_count * 100000) / perf_cycle_count) % 1000);
            $display("  frontend_stall / cycle = %0d / %0d = %0d.%03d%%",
                     perf_frontend_stall_count, perf_cycle_count,
                     (perf_frontend_stall_count * 100) / perf_cycle_count,
                     ((perf_frontend_stall_count * 100000) / perf_cycle_count) % 1000);
        end

        if (perf_instret_count > 0) begin
            $display("");
            $display("  redirect / instret     = %0d / %0d = %0d.%03d",
                     perf_redirect_count, perf_instret_count,
                     perf_redirect_count / perf_instret_count,
                     ((perf_redirect_count * 1000) / perf_instret_count) % 1000);
            $display("  (load+store) / instret = %0d / %0d = %0d.%03d",
                     perf_load_count + perf_store_count, perf_instret_count,
                     (perf_load_count + perf_store_count) / perf_instret_count,
                     (((perf_load_count + perf_store_count) * 1000) / perf_instret_count) % 1000);
        end

        $display("");
        $display("==============================================");
        $display("  Done.");
        $display("==============================================");
        $finish;
    end

    // Timeout safety net
    initial begin
        #3000000;
        $display("[TIMEOUT] Simulation exceeded time limit.");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("KLDJ_irom_v2_tb.vcd");
        $dumpvars(0, KLDJ_irom_v2_tb);
    end

endmodule
