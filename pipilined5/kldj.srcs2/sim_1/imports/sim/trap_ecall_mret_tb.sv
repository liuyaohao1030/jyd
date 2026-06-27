`timescale 1ns/1ps
`include "define.v"

module trap_ecall_mret_tb;

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
reg seen_trap_redirect;
reg seen_mret_redirect;

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

function automatic [31:0] rv32_u;
    input [19:0] imm20;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
        rv32_u = {imm20, rd, opcode};
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

integer i;

always @(posedge core_clk) begin
    if (rst == 1'b1) begin
        seen_trap_redirect <= 1'b0;
        seen_mret_redirect <= 1'b0;
    end else begin
        if (tb_ex_jump && tb_ex_jump_pc == (START_PC + 32'h40)) begin
            seen_trap_redirect <= 1'b1;
        end
        if (tb_ex_jump && tb_ex_jump_pc == (START_PC + 32'h18)) begin
            seen_mret_redirect <= 1'b1;
        end
    end
end

initial begin
    rst = 1'b1;

    for (i = 0; i < IMEM_WORDS; i = i + 1) begin
        imem[i] = 32'h00000013;
    end

    imem[0]  = rv32_u(20'h80000, 5'd1, 7'b0110111);                     // x1 = 0x80000000
    imem[1]  = rv32_i(12'h041, 5'd1, 3'b000, 5'd1, 7'b0010011);          // x1 = handler | 1
    imem[2]  = rv32_i(12'h008, 5'd0, 3'b000, 5'd2, 7'b0010011);          // x2 = mstatus.MIE
    imem[3]  = rv32_csr(`KLDJ_CSR_MSTATUS, 5'd2, 3'b001, 5'd0);          // csrw mstatus, x2
    imem[4]  = rv32_csr(`KLDJ_CSR_MTVEC, 5'd1, 3'b001, 5'd0);            // csrw mtvec, x1
    imem[5]  = 32'h00000073;                                             // ecall
    imem[6]  = rv32_i(12'h001, 5'd0, 3'b000, 5'd10, 7'b0010011);         // return path
    imem[7]  = rv32_csr(`KLDJ_CSR_MSTATUS, 5'd0, 3'b010, 5'd12);         // read mstatus after mret
    imem[8]  = 32'h0000006f;                                             // finish loop

    imem[16] = rv32_csr(`KLDJ_CSR_MEPC, 5'd0, 3'b010, 5'd3);             // x3 = mepc
    imem[17] = rv32_csr(`KLDJ_CSR_MCAUSE, 5'd0, 3'b010, 5'd4);           // x4 = mcause
    imem[18] = rv32_csr(`KLDJ_CSR_MSTATUS, 5'd0, 3'b010, 5'd5);          // x5 = trap mstatus
    imem[19] = rv32_i(12'h004, 5'd3, 3'b000, 5'd7, 7'b0010011);          // x7 = mepc + 4
    imem[20] = rv32_csr(`KLDJ_CSR_MEPC, 5'd7, 3'b001, 5'd0);             // mepc = ecall + 4
    imem[21] = 32'h30200073;                                             // mret
    imem[22] = rv32_i(12'h001, 5'd0, 3'b000, 5'd11, 7'b0010011);         // wrong path after mret

    #20;
    rst = 1'b0;

    repeat (120) @(posedge core_clk);
    #1;

    if (!seen_trap_redirect) $fatal(1, "ecall did not redirect to mtvec & ~3");
    if (!seen_mret_redirect) $fatal(1, "mret did not redirect to mepc");
    if (dut.reg5.regs[3] !== (START_PC + 32'h14)) $fatal(1, "mepc saved wrong: x3=0x%08h", dut.reg5.regs[3]);
    if (dut.reg5.regs[4] !== 32'd11) $fatal(1, "mcause wrong: x4=0x%08h", dut.reg5.regs[4]);
    if (dut.reg5.regs[5] !== 32'h00000080) $fatal(1, "trap mstatus wrong: x5=0x%08h", dut.reg5.regs[5]);
    if (dut.reg5.regs[10] !== 32'h00000001) $fatal(1, "return path did not execute: x10=0x%08h", dut.reg5.regs[10]);
    if (dut.reg5.regs[11] !== 32'h00000000) $fatal(1, "mret wrong path was not flushed: x11=0x%08h", dut.reg5.regs[11]);
    if (dut.reg5.regs[12] !== 32'h00000088) $fatal(1, "mret mstatus wrong: x12=0x%08h", dut.reg5.regs[12]);
    if (dut.csr0.mcause !== 32'd11) $fatal(1, "CSR mcause final wrong: 0x%08h", dut.csr0.mcause);
    if (dut.csr0.mepc !== (START_PC + 32'h18)) $fatal(1, "CSR mepc final wrong: 0x%08h", dut.csr0.mepc);
    if (dut.csr0.mtvec !== (START_PC + 32'h41)) $fatal(1, "CSR mtvec raw value wrong: 0x%08h", dut.csr0.mtvec);

    $display("[SUMMARY] ecall/mret trap smoke test passed.");
    $finish;
end

endmodule
