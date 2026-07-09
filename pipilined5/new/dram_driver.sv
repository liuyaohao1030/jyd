`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: dram_driver
// Description: DRAM driver with True Dual Port BRAM
//
//   Port A: Write path - registered (WEA/addr/data), breaks critical path
//   Port B: Read path  - combinational address, no extra read latency
//
//   Write latency: 1 cycle (register) + 0 cycles (BRAM) = 1 cycle total
//   Read latency:  0 cycles (address) + 1 cycle (BRAM registered) = 1 cycle
//   Read and write ports are independent, no mutual interference.
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
    // Write register bank: register write signals for 1 cycle
    // to break the critical path from EX stage to BRAM WEA
    // ================================================================
    logic [15:0] bram_addr_r;
    logic [ 3:0] bram_we_r;
    logic [31:0] bram_din_r;

    always @(posedge clk) begin
        bram_addr_r <= perip_addr[17:2];
        bram_we_r   <= dram_wen ? perip_be : 4'b0000;
        bram_din_r  <= perip_wdata;
    end

    // ================================================================
    // Read address: combinational, no extra read latency
    // ================================================================
    logic [15:0] bram_addr_rd;
    assign bram_addr_rd = perip_addr[17:2];

    // ================================================================
    // True Dual Port BRAM instantiation
    // ================================================================
    DRAM_TDP u_dram_tdp (
        // Port A: Write (registered inputs)
        .clka   (clk            ),
        .ena    (1'b1           ),
        .wea    (bram_we_r      ),  // 4-bit byte write enable (registered)
        .addra  (bram_addr_r    ),  // 16-bit address (registered)
        .dina   (bram_din_r     ),  // 32-bit data (registered)
        .douta  (               ),  // Port A output unused

        // Port B: Read (combinational address)
        .clkb   (clk            ),
        .enb    (1'b1           ),
        .web    (4'b0000        ),  // Port B read-only
        .addrb  (bram_addr_rd   ),  // 16-bit address (combinational)
        .dinb   (32'b0          ),  // Unused
        .doutb  (perip_rdata    )   // 32-bit read data
    );

endmodule
