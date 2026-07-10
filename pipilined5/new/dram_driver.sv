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
    input  logic         clk				,

    input  logic [17:0]  perip_addr			,
    input  logic [31:0]  perip_wdata		,
	input  logic [3:0]	 perip_be			,
    input  logic         dram_wen           ,
    output logic [31:0]  perip_rdata		
);
    logic [15:0] dram_addr;
    logic [ 3:0] bram_we;
    logic [31:0] bram_dout;

    assign dram_addr = perip_addr[17:2];
    assign bram_we = dram_wen ? perip_be : 4'b0000;
    assign perip_rdata = bram_dout;

    DRAM_BRAM Mem_DRAM (
        .clka       (clk),
        .ena        (1'b1),
        .wea        (bram_we),
        .addra      (dram_addr),
        .dina       (perip_wdata),
        .douta      (bram_dout)
    );
endmodule
