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

    // Reset synchronizer: hold reset for 16 cycles after PLL locks
    (* mark_debug = "true" *) logic [3:0] rst_cnt = 4'd0;
    (* mark_debug = "true" *) logic       rst_sync = 1'b1;
    (* mark_debug = "true" *) logic       dbg_w_clk_rst;
    assign dbg_w_clk_rst = w_clk_rst;

    always_ff @(posedge w_cpu_clk) begin
        if (w_clk_rst) begin
            // w_clk_rst=1 means PLL NOT locked (active-high reset from ~locked)
            rst_cnt  <= 4'd0;
            rst_sync <= 1'b1;
        end else if (rst_cnt != 4'd15) begin
            rst_cnt  <= rst_cnt + 1'b1;
            rst_sync <= 1'b1;
        end else begin
            rst_sync <= 1'b0;
        end
    end

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
        .rst            (rst_sync),

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
