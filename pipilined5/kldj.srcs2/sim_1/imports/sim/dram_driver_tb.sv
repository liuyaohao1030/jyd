`timescale 1ns / 1ps

module dram_driver_tb;

    logic        clk = 1'b0;
    logic [17:0] perip_addr = 18'd0;
    logic [31:0] perip_wdata = 32'd0;
    logic [3:0]  perip_be = 4'd0;
    logic        dram_wen = 1'b0;
    logic [31:0] perip_rdata;

    integer pass_count = 0;
    integer fail_count = 0;

    localparam [17:0] ADDR_A = 18'h00100;
    localparam [17:0] ADDR_B = 18'h00104;

    always #5 clk = ~clk;

    dram_driver u_dut (
        .clk        (clk),
        .perip_addr (perip_addr),
        .perip_wdata(perip_wdata),
        .perip_be   (perip_be),
        .dram_wen   (dram_wen),
        .perip_rdata(perip_rdata)
    );

    // Drive one request per cycle at the falling edge so all inputs are
    // stable before the driver's rising-edge sampling point.
    task automatic request(
        input logic        wen,
        input logic [17:0] addr,
        input logic [31:0] wdata,
        input logic [3:0]  be
    );
        begin
            @(negedge clk);
            dram_wen   = wen;
            perip_addr = addr;
            perip_wdata = wdata;
            perip_be   = be;
        end
    endtask

    // Read after the NBA updates have settled by checking at the falling
    // edge following the request's sampling edge.
    task automatic expect_response(
        input logic [31:0] expected,
        input logic        expected_forward,
        input [511:0]      test_name
    );
        begin
            @(negedge clk);
            if ((perip_rdata === expected) &&
                (u_dut.fwd_r === expected_forward)) begin
                $display("[PASS] %0s: data=0x%08x fwd=%0b",
                         test_name, perip_rdata, u_dut.fwd_r);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: data=0x%08x (expected 0x%08x), fwd=%0b (expected %0b)",
                         test_name, perip_rdata, expected,
                         u_dut.fwd_r, expected_forward);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task automatic read_expect(
        input logic [17:0] addr,
        input logic [31:0] expected,
        input logic        expected_forward,
        input [511:0]      test_name
    );
        begin
            request(1'b0, addr, 32'd0, 4'b0000);
            expect_response(expected, expected_forward, test_name);
        end
    endtask

    initial begin
        $display("==============================================");
        $display("  DRAM driver / store-forward testbench");
        $display("==============================================");

        // The production driver has no reset.  A few idle sampling edges make
        // its output select registers known before checking it.
        repeat (3) @(negedge clk);
        if (^perip_rdata === 1'bx) begin
            $display("[FAIL] idle initialization left perip_rdata unknown");
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] idle initialization: data=0x%08x", perip_rdata);
            pass_count = pass_count + 1;
        end

        // Full-word store followed immediately by a same-address load.
        request(1'b1, ADDR_A, 32'h11223344, 4'b1111);
        read_expect(ADDR_A, 32'h11223344, 1'b1,
                    "SW -> next-cycle same-address load");

        // Once the store buffer expires, the same value must come from BRAM.
        request(1'b0, ADDR_B, 32'd0, 4'b0000);
        read_expect(ADDR_A, 32'h11223344, 1'b0,
                    "full-word value after buffer expiry");

        // Byte lane 2 merge: untouched bytes must come from BRAM.
        request(1'b1, ADDR_A, 32'h00AA0000, 4'b0100);
        read_expect(ADDR_A, 32'h11AA3344, 1'b1,
                    "byte lane 2 store-forward merge");
        request(1'b0, ADDR_B, 32'd0, 4'b0000);
        read_expect(ADDR_A, 32'h11AA3344, 1'b0,
                    "byte lane 2 committed to BRAM");

        // Lower and upper halfword byte enables.
        request(1'b1, ADDR_A, 32'h0000BEEF, 4'b0011);
        read_expect(ADDR_A, 32'h11AABEEF, 1'b1,
                    "lower-half store-forward merge");
        request(1'b1, ADDR_A, 32'hCAFE0000, 4'b1100);
        read_expect(ADDR_A, 32'hCAFEBEEF, 1'b1,
                    "upper-half store-forward merge");

        // Initialize B, then keep a pending write to A while reading B.  No
        // bytes from the A store are allowed to leak into the B response.
        request(1'b1, ADDR_B, 32'h55667788, 4'b1111);
        read_expect(ADDR_B, 32'h55667788, 1'b1,
                    "initialize second address");
        request(1'b1, ADDR_A, 32'hDEADBEEF, 4'b1111);
        read_expect(ADDR_B, 32'h55667788, 1'b0,
                    "pending store A does not forward to load B");

        // Consecutive stores replace the one-entry buffer, while the older
        // write is already committed and remains readable from BRAM.
        request(1'b1, ADDR_A, 32'h01020304, 4'b1111);
        request(1'b1, ADDR_B, 32'hA0B0C0D0, 4'b1111);
        read_expect(ADDR_A, 32'h01020304, 1'b0,
                    "older consecutive store committed before load");
        read_expect(ADDR_B, 32'hA0B0C0D0, 1'b0,
                    "newer consecutive store committed before load");

        $display("==============================================");
        $display("  %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        if (fail_count == 0) begin
            $display("  *** DRAM DRIVER TEST PASSED ***");
            $finish;
        end else begin
            $fatal(1, "DRAM driver test failed");
        end
    end

    initial begin
        #10000;
        $fatal(1, "DRAM driver test timeout");
    end

endmodule
