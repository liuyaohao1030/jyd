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
    logic [31:0] perip_addr, perip_wdata, perip_rdata, cpu_mem_addr;
    logic perip_wen;
    logic [1:0] perip_mask;
    logic [3:0] cpu_mem_be;

// 1. 将 CPU 的 4-bit 掩码转换为 SoC 的 2-bit perip_mask
// 4'b1111(字) -> 2'b10; 4'b0011 或 4'b1100(半字) -> 2'b01; 其余(字节) -> 2'b00
    assign perip_mask = (cpu_mem_be == 4'b1111) ? 2'b10 :
                        ((cpu_mem_be == 4'b0011) || (cpu_mem_be == 4'b1100)) ? 2'b01 : 
                        2'b00;

// 2. 强行把地址的低 2 位抹零给外设总线
// 这样当你的 CPU 跑 lb/lh 指令读取外设(如 SW, KEY)时，总能命中外设的
    assign perip_addr = {cpu_mem_addr[31:2], 2'b00};

    // 16KB = 2^12 * 32bit
    assign inst_addr = pc[13:2];
/*
    myCPU Core_cpu (
        .cpu_rst            (w_clk_rst),
        .cpu_clk            (w_cpu_clk),

        // Interface to IROM
        .irom_addr          (pc),             
        .irom_data          (instruction),   

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),     
        .perip_wen          (perip_wen),     
        .perip_mask         (perip_mask),   
        .perip_wdata        (perip_wdata),    
        .perip_rdata        (perip_rdata)     
    );
*/
    KLDJ_top Core_cpu (
        .rst                (w_clk_rst),
        .clk                (w_cpu_clk),

        // IROM 
        .tb_if_pc           (pc),            
        .tb_if_inst         (instruction),   

        // testbench interface
        .tb_ex_jump         (),              
        .tb_ex_jump_pc      (),              
        .tb_ex_res          (),              

        // DRAM & Perip
        .mem_addr           (cpu_mem_addr),   // perip_addr 
        .mem_we             (perip_wen),     
        .mem_be             (cpu_mem_be),    
        .mem_wdata          (perip_wdata),   
        .mem_rdata          (perip_rdata),
        .core_clk_o         ()
    );

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
