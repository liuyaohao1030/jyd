`timescale 1ns/1ps

// ============================================================================
// Focused Testbench: Demonstrate dram_driver store-to-load forwarding timing bug
//
// This testbench directly drives the perip_bridge interface to test
// store-to-load forwarding behavior in the dram_driver.
// ============================================================================

module tb_timing_bug;

    reg clk;
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // Bridge interface signals
    reg         rst;
    reg  [31:0] perip_addr;
    reg  [31:0] perip_wdata;
    reg         perip_wen;
    reg  [3:0]  perip_be;
    wire [31:0] perip_rdata;

    reg  [63:0] virtual_sw;
    reg  [7:0]  virtual_key;
    wire [39:0] virtual_seg;
    wire [31:0] virtual_led;

    // Instantiate perip_bridge (which contains dram_driver)
    perip_bridge u_bridge (
        .clk                (clk),
        .cnt_clk            (clk),
        .rst                (rst),
        .perip_addr         (perip_addr),
        .perip_wdata        (perip_wdata),
        .perip_wen          (perip_wen),
        .perip_be           (perip_be),
        .perip_rdata        (perip_rdata),
        .virtual_sw_input   (virtual_sw),
        .virtual_key_input  (virtual_key),
        .virtual_seg_output (virtual_seg),
        .virtual_led_output (virtual_led)
    );

    // Internal signals for monitoring
    wire        dram_wen      = perip_wen && u_bridge.is_dram_addr;
    wire [15:0] bram_addr_r   = u_bridge.dram_driver_inst.bram_addr_r;
    wire [3:0]  bram_we_r     = u_bridge.dram_driver_inst.bram_we_r;
    wire [31:0] bram_din_r    = u_bridge.dram_driver_inst.bram_din_r;
    wire [1:0]  buf_valid_sr  = u_bridge.dram_driver_inst.buf_valid_sr;
    wire        fwd           = u_bridge.dram_driver_inst.fwd_comb;
    wire        fwd_r         = u_bridge.dram_driver_inst.fwd_r;
    wire [31:0] bram_dout     = u_bridge.dram_driver_inst.bram_dout;
    wire        rd_is_dram_q  = u_bridge.rd_is_dram_q;

    integer cycle;
    integer errors;

    task do_store(input [31:0] addr, input [31:0] data, input [3:0] be);
        @(posedge clk);
        perip_addr  <= addr;
        perip_wdata <= data;
        perip_wen   <= 1;
        perip_be    <= be;
        $display("[%0d] STORE: addr=%h, data=%h, be=%b", cycle, addr, data, be);
    endtask

    task do_load(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        perip_addr  <= addr;
        perip_wdata <= 0;
        perip_wen   <= 0;
        perip_be    <= 0;
        @(posedge clk);  // Wait for BRAM registered output
        @(posedge clk);  // Wait for bridge rd_is_dram_q pipeline
        data = perip_rdata;
        $display("[%0d] LOAD: addr=%h, got data=%h", cycle, addr, data);
    endtask

    task do_idle();
        @(posedge clk);
        perip_addr  <= 0;
        perip_wdata <= 0;
        perip_wen   <= 0;
        perip_be    <= 0;
    endtask

    // Test: store then immediate load to same address
    task test_store_load_same_addr();
        reg [31:0] rdata;
        begin
            $display("");
            $display("=== Test: Store then Load to same address (0x80100000) ===");

            // Store 0xDEADBEEF to address 0x80100000
            do_store(32'h80100000, 32'hDEADBEEF, 4'b1111);

            // Immediately load from same address (no idle cycles)
            @(posedge clk);
            perip_addr  <= 32'h80100000;
            perip_wdata <= 0;
            perip_wen   <= 0;
            perip_be    <= 0;

            // Monitor what happens in the next few cycles
            @(posedge clk);
            $display("[%0d] After load addr presented: fwd=%b, rd_is_dram_q=%b, bram_dout=%h, perip_rdata=%h",
                     cycle, fwd, rd_is_dram_q, bram_dout, perip_rdata);

            @(posedge clk);
            $display("[%0d] Next cycle: fwd=%b, rd_is_dram_q=%b, bram_dout=%h, perip_rdata=%h",
                     cycle, fwd, rd_is_dram_q, bram_dout, perip_rdata);

            @(posedge clk);
            $display("[%0d] Data captured: fwd=%b, rd_is_dram_q=%b, bram_dout=%h, perip_rdata=%h",
                     cycle, fwd, rd_is_dram_q, bram_dout, perip_rdata);

            if (perip_rdata == 32'hDEADBEEF) begin
                $display("PASS: Load got correct data 0xDEADBEEF");
            end else begin
                $display("FAIL: Expected 0xDEADBEEF, got 0x%h", perip_rdata);
                errors = errors + 1;
            end
        end
    endtask

    // Test: store then load with 1 idle cycle gap
    task test_store_load_1gap();
        reg [31:0] rdata;
        begin
            $display("");
            $display("=== Test: Store then Load with 1 idle cycle (0x80100004) ===");

            do_store(32'h80100004, 32'hCAFE0001, 4'b1111);
            do_idle();

            @(posedge clk);
            perip_addr  <= 32'h80100004;
            perip_wdata <= 0;
            perip_wen   <= 0;
            perip_be    <= 0;

            @(posedge clk);
            $display("[%0d] After load addr: fwd=%b, rd_is_dram_q=%b, bram_dout=%h",
                     cycle, fwd, rd_is_dram_q, bram_dout);

            @(posedge clk);
            $display("[%0d] Data cycle: fwd=%b, rd_is_dram_q=%b, bram_dout=%h, perip_rdata=%h",
                     cycle, fwd, rd_is_dram_q, bram_dout, perip_rdata);

            if (perip_rdata == 32'hCAFE0001) begin
                $display("PASS: Load got correct data");
            end else begin
                $display("FAIL: Expected 0xCAFE0001, got 0x%h", perip_rdata);
                errors = errors + 1;
            end
        end
    endtask

    // Test: store then load with 2 idle cycles gap
    task test_store_load_2gap();
        reg [31:0] rdata;
        begin
            $display("");
            $display("=== Test: Store then Load with 2 idle cycles (0x80100008) ===");

            do_store(32'h80100008, 32'h12345678, 4'b1111);
            do_idle();
            do_idle();

            @(posedge clk);
            perip_addr  <= 32'h80100008;
            perip_wdata <= 0;
            perip_wen   <= 0;
            perip_be    <= 0;

            @(posedge clk);
            @(posedge clk);
            $display("[%0d] Data: perip_rdata=%h", cycle, perip_rdata);

            if (perip_rdata == 32'h12345678) begin
                $display("PASS: Load got correct data");
            end else begin
                $display("FAIL: Expected 0x12345678, got 0x%h", perip_rdata);
                errors = errors + 1;
            end
        end
    endtask

    // Test: byte store then word load
    task test_byte_store_word_load();
        reg [31:0] rdata;
        begin
            $display("");
            $display("=== Test: Byte store then word load (0x8010000C) ===");

            // First store a known value
            do_store(32'h8010000C, 32'hFFFFFFFF, 4'b1111);
            do_idle();
            do_idle();

            // Then store just 1 byte
            do_store(32'h8010000C, 32'h000000AA, 4'b0001);
            do_idle();

            // Load the full word
            @(posedge clk);
            perip_addr  <= 32'h8010000C;
            perip_wdata <= 0;
            perip_wen   <= 0;
            perip_be    <= 0;

            @(posedge clk);
            @(posedge clk);
            $display("[%0d] Data: perip_rdata=%h", cycle, perip_rdata);

            if (perip_rdata == 32'hFFFFFFAA) begin
                $display("PASS: Load got correct data (byte updated)");
            end else begin
                $display("FAIL: Expected 0xFFFFFFAA, got 0x%h", perip_rdata);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("==============================================");
        $display("  dram_driver Store-to-Load Forwarding Test");
        $display("==============================================");

        cycle = 0;
        errors = 0;
        rst = 1;
        perip_addr = 0;
        perip_wdata = 0;
        perip_wen = 0;
        perip_be = 0;
        virtual_sw = 0;
        virtual_key = 0;

        repeat (10) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        test_store_load_same_addr();
        test_store_load_1gap();
        test_store_load_2gap();
        test_byte_store_word_load();

        $display("");
        $display("==============================================");
        $display("  Results: %0d errors", errors);
        $display("==============================================");

        $finish;
    end

    always @(posedge clk) begin
        if (!rst) cycle <= cycle + 1;
    end

    initial begin
        #100000;
        $display("[TIMEOUT]");
        $finish;
    end

    initial begin
        $dumpfile("tb_timing_bug.vcd");
        $dumpvars(0, tb_timing_bug);
    end

endmodule
