`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2025 11:42:01 AM
// Design Name: 
// Module Name: dram_driver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
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
