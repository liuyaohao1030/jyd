`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:13 PM
// Design Name: 
// Module Name: student_top
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


module student_top#(
    parameter                           P_SW_CNT            = 64,
    parameter                           P_LED_CNT           = 32,
    parameter                           P_SEG_CNT           = 40,
    parameter                           P_KEY_CNT           = 8
) (
    input                                       w_cpu_clk     ,
    input                                       w_clk_50Mhz   ,
    input                                       w_clk_rst     ,
    input  [P_KEY_CNT - 1:0]                    virtual_key   ,
    input  [P_SW_CNT  - 1:0]                    virtual_sw    ,

    output [P_LED_CNT - 1:0]                    virtual_led   ,
    output [P_SEG_CNT - 1:0]                    virtual_seg   
);

    // IROM
    logic [31:0] pc;
    logic [11:0] inst_addr;
    logic [31:0] instruction;

    // perip
    logic [31:0] perip_addr, perip_wdata, perip_rdata;
    logic perip_wen;
    logic [1:0] perip_mask;
    logic [3:0] cpu_mem_be; // 接收 KLDJ_top 的 4-bit 掩码

    // 16KB = 2^12 * 32bit
    assign inst_addr = pc[13:2];

    KLDJ_top u_KLDJ_top (
    .clk            (w_cpu_clk),
    .rst            (w_clk_rst),
    
    .tb_if_inst     (instruction),
    .tb_if_pc       (pc),
    
    .mem_addr       (perip_addr),
    .mem_wdata      (perip_wdata),
    .mem_we         (perip_wen),
    .mem_be         (cpu_mem_be), 
    .mem_rdata      (perip_rdata),
    
    .tb_ex_jump     (),
    .tb_ex_jump_pc  (),
    .tb_ex_res      (),
    .core_clk_o     ()
);

    // 2'b10: Word, 2'b01: Halfword, 2'b00: Byte
    assign perip_mask = (cpu_mem_be == 4'b1111) ? 2'b10 :
                        (cpu_mem_be == 4'b0011 || cpu_mem_be == 4'b1100) ? 2'b01 : 
                        2'b00;

    IROM Mem_IROM (
        .a          (inst_addr),
        .spo        (instruction)
    );
    
    perip_bridge bridge_inst (
        .clk				(w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst                (w_clk_rst),
        .perip_addr			(perip_addr),
        .perip_wdata		(perip_wdata),
        .perip_wen			(perip_wen),
        .perip_mask			(perip_mask),
        .perip_rdata		(perip_rdata),
        .virtual_sw_input	(virtual_sw),
        .virtual_key_input	(virtual_key),	
        .virtual_seg_output	(virtual_seg),
        .virtual_led_output (virtual_led)
    );

endmodule
