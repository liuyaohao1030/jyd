`timescale 1ns/1ps

// Focused check for the FixTiming7 JALR operand bypass.  data2 is deliberately
// different from jalr_imm so the test cannot pass through the generic EX mux.
module KLDJ_exu_jalr_tb;
    reg         clk;
    reg         rst;
    reg         valid;
    reg  [31:0] data1;
    reg  [31:0] data2;
    reg  [31:0] data3;
    reg  [31:0] data4;
    reg  [31:0] ctrl_rs1_data;
    reg  [31:0] ctrl_rs2_data;
    reg  [31:0] jalr_imm;
    reg  [17:0] exu_op;
    reg  [9:0]  alu_ctrl;
    reg  [11:0] csr_addr;
    reg         csr_op;
    reg  [4:0]  csr_zimm;
    reg  [31:0] csr_rdata;
    reg  [31:0] mret_pc;

    wire        exu_jump;
    wire [31:0] exu_jump_pc;
    wire [31:0] exu_res;
    wire [31:0] ex_mem_addr;
    wire        div_stall;
    wire        mul_stall;
    wire        csr_we;
    wire [31:0] csr_wdata;
    wire        is_ecall;
    wire        is_mret;

    KLDJ_exu dut(
         .clk(clk), .rst(rst), .valid(valid)
        ,.data1(data1), .data2(data2), .data3(data3), .data4(data4)
        ,.ctrl_rs1_data(ctrl_rs1_data), .ctrl_rs2_data(ctrl_rs2_data)
        ,.jalr_imm(jalr_imm), .exu_op(exu_op), .alu_ctrl(alu_ctrl)
        ,.csr_addr(csr_addr), .csr_op(csr_op), .csr_zimm(csr_zimm)
        ,.csr_rdata(csr_rdata), .csr_we(csr_we), .csr_wdata(csr_wdata)
        ,.is_ecall(is_ecall), .is_mret(is_mret), .mret_pc(mret_pc)
        ,.exu_jump(exu_jump), .exu_jump_pc(exu_jump_pc)
        ,.exu_res(exu_res), .ex_mem_addr(ex_mem_addr)
        ,.div_stall(div_stall), .mul_stall(mul_stall)
    );

    always #5 clk = ~clk;

    task check_target;
        input [31:0] expected;
        input [8*40-1:0] label;
        begin
            #1;
            if (exu_jump_pc !== expected) begin
                $display("FAIL: %0s expected=%08x got=%08x", label,
                         expected, exu_jump_pc);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        valid = 1'b1;
        // data1 deliberately differs from ctrl_rs1_data.  A JALR target must
        // use the registered control-flow path, not the generic ALU input.
        data1 = 32'hdead_beef;
        data2 = 32'hdead_beef;
        data3 = 32'h0000_0123;
        data4 = 32'h0000_0000;
        ctrl_rs1_data = 32'h8000_0103;
        ctrl_rs2_data = 32'h1234_5678;
        jalr_imm = 32'h0000_0005;
        exu_op = 18'h9;
        alu_ctrl = 10'h008;
        csr_addr = 12'h0;
        csr_op = 1'b0;
        csr_zimm = 5'h0;
        csr_rdata = 32'h0;
        mret_pc = 32'h8000_0200;

        // (0x80000103 + 5) & ~1 = 0x80000108.
        check_target(32'h8000_0108, "positive immediate");

        ctrl_rs1_data = 32'h8000_0100;
        jalr_imm = 32'hffff_fffc;
        // (0x80000100 - 4) & ~1 = 0x800000fc.
        check_target(32'h8000_00fc, "negative immediate");

        // JAL remains on the ordinary ALU path and is unaffected by jalr_imm.
        exu_op = 18'h1c;
        data1 = 32'h8000_0100;
        data2 = 32'h0000_0020;
        ctrl_rs1_data = 32'hdead_beef;
        jalr_imm = 32'hdead_beef;
        check_target(32'h8000_0120, "direct JAL path");

        $display("PASS: KLDJ_exu_jalr_tb (3 checks)");
        $finish;
    end
endmodule
