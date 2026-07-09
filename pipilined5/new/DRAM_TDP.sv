`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module Name: DRAM_TDP
// Description: True Dual Port BRAM Behavioral Model (simulation only)
//
//   Port A: Write First mode, byte-enable
//   Port B: Read First mode
//   65536 x 32-bit = 256KB, 16-bit address, 4-bit byte enable
//   Interface compatible with Xilinx blk_mem_gen True Dual Port IP
//
//   For synthesis, replace with actual Vivado blk_mem_gen IP (DRAM_TDP).
//   This behavioral model is functionally equivalent for simulation.
//////////////////////////////////////////////////////////////////////////////

module DRAM_TDP (
    // Port A
    input  wire         clka,
    input  wire         ena,
    input  wire [3:0]   wea,
    input  wire [15:0]  addra,
    input  wire [31:0]  dina,
    output reg  [31:0]  douta,

    // Port B
    input  wire         clkb,
    input  wire         enb,
    input  wire [3:0]   web,
    input  wire [15:0]  addrb,
    input  wire [31:0]  dinb,
    output reg  [31:0]  doutb
);

    // 65536 words x 32 bits
    reg [31:0] mem [0:65535];

    // Initialize to zero
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 32'h0;
    end

    // ------------------------------------------------------------
    // Port A: Write First
    //   - Write: merge new bytes with old word using byte-enable
    //   - Read:  output the newly written word (Write First)
    // Uses blocking assignments so the write completes before the
    // read statement sees the updated value.
    // ------------------------------------------------------------
    always @(posedge clka) begin
        if (ena) begin
            if (wea[0]) mem[addra][ 7: 0] = dina[ 7: 0];
            if (wea[1]) mem[addra][15: 8] = dina[15: 8];
            if (wea[2]) mem[addra][23:16] = dina[23:16];
            if (wea[3]) mem[addra][31:24] = dina[31:24];
            douta = mem[addra];
        end
    end

    // ------------------------------------------------------------
    // Port B: Read First
    //   - Read:  output the old word before any write
    //   - Write: merge new bytes with old word using byte-enable
    // Uses non-blocking assignment for the read so it captures the
    // value before the blocking write updates memory.
    // ------------------------------------------------------------
    always @(posedge clkb) begin
        if (enb) begin
            doutb <= mem[addrb];  // Non-blocking: samples old value
            if (web[0]) mem[addrb][ 7: 0] = dinb[ 7: 0];
            if (web[1]) mem[addrb][15: 8] = dinb[15: 8];
            if (web[2]) mem[addrb][23:16] = dinb[23:16];
            if (web[3]) mem[addrb][31:24] = dinb[31:24];
        end
    end

endmodule
