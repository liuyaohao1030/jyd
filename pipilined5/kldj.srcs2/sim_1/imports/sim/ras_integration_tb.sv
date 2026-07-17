`timescale 1ns/1ps

`include "define.v"

// End-to-end RAS test.  The program executes a nested call, saves/restores
// ra around the inner call, and returns twice.  EX2 updates the RAS one cycle
// later than EX, so the closely spaced outer return may need one recovery
// redirect while the preceding return pop is still in flight.
module ras_integration_tb;
    reg         clk = 1'b0;
    reg         rst;
    reg [31:0]  inst_mem [0:255];
    wire [31:0] if_pc;
    wire [31:0] inst_rdata;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    reg  [31:0] mem_rdata;

    integer i;
    integer ras_return_seen;
    integer ras_return_hits;
    integer ras_return_redirects;

    assign inst_rdata = inst_mem[if_pc[9:2]];

    always #5 clk = ~clk;

    KLDJ_top dut (
         .clk          (clk          )
        ,.rst          (rst          )
        ,.tb_if_inst   (inst_rdata   )
        ,.tb_if_pc     (if_pc        )
        ,.tb_ex_jump   (             )
        ,.tb_ex_jump_pc(             )
        ,.tb_ex_res    (             )
        ,.mem_addr     (mem_addr     )
        ,.mem_wdata    (mem_wdata    )
        ,.mem_we       (mem_we       )
        ,.mem_be       (mem_be       )
        ,.mem_rdata    (mem_rdata    )
        ,.core_clk_o   (             )
    );

    function [31:0] rv_i;
        input [11:0] imm;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            rv_i = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] rv_j;
        input signed [20:0] imm;
        input [4:0] rd;
        reg [20:0] value;
        begin
            value = imm;
            rv_j = {value[20], value[10:1], value[11], value[19:12], rd, 7'b1101111};
        end
    endfunction

    wire ex2_is_canonical_return = dut.ex2_valid &&
                                   (dut.ex2_exu_op == 18'h09) &&
                                   (dut.ex2_rd_addr == 5'd0) &&
                                   (dut.ex2_rs1_addr == 5'd1) &&
                                   (dut.ex2_data2 == 32'd0);

    always @(posedge clk) begin
        mem_rdata <= 32'b0;
        if(!rst && ex2_is_canonical_return) begin
            ras_return_seen <= ras_return_seen + 1;
            if(dut.ex2_pred_taken &&
               (dut.ex2_pred_target == dut.ex2_jump_pc_raw) &&
               !dut.ex_redirect)
                ras_return_hits <= ras_return_hits + 1;
            else
                ras_return_redirects <= ras_return_redirects + 1;
        end
    end

    initial begin
        for(i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013; // nop

        // main: call f1, copy its result, then park in a JAL x0 self-loop.
        inst_mem[0]  = rv_j(21'sd32, 5'd1);                         // jal ra, f1
        inst_mem[1]  = rv_i(12'd0, 5'd10, 3'b000, 5'd11, 7'b0010011); // x11=x10
        inst_mem[2]  = rv_j(21'sd0, 5'd0);                          // terminal loop

        // f1: preserve main's ra in x5, call f2, restore ra, add one, ret.
        inst_mem[8]  = rv_i(12'd0, 5'd1, 3'b000, 5'd5, 7'b0010011); // x5=ra
        inst_mem[9]  = rv_j(21'sd32, 5'd1);                         // jal ra, f2
        inst_mem[10] = rv_i(12'd0, 5'd5, 3'b000, 5'd1, 7'b0010011); // ra=x5
        inst_mem[11] = rv_i(12'd1, 5'd10, 3'b000, 5'd10, 7'b0010011);
        inst_mem[12] = rv_i(12'd0, 5'd1, 3'b000, 5'd0, 7'b1100111); // ret

        // f2: return the value 7 using a canonical ret.
        inst_mem[17] = rv_i(12'd7, 5'd0, 3'b000, 5'd10, 7'b0010011);
        inst_mem[18] = rv_i(12'd0, 5'd1, 3'b000, 5'd0, 7'b1100111); // ret

        rst                  = `KLDJ_RSTABLE;
        mem_rdata            = 32'b0;
        ras_return_seen      = 0;
        ras_return_hits      = 0;
        ras_return_redirects = 0;
        repeat (5) @(posedge clk);
        rst = ~`KLDJ_RSTABLE;

        repeat (100) @(posedge clk);
        #1;
        if(dut.reg5.regs[10] !== 32'd8 || dut.reg5.regs[11] !== 32'd8)
            $fatal(1, "nested call result mismatch: x10=%h x11=%h",
                   dut.reg5.regs[10], dut.reg5.regs[11]);
        if(ras_return_seen !== 2 || ras_return_hits < 1 ||
           (ras_return_hits + ras_return_redirects) !== 2)
            $fatal(1, "RAS integration failed: returns=%0d hits=%0d redirects=%0d",
                   ras_return_seen, ras_return_hits, ras_return_redirects);

        $display("RAS INTEGRATION TEST PASSED (returns=%0d hits=%0d redirects=%0d)",
                 ras_return_seen, ras_return_hits, ras_return_redirects);
        $finish;
    end
endmodule
