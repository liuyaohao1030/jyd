`timescale 1ns/1ps
`include "define.v"

module tb_full_system;

    // Clock & Reset
    reg clk_cpu;
    reg rst_n;  // active-HIGH: 1=reset, 0=run

    initial clk_cpu = 0;
    always #5 clk_cpu = ~clk_cpu;

    // Virtual I/O
    wire [7:0]  virtual_key = 8'h00;
    wire [63:0] virtual_sw  = 64'h0;
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    // DUT
    student_top u_student_top (
        .w_cpu_clk     (clk_cpu),
        .w_clk_50Mhz   (clk_cpu),
        .w_clk_rst     (rst_n),
        .virtual_key   (virtual_key),
        .virtual_sw    (virtual_sw),
        .virtual_led   (virtual_led),
        .virtual_seg   (virtual_seg)
    );

    // CPU signals
    wire [31:0] cpu_pc     = u_student_top.pc;
    wire [31:0] cpu_inst   = u_student_top.instruction;
    wire [31:0] mem_addr   = u_student_top.perip_addr;
    wire [31:0] mem_wdata  = u_student_top.perip_wdata;
    wire        mem_we     = u_student_top.perip_wen;
    wire [3:0]  mem_be     = u_student_top.cpu_mem_be;
    wire [31:0] mem_rdata  = u_student_top.perip_rdata;

    // DRAM signals
    wire        is_dram_addr = u_student_top.bridge_inst.is_dram_addr;
    wire        rd_is_dram_q = u_student_top.bridge_inst.rd_is_dram_q;
    wire [1:0]  buf_valid_sr = u_student_top.bridge_inst.dram_driver_inst.buf_valid_sr;
    wire        fwd_r        = u_student_top.bridge_inst.dram_driver_inst.fwd_r;
    wire [31:0] bram_dout    = u_student_top.bridge_inst.dram_driver_inst.bram_dout;
    wire [31:0] dram_rdata   = u_student_top.bridge_inst.dram_driver_inst.perip_rdata;

    // CPU pipeline
    wire        ex_valid = u_student_top.u_KLDJ_top.id_ex_valid;
    wire [31:0] ex_pc    = u_student_top.u_KLDJ_top.id_ex_pc;
    wire        is_ecall = u_student_top.u_KLDJ_top.is_ecall;
    wire        is_mret  = u_student_top.u_KLDJ_top.is_mret;
    wire        load_use_stall = u_student_top.u_KLDJ_top.load_use_stall;

    // Counters
    integer cycle_count;
    integer store_count, load_count, fwd_count;
    reg [31:0] last_pc;
    integer    pc_stuck_count;

    // DRAM write tracking
    reg        prev_dram_wen;
    reg [31:0] prev_dram_addr;
    reg [31:0] prev_dram_data;

    wire dram_wen = u_student_top.bridge_inst.perip_wen && u_student_top.bridge_inst.is_dram_addr;

    always @(posedge clk_cpu) begin
        if (rst_n == 0) begin  // CPU running (rst_n=0 means reset released)
            cycle_count <= cycle_count + 1;

            // Progress report every 200000 cycles
            if (cycle_count % 200000 == 0 && cycle_count > 0) begin
                $display("[%0d] Progress: PC=%h, stores=%0d, loads=%0d, fwds=%0d",
                         cycle_count, cpu_pc, store_count, load_count, fwd_count);
            end

            // ECALL/MRET detection
            if (ex_valid && is_ecall)
                $display("[%0d] ECALL at PC=%h", cycle_count, ex_pc);
            if (ex_valid && is_mret)
                $display("[%0d] MRET at PC=%h", cycle_count, ex_pc);

            // Track stores to DRAM
            if (dram_wen) begin
                store_count <= store_count + 1;
                prev_dram_wen  <= 1;
                prev_dram_addr <= {14'h0, u_student_top.bridge_inst.dram_driver_inst.bram_addr_r, 2'b00};
                prev_dram_data <= u_student_top.bridge_inst.dram_driver_inst.bram_din_r;
            end else begin
                prev_dram_wen <= 0;
            end

            // Track loads from DRAM
            if (rd_is_dram_q && !mem_we) begin
                load_count <= load_count + 1;
            end

            // Track forwarding
            if (fwd_r) begin
                fwd_count <= fwd_count + 1;
            end

            // PC stuck detection
            if (cpu_pc == last_pc && cpu_pc != 0 && !load_use_stall) begin
                pc_stuck_count <= pc_stuck_count + 1;
                if (pc_stuck_count == 5000) begin
                    $display("[%0d] *** PC STUCK at %h for 5000 cycles! ***", cycle_count, cpu_pc);
                    $display("[%0d] mem_addr=%h, mem_we=%b, mem_rdata=%h, ex_valid=%b",
                             cycle_count, mem_addr, mem_we, mem_rdata, ex_valid);
                    $display("[%0d] inst=%h, is_ecall=%b, is_mret=%b, load_use_stall=%b",
                             cycle_count, cpu_inst, is_ecall, is_mret, load_use_stall);
                    $display("[%0d] fwd_r=%b, buf_valid_sr=%b, rd_is_dram_q=%b",
                             cycle_count, fwd_r, buf_valid_sr, rd_is_dram_q);
                end
            end else begin
                pc_stuck_count <= 0;
            end
            last_pc <= cpu_pc;
        end
    end

    // Main
    initial begin
        $display("==============================================");
        $display("  Full System irom-v2 Simulation");
        $display("==============================================");

        cycle_count = 0;
        store_count = 0;
        load_count = 0;
        fwd_count = 0;
        pc_stuck_count = 0;
        last_pc = 0;
        prev_dram_wen = 0;

        // Reset
        rst_n = 1;
        repeat (20) @(posedge clk_cpu);
        rst_n = 0;
        $display("Reset released at cycle %0d", cycle_count);
        $display("");

        // Run
        repeat (500000) @(posedge clk_cpu);

        $display("");
        $display("==============================================");
        $display("  Simulation Complete");
        $display("==============================================");
        $display("  Total cycles:  %0d", cycle_count);
        $display("  Store count:   %0d", store_count);
        $display("  Load count:    %0d", load_count);
        $display("  Forward count: %0d", fwd_count);
        $display("  Final PC:      %h", cpu_pc);
        $display("==============================================");

        $finish;
    end

    // Timeout
    initial begin
        #2400000000;
        $display("[TIMEOUT]");
        $finish;
    end

    // VCD
    initial begin
        $dumpfile("tb_full_system.vcd");
        $dumpvars(0, tb_full_system);
    end

endmodule
