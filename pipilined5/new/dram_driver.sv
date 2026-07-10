`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: dram_driver
// Description: DRAM driver with True Dual Port BRAM (Optimized for timing)
//
//   Port A: Write path - DIRECT connection (no register), 1-cycle latency
//   Port B: Read path  - combinational address, isolated from write path
//
//   Write latency: 1 cycle (BRAM only) - same as original single-port design
//   Read latency:  1 cycle (BRAM registered output)
//
//   Strategy: Use TDP to physically separate read and write paths, allowing
//   synthesis tool to optimize each independently without adding write latency.
//   No store buffer or forwarding needed since write completes in 1 cycle.
//////////////////////////////////////////////////////////////////////////////////

module dram_driver(
    input  logic         clk            ,
    input  logic [17:0]  perip_addr     ,
    input  logic [31:0]  perip_wdata    ,
    input  logic [3:0]   perip_be       ,
    input  logic         dram_wen       ,
    output logic [31:0]  perip_rdata
);

    // ================================================================
    // Address and control signals - direct connection for write
    // ================================================================
    logic [15:0] bram_addr;
    logic [ 3:0] bram_we;

    assign bram_addr = perip_addr[17:2];
    assign bram_we   = dram_wen ? perip_be : 4'b0000;

    // ================================================================
    // True Dual Port BRAM instantiation
    //   Port A: Write (direct connection, maintains 1-cycle write latency)
    //   Port B: Read  (separate port, breaks read critical path)
    //
    //   The dual-port architecture physically separates read and write
    //   paths in the BRAM fabric, allowing better timing optimization
    //   without compromising write latency.
    // ================================================================
    logic [31:0] bram_dout;

    DRAM_TDP u_dram_tdp (
        // Port A: Write (direct, no extra registers)
        .clka   (clk          ),
        .wea    (bram_we      ),  // Direct write enable
        .addra  (bram_addr    ),  // Direct address
        .dina   (perip_wdata  ),  // Direct data
        .douta  (             ),  // Unused (write-only port)

        // Port B: Read (separate port for read optimization)
        .clkb   (clk          ),
        .web    (4'b0000      ),  // Read-only port
        .addrb  (bram_addr    ),  // Same address logic
        .dinb   (32'b0        ),
        .doutb  (bram_dout    )   // Read data output
    );

    assign perip_rdata = bram_dout;

endmodule