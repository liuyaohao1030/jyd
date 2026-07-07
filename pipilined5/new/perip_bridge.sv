`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2025/04/22 10:25:24
// Design Name:
// Module Name: perip_bridge
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

module perip_bridge(
    input  logic         clk                ,
    input  logic         cnt_clk            ,
    input  logic         rst                ,

    input  logic [31:0]  perip_addr         ,
    input  logic [31:0]  perip_wdata        ,
    input  logic         perip_wen          ,
    input  logic [3:0]   perip_be           ,
    output logic [31:0]  perip_rdata        ,

    input  logic [63:0]  virtual_sw_input   ,
    input  logic [7:0]   virtual_key_input  ,

    output logic [39:0]  virtual_seg_output ,
    output logic [31:0]  virtual_led_output
);
    localparam DRAM_ADDR_START = 32'h8010_0000;
    localparam DRAM_ADDR_END   = 32'h8014_0000;
    localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
    localparam SEG_ADDR  = 32'h8020_0020;  // seg
    localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
    localparam CNT_ADDR  = 32'h8020_0050;  // counter
    localparam CNT_START_CMD = 32'h8000_0000;
    localparam CNT_STOP_CMD  = 32'hFFFF_FFFF;

    logic [31:0] LED;
    logic [31:0] seg_wdata, cnt_rdata, cnt_rdata_q, mmio_rdata_q, dram_rdata;
    logic [39:0] seg_output;
    logic cnt_enable_cfg;

    wire is_dram_addr = (perip_addr >= DRAM_ADDR_START) && (perip_addr < DRAM_ADDR_END);
    wire is_sw0_addr  = (perip_addr == SW0_ADDR);
    wire is_sw1_addr  = (perip_addr == SW1_ADDR);
    wire is_key_addr  = (perip_addr == KEY_ADDR);
    wire is_seg_addr  = (perip_addr == SEG_ADDR);
    wire is_led_addr  = (perip_addr == LED_ADDR);
    wire is_cnt_addr  = (perip_addr == CNT_ADDR);

    logic rd_is_dram_q;
    logic rd_is_sw0_q;
    logic rd_is_sw1_q;
    logic rd_is_key_q;
    logic rd_is_seg_q;
    logic rd_is_cnt_q;

    // Write process. LED/SEG write semantics are unchanged.
    always_ff @(posedge clk) begin
        if (rst) begin
            LED            <= 32'd0;
            seg_wdata      <= 32'd0;
            cnt_enable_cfg <= 1'b0;
        end else if (perip_wen) begin
            if (is_led_addr) begin
                LED <= perip_wdata;
            end else if (is_seg_addr) begin
                seg_wdata <= perip_wdata;
            end else if (is_cnt_addr) begin
                if (perip_wdata == CNT_START_CMD) begin
                    cnt_enable_cfg <= 1'b1;
                end else if (perip_wdata == CNT_STOP_CMD) begin
                    cnt_enable_cfg <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_is_dram_q <= 1'b0;
            rd_is_sw0_q  <= 1'b0;
            rd_is_sw1_q  <= 1'b0;
            rd_is_key_q  <= 1'b0;
            rd_is_seg_q  <= 1'b0;
            rd_is_cnt_q  <= 1'b0;
            mmio_rdata_q <= 32'h0;
            cnt_rdata_q  <= 32'h0;
        end else begin
            rd_is_dram_q <= (~perip_wen) && is_dram_addr;
            rd_is_sw0_q  <= (~perip_wen) && is_sw0_addr;
            rd_is_sw1_q  <= (~perip_wen) && is_sw1_addr;
            rd_is_key_q  <= (~perip_wen) && is_key_addr;
            rd_is_seg_q  <= (~perip_wen) && is_seg_addr;
            rd_is_cnt_q  <= (~perip_wen) && is_cnt_addr;
            cnt_rdata_q  <= cnt_rdata;

            case (perip_addr)
                SW0_ADDR:  mmio_rdata_q <= virtual_sw_input[31:0];
                SW1_ADDR:  mmio_rdata_q <= virtual_sw_input[63:32];
                KEY_ADDR:  mmio_rdata_q <= {24'd0, virtual_key_input};
                SEG_ADDR:  mmio_rdata_q <= seg_wdata;
                default:   mmio_rdata_q <= 32'hDEAD_BEEF;
            endcase
        end
    end

    // seg driver
    display_seg seg_driver (
        .clk    (clk),
        .rst    (rst),
        .s      (seg_wdata),
        .seg1   (seg_output[6:0]),
        .seg2   (seg_output[16:10]),
        .seg3   (seg_output[26:20]),
        .seg4   (seg_output[36:30]),
        .ans    ({seg_output[39:38], seg_output[29:28], seg_output[19:18], seg_output[9:8]})
    );

    assign seg_output[7]  = 0;
    assign seg_output[17] = 0;
    assign seg_output[27] = 0;
    assign seg_output[37] = 0;

    // dram rw
    dram_driver dram_driver_inst (
        .clk                (clk),
        .perip_addr         (perip_addr[17:0]),
        .perip_wdata        (perip_wdata),
        .perip_be           (perip_be),
        .dram_wen           (perip_wen && is_dram_addr),
        .perip_rdata        (dram_rdata)
    );

    // counter rw
    counter counter_inst (
        .cpu_clk            (clk),
        .cnt_clk            (cnt_clk),
        .rst                (rst),
        .cnt_enable_cpu     (cnt_enable_cfg),
        .perip_rdata        (cnt_rdata)
    );

    assign perip_rdata =
        rd_is_dram_q ? dram_rdata :
        rd_is_cnt_q  ? cnt_rdata_q :
        (rd_is_sw0_q || rd_is_sw1_q || rd_is_key_q || rd_is_seg_q) ? mmio_rdata_q :
        32'h0;

    assign virtual_led_output = LED;
    assign virtual_seg_output = seg_output;

endmodule
