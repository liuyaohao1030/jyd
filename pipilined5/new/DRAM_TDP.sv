`timescale 1ns / 1ps

//=============================================================================
// DRAM_TDP - True Dual Port BRAM Behavioral Model (Simulation Only)
//=============================================================================
// Behavioral model for Vivado Block Memory Generator:
//   - True Dual Port RAM, 65536x32-bit
//   - Port A: Write First (registered write path)
//   - Port B: Read First
//   - 4-bit byte write enable
//
// Synthesis: Use Vivado Block Memory Generator IP (blk_mem_gen)
// Replace this file with the IP during synthesis.
//=============================================================================

module DRAM_TDP (
    // Port A: Write
    input  wire         clka,
    input  wire [3:0]   wea,
    input  wire [15:0]  addra,
    input  wire [31:0]  dina,
    output reg  [31:0]  douta,

    // Port B: Read
    input  wire         clkb,
    input  wire [3:0]   web,
    input  wire [15:0]  addrb,
    input  wire [31:0]  dinb,
    output reg  [31:0]  doutb
);

    // 65536 x 32-bit memory
    reg [31:0] mem [0:65535];

    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 32'h0;
    end

    // Port A: Write First (blocking assignments)
    // Write first: data written is read back on the same cycle
    always @(posedge clka) begin
        if (wea[0]) mem[addra][ 7: 0] = dina[ 7: 0];
        if (wea[1]) mem[addra][15: 8] = dina[15: 8];
        if (wea[2]) mem[addra][23:16] = dina[23:16];
        if (wea[3]) mem[addra][31:24] = dina[31:24];
        douta = mem[addra];
    end

    // Port B: Read First (non-blocking read, blocking write)
    // Read first: old data is read back on the same cycle, write takes effect next cycle
    always @(posedge clkb) begin
        doutb <= mem[addrb];
        if (web[0]) mem[addrb][ 7: 0] = dinb[ 7: 0];
        if (web[1]) mem[addrb][15: 8] = dinb[15: 8];
        if (web[2]) mem[addrb][23:16] = dinb[23:16];
        if (web[3]) mem[addrb][31:24] = dinb[31:24];
    end

endmodule
