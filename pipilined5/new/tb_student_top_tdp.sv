`timescale 1ns / 1ps
`include "define.v"

//////////////////////////////////////////////////////////////////////////////
// Testbench: tb_student_top_tdp
//
// Full-system testbench for True Dual Port BRAM verification.
// Instantiates student_top with behavioral IROM and DRAM_TDP models.
// Loads irom-v2 test program and checks for correct execution.
//
// Usage:
//   1. Copy irom_v2.hex to simulation working directory
//   2. Run: xvlog -sv tb_student_top_tdp.sv IROM_BHV.sv DRAM_TDP.sv \
//              dram_driver.sv perip_bridge.sv student_top.sv ...
//   3. Run: xelab -debug all tb_student_top_tdp -s sim
//   4. Run: xsim sim -runall
//////////////////////////////////////////////////////////////////////////////

module tb_student_top_tdp;

    // ------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------
    reg         clk;
    reg         clk_50m;
    reg         rst;

    initial clk = 0;
    always #5 clk = ~clk;       // 100 MHz

    initial clk_50m = 0;
    always #10 clk_50m = ~clk_50m;  // 50 MHz

    // ------------------------------------------------
    // I/O
    // ------------------------------------------------
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    // ------------------------------------------------
    // DUT: student_top with behavioral models
    // Note: This testbench requires that student_top's
    // IROM and DRAM instances use behavioral models
    // (IROM_BHV and DRAM_TDP) instead of Vivado IPs.
    // See the Vivado guide for how to set this up.
    // ------------------------------------------------

    // Instruction memory (behavioral)
    reg [31:0] inst_mem [0:4095];
    wire [31:0] pc;
    wire [11:0] inst_addr = pc[13:2];
    wire [31:0] instruction;
    assign instruction = inst_mem[inst_addr];

    // Data memory interface
    wire [31:0] perip_addr, perip_wdata, perip_rdata;
    wire        perip_wen;
    wire [3:0]  cpu_mem_be;

    // DUT
    KLDJ_top u_KLDJ_top (
        .clk            (clk),
        .rst            (rst),
        .tb_if_inst     (instruction),
        .tb_if_pc       (pc),
        .mem_addr       (perip_addr),
        .mem_wdata      (perip_wdata),
        .mem_we         (perip_wen),
        .mem_be         (cpu_mem_be),
        .mem_rdata      (perip_rdata),
        .tb_ex_jump     (),
        .tb_ex_jump_pc  (),
        .tb_ex_res      (),
        .core_clk_o     ()
    );

    // DRAM via perip_bridge (uses dram_driver → DRAM_TDP)
    perip_bridge bridge_inst (
        .clk                (clk),
        .cnt_clk            (clk_50m),
        .rst                (rst),
        .perip_addr         (perip_addr),
        .perip_wdata        (perip_wdata),
        .perip_wen          (perip_wen),
        .perip_be           (cpu_mem_be),
        .perip_rdata        (perip_rdata),
        .virtual_sw_input   (64'h0),
        .virtual_key_input  (8'h0),
        .virtual_seg_output (virtual_seg),
        .virtual_led_output (virtual_led)
    );

    // ------------------------------------------------
    // Monitor DRAM writes for verification
    // ------------------------------------------------
    wire        is_dram_write = perip_wen &&
                    (perip_addr >= 32'h8010_0000) &&
                    (perip_addr < 32'h8014_0000);
    wire [15:0] dram_wr_addr = perip_addr[17:2];

    always @(posedge clk) begin
        if (is_dram_write) begin
            $display("[%0t] DRAM WRITE: addr=0x%08x data=0x%08x be=%b",
                     $time, perip_addr, perip_wdata, cpu_mem_be);
        end
    end

    // ------------------------------------------------
    // Monitor LED output for test results
    // ------------------------------------------------
    always @(posedge clk) begin
        if (virtual_led != 32'h0) begin
            $display("[%0t] LED changed: 0x%08x", $time, virtual_led);
        end
    end

    // ------------------------------------------------
    // Main
    // ------------------------------------------------
    initial begin
        $display("==============================================");
        $display("  True Dual Port BRAM - Full System Testbench");
        $display("==============================================");

        // Load instruction memory
        $readmemh("irom_v2.hex", inst_mem);

        // Reset
        rst = `KLDJ_RSTABLE;
        repeat (10) @(posedge clk);
        rst = ~`KLDJ_RSTABLE;

        $display("");
        $display("Running irom-v2 program with True Dual Port BRAM...");
        $display("");

        // Run for enough cycles
        repeat (50000) @(posedge clk);

        $display("");
        $display("==============================================");
        $display("  Simulation Complete");
        $display("==============================================");
        $display("  LED = 0x%08x", virtual_led);
        $display("==============================================");
        $finish;
    end

    // Timeout
    initial begin
        #10000000;
        $display("[TIMEOUT] Simulation exceeded time limit.");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("tb_student_top_tdp.vcd");
        $dumpvars(0, tb_student_top_tdp);
    end

endmodule
