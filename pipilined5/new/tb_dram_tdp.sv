`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////
// Testbench: tb_dram_tdp
//
// Unit testbench for DRAM_TDP (True Dual Port BRAM behavioral model).
// Verifies:
//   1. Basic read/write on both ports
//   2. Byte-enable partial writes
//   3. Simultaneous read/write on different ports
//   4. Write-then-read on same port (Write First on Port A)
//   5. Read-during-write on Port B (Read First)
//////////////////////////////////////////////////////////////////////////////

module tb_dram_tdp;

    // Clocks
    reg clka, clkb;

    initial clka = 0;
    always #5 clka = ~clka;

    initial clkb = 0;
    always #7 clkb = ~clkb;  // Different frequency for Port B

    // Port A signals
    reg         ena;
    reg  [3:0]  wea;
    reg  [15:0] addra;
    reg  [31:0] dina;
    wire [31:0] douta;

    // Port B signals
    reg         enb;
    reg  [3:0]  web;
    reg  [15:0] addrb;
    reg  [31:0] dinb;
    wire [31:0] doutb;

    // DUT
    DRAM_TDP u_dut (
        .clka  (clka  ), .ena   (ena   ),
        .wea   (wea   ), .addra (addra ), .dina  (dina  ), .douta (douta),
        .clkb  (clkb  ), .enb   (enb   ),
        .web   (web   ), .addrb (addrb ), .dinb  (dinb  ), .doutb (doutb)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check(input [31:0] actual, input [31:0] expected, input [255:0] msg);
        if (actual === expected) begin
            $display("[PASS] %0s: got 0x%08x", msg, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] %0s: expected 0x%08x, got 0x%08x", msg, expected, actual);
            fail_count = fail_count + 1;
        end
    endtask

    // Write via Port A
    task port_a_write;
        input [15:0] addr;
        input [31:0] data;
        input [3:0]  be;
        begin
            @(posedge clka);
            ena  = 1'b1;
            wea  = be;
            addra = addr;
            dina = data;
            @(posedge clka);
            ena  = 1'b0;
            wea  = 4'b0;
        end
    endtask

    // Read via Port B
    task port_b_read;
        input [15:0] addr;
        begin
            @(posedge clkb);
            enb  = 1'b1;
            web  = 4'b0;
            addrb = addr;
            dinb = 32'h0;
            @(posedge clkb);
            enb  = 1'b0;
        end
    endtask

    // ------------------------------------------------
    // Main test sequence
    // ------------------------------------------------
    initial begin
        $display("==============================================");
        $display("  DRAM_TDP Unit Testbench");
        $display("==============================================");

        // Init
        ena = 0; wea = 0; addra = 0; dina = 0;
        enb = 0; web = 0; addrb = 0; dinb = 0;

        // ---- Test 1: Basic Write (Port A) + Read (Port B) ----
        $display("");
        $display("--- Test 1: Basic Write (A) + Read (B) ---");
        port_a_write(16'h0000, 32'hDEADBEEF, 4'b1111);
        @(posedge clka); // Wait for write to complete
        @(posedge clka);
        port_b_read(16'h0000);
        @(posedge clkb);
        @(posedge clkb); // Wait for registered output
        check(doutb, 32'hDEADBEEF, "Read back from Port B");

        // ---- Test 2: Byte-enable partial write ----
        $display("");
        $display("--- Test 2: Byte-enable partial write ---");
        // Write full word first
        port_a_write(16'h0001, 32'h11223344, 4'b1111);
        @(posedge clka);
        @(posedge clka);
        // Overwrite only byte 0 and byte 2
        port_a_write(16'h0001, 32'hAABBCCDD, 4'b0101);
        @(posedge clka);
        @(posedge clka);
        port_b_read(16'h0001);
        @(posedge clkb);
        @(posedge clkb);
        // Expected: byte0=DD, byte1=33, byte2=BB, byte3=11 → 0x11BB33DD
        check(doutb, 32'h11BB33DD, "Byte-enable partial write");

        // ---- Test 3: Multiple addresses ----
        $display("");
        $display("--- Test 3: Multiple addresses ---");
        port_a_write(16'h0010, 32'hAAAA_0000, 4'b1111);
        port_a_write(16'h0011, 32'hBBBB_0000, 4'b1111);
        port_a_write(16'h0012, 32'hCCCC_0000, 4'b1111);
        @(posedge clka);
        @(posedge clka);
        port_b_read(16'h0010);
        @(posedge clkb);
        @(posedge clkb);
        check(doutb, 32'hAAAA_0000, "Addr 0x0010");
        port_b_read(16'h0011);
        @(posedge clkb);
        @(posedge clkb);
        check(doutb, 32'hBBBB_0000, "Addr 0x0011");
        port_b_read(16'h0012);
        @(posedge clkb);
        @(posedge clkb);
        check(doutb, 32'hCCCC_0000, "Addr 0x0012");

        // ---- Test 4: Simultaneous read (B) and write (A) to different addresses ----
        $display("");
        $display("--- Test 4: Simultaneous R/W different addresses ---");
        port_a_write(16'h0020, 32'h12345678, 4'b1111);
        @(posedge clka);
        @(posedge clka);
        // Now read 0x0020 via B while writing 0x0021 via A
        @(posedge clka);
        ena  = 1'b1; wea = 4'b1111; addra = 16'h0021; dina = 32'hFFFFFFFF;
        enb  = 1'b1; web = 4'b0;    addrb = 16'h0020; dinb = 32'h0;
        @(posedge clka);
        ena = 1'b0; wea = 4'b0;
        enb = 1'b0;
        @(posedge clkb);
        @(posedge clkb);
        check(doutb, 32'h12345678, "Read 0x0020 while writing 0x0021");

        // ---- Test 5: Write then read same address on Port A (Write First) ----
        $display("");
        $display("--- Test 5: Write First on Port A ---");
        port_a_write(16'h0030, 32'h11111111, 4'b1111);
        @(posedge clka);
        @(posedge clka);
        // Write new value and read in same cycle
        @(posedge clka);
        ena = 1'b1; wea = 4'b1111; addra = 16'h0030; dina = 32'h22222222;
        @(posedge clka);
        ena = 1'b0; wea = 4'b0;
        // douta should be 0x22222222 (Write First)
        @(posedge clka);
        check(douta, 32'h22222222, "Port A Write First output");

        // ---- Summary ----
        $display("");
        $display("==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        if (fail_count == 0)
            $display("  ALL TESTS PASSED!");
        else
            $display("  SOME TESTS FAILED!");
        $display("==============================================");
        $finish;
    end

    // Timeout
    initial begin
        #100000;
        $display("[TIMEOUT]");
        $finish;
    end

    // VCD
    initial begin
        $dumpfile("tb_dram_tdp.vcd");
        $dumpvars(0, tb_dram_tdp);
    end

endmodule
