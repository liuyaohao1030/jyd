`timescale 1ns/1ps
`include "define.v"

module ex_forward_tb;
    reg         id_ex_valid;
    reg  [4:0]  id_ex_rd_addr;
    reg         id_ex_rs1_ren;
    reg         id_ex_rs2_ren;
    reg  [1:0]  id_ex_rs1_fwd_sel;
    reg  [1:0]  id_ex_rs2_fwd_sel;
    reg         id_ex_load_op;
    reg         id_ex_store_op;
    reg         id_ex_rs2_to_data2;
    reg  [31:0] id_ex_data1;
    reg  [31:0] id_ex_data2;
    reg  [31:0] id_ex_data3;
    reg  [31:0] id_ex_data4;
    reg  [31:0] id_ex_rs1_data;
    reg  [31:0] id_ex_rs2_data;
    reg  [31:0] ex_mem_exu_res;
    reg  [31:0] mem_wb_wb_data;
    reg         if_id_valid;
    reg  [4:0]  id_reg_rs1_addr;
    reg  [4:0]  id_reg_rs2_addr;
    reg         id_reg_rs1_ren;
    reg         id_reg_rs2_ren;

    wire [31:0] ex_data1;
    wire [31:0] ex_data2;
    wire [31:0] ex_data3;
    wire [31:0] ex_data4;
    wire [31:0] ex_store_wdata;
    wire        load_use_stall;
    integer checks;

    ex_forward dut (
         .id_ex_valid       (id_ex_valid)
        ,.id_ex_rd_addr     (id_ex_rd_addr)
        ,.id_ex_rs1_ren     (id_ex_rs1_ren)
        ,.id_ex_rs2_ren     (id_ex_rs2_ren)
        ,.id_ex_rs1_fwd_sel (id_ex_rs1_fwd_sel)
        ,.id_ex_rs2_fwd_sel (id_ex_rs2_fwd_sel)
        ,.id_ex_load_op     (id_ex_load_op)
        ,.id_ex_store_op    (id_ex_store_op)
        ,.id_ex_rs2_to_data2(id_ex_rs2_to_data2)
        ,.id_ex_data1       (id_ex_data1)
        ,.id_ex_data2       (id_ex_data2)
        ,.id_ex_data3       (id_ex_data3)
        ,.id_ex_data4       (id_ex_data4)
        ,.id_ex_rs1_data    (id_ex_rs1_data)
        ,.id_ex_rs2_data    (id_ex_rs2_data)
        ,.ex_mem_exu_res    (ex_mem_exu_res)
        ,.mem_wb_wb_data    (mem_wb_wb_data)
        ,.if_id_valid       (if_id_valid)
        ,.id_reg_rs1_addr   (id_reg_rs1_addr)
        ,.id_reg_rs2_addr   (id_reg_rs2_addr)
        ,.id_reg_rs1_ren    (id_reg_rs1_ren)
        ,.id_reg_rs2_ren    (id_reg_rs2_ren)
        ,.ex_data1          (ex_data1)
        ,.ex_data2          (ex_data2)
        ,.ex_data3          (ex_data3)
        ,.ex_data4          (ex_data4)
        ,.ex_store_wdata    (ex_store_wdata)
        ,.load_use_stall    (load_use_stall)
    );

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*56-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("FAIL: %0s expected=%08x actual=%08x", label, expected, actual);
                $fatal(1);
            end
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input [8*56-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("FAIL: %0s expected=%b actual=%b", label, expected, actual);
                $fatal(1);
            end
        end
    endtask

    task apply_defaults;
        begin
            id_ex_valid        = 1'b1;
            id_ex_rd_addr      = 5'd7;
            id_ex_rs1_ren      = 1'b1;
            id_ex_rs2_ren      = 1'b1;
            id_ex_rs1_fwd_sel  = 2'b00;
            id_ex_rs2_fwd_sel  = 2'b00;
            id_ex_load_op      = 1'b0;
            id_ex_store_op     = 1'b1;
            id_ex_rs2_to_data2 = 1'b1;
            id_ex_data1        = 32'h1111_0001;
            id_ex_data2        = 32'h2222_0002;
            id_ex_data3        = 32'h3333_0003;
            id_ex_data4        = 32'h4444_0004;
            id_ex_rs1_data     = 32'ha1a1_a1a1;
            id_ex_rs2_data     = 32'hb2b2_b2b2;
            ex_mem_exu_res     = 32'he3e3_e3e3;
            mem_wb_wb_data     = 32'hf4f4_f4f4;
            if_id_valid        = 1'b0;
            id_reg_rs1_addr    = 5'd0;
            id_reg_rs2_addr    = 5'd0;
            id_reg_rs1_ren     = 1'b0;
            id_reg_rs2_ren     = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        apply_defaults();
        #1;
        expect_word(ex_data1, id_ex_rs1_data, "generic rs1 regfile data");
        expect_word(ex_data2, id_ex_rs2_data, "generic rs2 regfile data");
        expect_word(ex_store_wdata, id_ex_rs2_data, "store regfile data");

        id_ex_rs1_fwd_sel = 2'b01;
        id_ex_rs2_fwd_sel = 2'b01;
        #1;
        expect_word(ex_data1, ex_mem_exu_res, "rs1 EX/MEM forward");
        expect_word(ex_data2, ex_mem_exu_res, "rs2 EX/MEM forward");
        expect_word(ex_store_wdata, ex_mem_exu_res, "store EX/MEM forward");

        id_ex_rs1_fwd_sel = 2'b10;
        id_ex_rs2_fwd_sel = 2'b10;
        #1;
        expect_word(ex_data1, mem_wb_wb_data, "rs1 MEM/WB forward");
        expect_word(ex_data2, mem_wb_wb_data, "rs2 MEM/WB forward");
        expect_word(ex_store_wdata, mem_wb_wb_data, "store MEM/WB forward");

        id_ex_rs1_ren = 1'b0;
        id_ex_rs2_to_data2 = 1'b0;
        id_ex_store_op = 1'b0;
        #1;
        expect_word(ex_data1, id_ex_data1, "immediate operand ignores rs1 select");
        expect_word(ex_data2, id_ex_data2, "immediate operand ignores rs2 select");
        expect_word(ex_store_wdata, id_ex_data3, "non-store data path unchanged");

        apply_defaults();
        id_ex_load_op   = 1'b1;
        if_id_valid     = 1'b1;
        id_reg_rs1_ren  = 1'b1;
        id_reg_rs1_addr = 5'd7;
        #1;
        expect_bit(load_use_stall, 1'b1, "load-use rs1 hazard");

        id_reg_rs1_addr = 5'd6;
        id_reg_rs1_ren  = 1'b0;
        id_reg_rs2_ren  = 1'b1;
        id_reg_rs2_addr = 5'd7;
        #1;
        expect_bit(load_use_stall, 1'b1, "load-use rs2 hazard");

        id_ex_rd_addr = 5'd0;
        #1;
        expect_bit(load_use_stall, 1'b0, "x0 is not a load-use producer");

        $display("PASS: ex_forward_tb (%0d checks)", checks);
        $finish;
    end
endmodule
