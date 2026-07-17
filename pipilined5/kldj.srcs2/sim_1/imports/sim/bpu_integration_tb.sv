`timescale 1ns/1ps
`include "define.v"

module bpu_integration_tb;
    reg clk = 1'b0;
    reg rst;
    reg [31:0] inst_mem [0:255];
    wire [31:0] if_pc;
    wire [31:0] inst_rdata = inst_mem[if_pc[9:2]];
    wire [31:0] mem_addr, mem_wdata;
    wire mem_we;
    wire [3:0] mem_be;
    reg [31:0] mem_rdata = 32'b0;
    reg [31:0] data_mem [0:255];
    wire [31:0] perf_unused [0:8];
    integer i;
    integer branch_updates = 0;
    integer dynamic_pred_hits = 0;

    always #5 clk = ~clk;

    KLDJ_top dut(
         .clk(clk), .rst(rst), .tb_if_inst(inst_rdata), .tb_if_pc(if_pc)
        ,.tb_ex_jump(), .tb_ex_jump_pc(), .tb_ex_res()
        ,.mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_we(mem_we), .mem_be(mem_be)
        ,.mem_rdata(mem_rdata), .core_clk_o()
        ,.perf_cycle_count(perf_unused[0]), .perf_instret_count(perf_unused[1])
        ,.perf_frontend_stall_count(perf_unused[2]), .perf_load_use_stall_count(perf_unused[3])
        ,.perf_mul_stall_count(perf_unused[4]), .perf_div_stall_count(perf_unused[5])
        ,.perf_redirect_count(perf_unused[6]), .perf_load_count(perf_unused[7])
        ,.perf_store_count(perf_unused[8])
    );

    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_be[0]) data_mem[mem_addr[9:2]][7:0]   <= mem_wdata[7:0];
            if (mem_be[1]) data_mem[mem_addr[9:2]][15:8]  <= mem_wdata[15:8];
            if (mem_be[2]) data_mem[mem_addr[9:2]][23:16] <= mem_wdata[23:16];
            if (mem_be[3]) data_mem[mem_addr[9:2]][31:24] <= mem_wdata[31:24];
        end
        mem_rdata <= data_mem[mem_addr[9:2]];

        if (dut.bpu_update_valid &&
            (dut.ex2_exu_op >= 18'h14) && (dut.ex2_exu_op <= 18'h19)) begin
            branch_updates <= branch_updates + 1;
            if (dut.ex2_pred_taken && dut.ex2_jump_raw && !dut.ex_redirect)
                dynamic_pred_hits <= dynamic_pred_hits + 1;
        end
    end

    function [31:0] rv_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin rv_i = {imm, rs1, funct3, rd, 7'b0010011}; end
    endfunction

    function [31:0] rv_b;
        input signed [12:0] imm;
        input [4:0] rs1;
        input [4:0] rs2;
        input [2:0] funct3;
        reg [12:0] v;
        begin
            v = imm;
            rv_b = {v[12], v[10:5], rs2, rs1, funct3, v[4:1], v[11], 7'b1100011};
        end
    endfunction

    function [31:0] rv_j;
        input signed [20:0] imm;
        input [4:0] rd;
        reg [20:0] v;
        begin
            v = imm;
            rv_j = {v[20], v[10:1], v[11], v[19:12], rd, 7'b1101111};
        end
    endfunction

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            inst_mem[i] = 32'h00000013;
            data_mem[i] = 32'b0;
        end
        // Long enough for the 6-bit GHR to settle and the active PHT entry to train.
        inst_mem[0] = rv_i(12'd12, 5'd0, 3'b000, 5'd1);
        inst_mem[1] = rv_i(12'hfff, 5'd1, 3'b000, 5'd1);
        inst_mem[2] = rv_b(-13'sd4, 5'd1, 5'd0, 3'b001); // bne x1,x0,loop
        inst_mem[3] = rv_i(12'h055, 5'd0, 3'b000, 5'd2);
        inst_mem[4] = rv_i(12'h0aa, 5'd0, 3'b000, 5'd3);
        inst_mem[5] = rv_j(21'sd0, 5'd0); // stable JAL self-loop

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (180) @(posedge clk);
        #1;
        if (dut.reg5.regs[1] !== 32'd0 || dut.reg5.regs[2] !== 32'h55 ||
            dut.reg5.regs[3] !== 32'haa)
            $fatal(1, "branch integration failed: x1=%h x2=%h x3=%h",
                   dut.reg5.regs[1], dut.reg5.regs[2], dut.reg5.regs[3]);
        if (branch_updates < 12 || dynamic_pred_hits == 0)
            $fatal(1, "Gshare did not train: updates=%0d hits=%0d",
                   branch_updates, dynamic_pred_hits);
        $display("BPU INTEGRATION TEST PASSED (updates=%0d hits=%0d GHR=%0d)",
                 branch_updates, dynamic_pred_hits,
                 dut.u_bpu.u_gshare_btb_core.ghr);
        $finish;
    end
endmodule
