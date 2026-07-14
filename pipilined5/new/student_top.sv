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

    // Power-on reset generation: counter to ensure reset pulse
    (* mark_debug = "true" *) logic [3:0] rst_counter = 4'hF;
    (* mark_debug = "true" *) logic       cpu_rst;

    always_ff @(posedge w_cpu_clk) begin
        if (w_clk_rst) begin
            // External reset active (PLL not locked)
            rst_counter <= 4'hF;
        end else if (rst_counter != 4'h0) begin
            // Count down to generate reset pulse
            rst_counter <= rst_counter - 4'h1;
        end
    end

    assign cpu_rst = (rst_counter != 4'h0) | w_clk_rst;

    // IROM
    logic [31:0] pc;
    logic [11:0] inst_addr;
    logic [31:0] instruction;

    // perip
    logic [31:0] perip_addr, perip_wdata, perip_rdata;
    logic perip_wen;
    logic [3:0] cpu_mem_be;

    // 16KB = 2^12 * 32bit
    assign inst_addr = pc[13:2];

    KLDJ_top u_KLDJ_top (
        .clk            (w_cpu_clk),
        .rst            (cpu_rst),

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

    IROM Mem_IROM (
        .a          (inst_addr),
        .spo        (instruction)
    );

    perip_bridge bridge_inst (
        .clk                (w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst                (w_clk_rst),
        .perip_addr         (perip_addr),
        .perip_wdata        (perip_wdata),
        .perip_wen          (perip_wen),
        .perip_be           (cpu_mem_be),
        .perip_rdata        (perip_rdata),
        .virtual_sw_input   (virtual_sw),
        .virtual_key_input  (virtual_key),
        .virtual_seg_output (virtual_seg),
        .virtual_led_output (virtual_led)
    );

endmodule
