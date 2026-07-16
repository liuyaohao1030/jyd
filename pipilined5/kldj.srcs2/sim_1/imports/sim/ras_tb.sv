`timescale 1ns/1ps

`include "define.v"

module ras_tb;
    reg         clk = 1'b0;
    reg         rst;
    reg         push;
    reg         pop;
    reg [31:0]  push_addr;
    wire        valid;
    wire [31:0] top_addr;

    integer checks;

    always #5 clk = ~clk;

    return_address_stack #(
         .DEPTH(4)
    ) dut (
         .clk      (clk      )
        ,.rst      (rst      )
        ,.push     (push     )
        ,.pop      (pop      )
        ,.push_addr(push_addr)
        ,.valid    (valid    )
        ,.top_addr (top_addr )
    );

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input [8*64-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected)
                $fatal(1, "RAS %0s: expected=%b actual=%b", label, expected, actual);
        end
    endtask

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*64-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected)
                $fatal(1, "RAS %0s: expected=%h actual=%h", label, expected, actual);
        end
    endtask

    task do_push;
        input [31:0] addr;
        begin
            push      = 1'b1;
            pop       = 1'b0;
            push_addr = addr;
            tick;
            push = 1'b0;
        end
    endtask

    task do_pop;
        begin
            push = 1'b0;
            pop  = 1'b1;
            tick;
            pop = 1'b0;
        end
    endtask

    initial begin
        checks    = 0;
        rst       = `KLDJ_RSTABLE;
        push      = 1'b0;
        pop       = 1'b0;
        push_addr = 32'b0;

        repeat (2) tick;
        rst = ~`KLDJ_RSTABLE;
        #1;
        expect_bit(valid, 1'b0, "empty after reset");

        // Nested calls return in strict LIFO order.
        do_push(32'h8000_0010);
        expect_bit(valid, 1'b1, "valid after first push");
        expect_word(top_addr, 32'h8000_0010, "first top");
        do_push(32'h8000_0020);
        expect_word(top_addr, 32'h8000_0020, "nested top");
        do_pop();
        expect_word(top_addr, 32'h8000_0010, "pop restores outer return");
        do_pop();
        expect_bit(valid, 1'b0, "empty after matched pops");

        // Underflow must not manufacture a prediction.
        do_pop();
        expect_bit(valid, 1'b0, "underflow remains empty");

        // Same-cycle pop/push replaces only the top entry.
        do_push(32'h8000_0030);
        do_push(32'h8000_0040);
        push      = 1'b1;
        pop       = 1'b1;
        push_addr = 32'h8000_0050;
        tick;
        push = 1'b0;
        pop  = 1'b0;
        expect_word(top_addr, 32'h8000_0050, "pop push replaces top");
        do_pop();
        expect_word(top_addr, 32'h8000_0030, "replacement preserves outer entry");

        // Overflow keeps the newest DEPTH entries.  For a depth-four stack,
        // the oldest address (0x10) is discarded when 0x50 is pushed.
        rst = `KLDJ_RSTABLE;
        tick;
        rst = ~`KLDJ_RSTABLE;
        do_push(32'h0000_0010);
        do_push(32'h0000_0020);
        do_push(32'h0000_0030);
        do_push(32'h0000_0040);
        do_push(32'h0000_0050);
        expect_word(top_addr, 32'h0000_0050, "overflow newest top");
        do_pop();
        expect_word(top_addr, 32'h0000_0040, "overflow pop one");
        do_pop();
        expect_word(top_addr, 32'h0000_0030, "overflow pop two");
        do_pop();
        expect_word(top_addr, 32'h0000_0020, "overflow drops oldest");
        do_pop();
        expect_bit(valid, 1'b0, "overflow stack drains cleanly");

        $display("RAS UNIT TEST PASSED (%0d checks)", checks);
        $finish;
    end
endmodule
