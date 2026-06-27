`timescale 1ns/1ps
`include "define.v"

module csr_instr_tb;

localparam [31:0] START_PC = `KLDJ_STARTPC;
localparam integer IMEM_WORDS = 64;

reg clk;
reg rst;
wire [31:0] tb_if_pc;
reg  [31:0] tb_if_inst;
wire tb_ex_jump;
wire [31:0] tb_ex_jump_pc;
wire [31:0] tb_ex_res;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire        mem_we;
wire [3:0]  mem_be;
wire [31:0] mem_rdata;
wire        core_clk;

reg [31:0] imem [0:IMEM_WORDS-1];

assign mem_rdata = 32'd0;

KLDJ_top dut (
     .clk          (clk)
    ,.rst          (rst)
    ,.tb_if_inst   (tb_if_inst)
    ,.tb_if_pc     (tb_if_pc)
    ,.tb_ex_jump   (tb_ex_jump)
    ,.tb_ex_jump_pc(tb_ex_jump_pc)
    ,.tb_ex_res    (tb_ex_res)
    ,.mem_addr     (mem_addr)
    ,.mem_wdata    (mem_wdata)
    ,.mem_we       (mem_we)
    ,.mem_be       (mem_be)
    ,.mem_rdata    (mem_rdata)
    ,.core_clk_o   (core_clk)
);

always @(*) begin
    if (^tb_if_pc === 1'bx)
        tb_if_inst = 32'h00000013;
    else
        tb_if_inst = imem[tb_if_pc[7:2]];
end

always begin
    clk = 1'b0;
    #5;
    clk = 1'b1;
    #5;
end

function automatic [31:0] rv32_i;
    input [11:0] imm12;
    input [4:0]  rs1;
    input [2:0]  funct3;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
        rv32_i = {imm12, rs1, funct3, rd, opcode};
    end
endfunction

function automatic [31:0] rv32_csr;
    input [11:0] csr;
    input [4:0]  rs1_zimm;
    input [2:0]  funct3;
    input [4:0]  rd;
    begin
        rv32_csr = {csr, rs1_zimm, funct3, rd, 7'b1110011};
    end
endfunction

function automatic [31:0] rv32_jal_zero;
    begin
        rv32_jal_zero = 32'h0000006f;
    end
endfunction

integer i;

initial begin
    rst = 1'b1;

    for (i = 0; i < IMEM_WORDS; i = i + 1) begin
        imem[i] = 32'h00000013;
    end

    imem[0] = rv32_i(12'h055, 5'd0, 3'b000, 5'd1, 7'b0010011);                  // addi x1, x0, 0x55
    imem[1] = rv32_csr(`KLDJ_CSR_MTVEC, 5'd1, 3'b001, 5'd2);                    // csrrw x2, mtvec, x1
    imem[2] = rv32_csr(`KLDJ_CSR_MTVEC, 5'd0, 3'b010, 5'd3);                    // csrrs x3, mtvec, x0
    imem[3] = rv32_i(12'h00f, 5'd0, 3'b000, 5'd4, 7'b0010011);                  // addi x4, x0, 0x0f
    imem[4] = rv32_csr(`KLDJ_CSR_MTVEC, 5'd4, 3'b010, 5'd5);                    // csrrs x5, mtvec, x4
    imem[5] = rv32_csr(`KLDJ_CSR_MTVEC, 5'd1, 3'b111, 5'd6);                    // csrrci x6, mtvec, 1
    imem[6] = rv32_csr(`KLDJ_CSR_MTVEC, 5'd0, 3'b110, 5'd7);                    // csrrsi x7, mtvec, 0
    imem[7] = rv32_csr(`KLDJ_CSR_MEPC, 5'd4, 3'b001, 5'd0);                     // csrrw x0, mepc, x4
    imem[8] = rv32_csr(`KLDJ_CSR_MEPC, 5'd0, 3'b010, 5'd8);                     // csrrs x8, mepc, x0
    imem[9] = rv32_jal_zero();

    #20;
    rst = 1'b0;

    repeat (80) @(posedge core_clk);
    #1;

    if (dut.reg5.regs[0] !== 32'h00000000) $fatal(1, "x0 changed: 0x%08h", dut.reg5.regs[0]);
    if (dut.reg5.regs[2] !== 32'h00000000) $fatal(1, "csrrw old value failed: x2=0x%08h", dut.reg5.regs[2]);
    if (dut.reg5.regs[3] !== 32'h00000055) $fatal(1, "csrrs x0 read failed: x3=0x%08h", dut.reg5.regs[3]);
    if (dut.reg5.regs[5] !== 32'h00000055) $fatal(1, "csrrs old value failed: x5=0x%08h", dut.reg5.regs[5]);
    if (dut.reg5.regs[6] !== 32'h0000005f) $fatal(1, "csrrci old value failed: x6=0x%08h", dut.reg5.regs[6]);
    if (dut.reg5.regs[7] !== 32'h0000005e) $fatal(1, "csrrsi zimm0 old value failed: x7=0x%08h", dut.reg5.regs[7]);
    if (dut.reg5.regs[8] !== 32'h0000000f) $fatal(1, "csrrw x0 write/read mepc failed: x8=0x%08h", dut.reg5.regs[8]);
    if (dut.csr0.mtvec !== 32'h0000005e) $fatal(1, "mtvec final failed: 0x%08h", dut.csr0.mtvec);
    if (dut.csr0.mepc !== 32'h0000000f) $fatal(1, "mepc final failed: 0x%08h", dut.csr0.mepc);

    $display("[SUMMARY] csr instruction smoke test passed.");
    $finish;
end

endmodule
