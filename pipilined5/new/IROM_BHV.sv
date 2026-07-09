`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module Name: IROM_BHV
// Description: IROM Behavioral Model (simulation only)
//   - Combinational read, 4096 x 32-bit
//   - Loads from irom_v2.hex via $readmemh
//   - Interface compatible with Xilinx dist_mem_gen IROM IP
//////////////////////////////////////////////////////////////////////////////

module IROM (
    input  wire [11:0]  a,
    output wire [31:0]  spo
);

    reg [31:0] rom [0:4095];

    initial begin
        $readmemh("irom_v2.hex", rom);
    end

    assign spo = rom[a];

endmodule
