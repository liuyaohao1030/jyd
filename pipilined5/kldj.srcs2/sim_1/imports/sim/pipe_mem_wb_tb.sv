`timescale 1ns / 1ps

`include "define.v"

module pipe_mem_wb_tb;

    reg         clk;
    reg         rst;
    reg         ex_mem_valid;
    reg  [31:0] ex_mem_pc;
    reg  [4:0]  ex_mem_rd_addr;
    reg         mem_stage_wb_ctl;
    reg  [31:0] wb_reg_rd_data;

    wire        mem_wb_valid;
    wire [31:0] mem_wb_pc;
    wire [4:0]  mem_wb_rd_addr;
    wire        mem_wb_wb_ctl;
    wire [31:0] mem_wb_wb_data;
    wire        mem_wb_forward_valid;

    integer checks;
    integer failures;

    pipe_mem_wb dut(
         .clk                 (clk)
        ,.rst                 (rst)
        ,.ex_mem_valid        (ex_mem_valid)
        ,.ex_mem_pc           (ex_mem_pc)
        ,.ex_mem_rd_addr      (ex_mem_rd_addr)
        ,.mem_stage_wb_ctl    (mem_stage_wb_ctl)
        ,.wb_reg_rd_data      (wb_reg_rd_data)
        ,.mem_wb_valid        (mem_wb_valid)
        ,.mem_wb_pc           (mem_wb_pc)
        ,.mem_wb_rd_addr      (mem_wb_rd_addr)
        ,.mem_wb_wb_ctl       (mem_wb_wb_ctl)
        ,.mem_wb_wb_data      (mem_wb_wb_data)
        ,.mem_wb_forward_valid(mem_wb_forward_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("[FAIL] %0s", message);
            end else begin
                $display("[PASS] %0s", message);
            end
        end
    endtask

    initial begin
        checks = 0;
        failures = 0;
        rst = `KLDJ_RSTABLE;
        ex_mem_valid = 1'b0;
        ex_mem_pc = 32'b0;
        ex_mem_rd_addr = 5'b0;
        mem_stage_wb_ctl = 1'b0;
        wb_reg_rd_data = 32'b0;

        tick;
        check(!mem_wb_valid && !mem_wb_forward_valid, "reset clears valid metadata");

        rst = ~`KLDJ_RSTABLE;
        ex_mem_valid = 1'b1;
        ex_mem_pc = 32'h80000100;
        ex_mem_rd_addr = 5'd7;
        mem_stage_wb_ctl = 1'b1;
        wb_reg_rd_data = 32'h12345678;
        tick;
        check(mem_wb_valid && mem_wb_forward_valid, "forward-valid aligns with a writable nonzero rd");
        check(mem_wb_rd_addr == 5'd7 && mem_wb_wb_data == 32'h12345678,
              "forward-valid payload is captured in the same cycle");

        ex_mem_valid = 1'b1;
        ex_mem_rd_addr = 5'd0;
        mem_stage_wb_ctl = 1'b1;
        wb_reg_rd_data = 32'hcafebabe;
        tick;
        check(mem_wb_valid && !mem_wb_forward_valid, "x0 never forwards");

        ex_mem_valid = 1'b1;
        ex_mem_rd_addr = 5'd9;
        mem_stage_wb_ctl = 1'b0;
        wb_reg_rd_data = 32'hdeadbeef;
        tick;
        check(mem_wb_valid && !mem_wb_forward_valid, "non-writeback instruction never forwards");

        ex_mem_valid = 1'b0;
        ex_mem_rd_addr = 5'd10;
        mem_stage_wb_ctl = 1'b1;
        tick;
        check(!mem_wb_valid && !mem_wb_forward_valid, "invalid MEM instruction clears forwarding");

        if (failures == 0)
            $display("PIPE_MEM_WB TEST PASSED (%0d checks)", checks);
        else
            $display("PIPE_MEM_WB TEST FAILED (%0d/%0d failed)", failures, checks);
        $finish;
    end

endmodule
