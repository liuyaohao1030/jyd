`include "../define.v"

module KLDJ_lsu(
     input  wire [17:0]         exu_op
    ,input  wire [3:0]          id_ls_ctl
    ,input  wire [`KLDJ_DATA]   ls_addr      // 从 EXU 传来的 ALU 计算结果（访存地址）
    ,input  wire [`KLDJ_DATA]   ls_wdata     // 从 IDU 传来的 data3（也就是 rs2，准备存入内存的数据）
    // 连接到 Data Memory 的接口
    ,output wire [`KLDJ_DATA]   mem_addr
    ,output wire [`KLDJ_DATA]   mem_wdata
    ,output wire                mem_we
    ,output wire [3:0]          mem_be
    ,input  wire [`KLDJ_DATA]   mem_rdata
    // 输出给写回阶段 (WBU)
    ,output wire [`KLDJ_DATA]   lsu_res
    ,output wire                is_load
);

    // 判断是否为 Load 或 Store
    assign is_load  = (exu_op >= 18'h1d && exu_op <= 18'h21); // LB, LH, LW, LBU, LHU
    wire is_store = (exu_op >= 18'h22 && exu_op <= 18'h24);   // SB, SH, SW

    // id_ls_ctl: bit0-1: size, bit2: signed, bit3: is_load_op
    wire [1:0] size = id_ls_ctl[1:0];
    wire signed_load = id_ls_ctl[2];

    // 生成 Byte Enable (mem_be)
    assign mem_be = (size == 2'b00) ? (4'b0001 << ls_addr[1:0]) :
                    (size == 2'b01) ? (4'b0011 << {ls_addr[1], 1'b0}) :
                    (size == 2'b10) ? 4'b1111 : 4'b0000;

    assign mem_we = is_store;
    assign mem_addr = ls_addr;

    // ----- Store 数据的对齐处理 -----
    wire [31:0] store_byte_data = {4{ls_wdata[7:0]}}; 
    wire [31:0] store_half_data = {2{ls_wdata[15:0]}};
    wire [31:0] store_word_data = ls_wdata;

    assign mem_wdata = (size == 2'b00) ? store_byte_data :
                       (size == 2'b01) ? store_half_data :
                       store_word_data;

    // ----- Load 数据的提取与符号扩展 -----
    wire [31:0] mem_rdata_shifted_byte = mem_rdata >> ({ls_addr[1:0], 3'b0});
    wire [7:0]  loaded_byte = mem_rdata_shifted_byte[7:0];

    wire [31:0] mem_rdata_shifted_half = mem_rdata >> ({ls_addr[1], 4'b0});
    wire [15:0] loaded_half = mem_rdata_shifted_half[15:0];

    wire [31:0] loaded_word = mem_rdata;

    assign lsu_res = (size == 2'b00) ? {{24{signed_load & loaded_byte[7]}}, loaded_byte[7:0]} :
                     (size == 2'b01) ? {{16{signed_load & loaded_half[15]}}, loaded_half[15:0]} :
                     loaded_word;

endmodule
