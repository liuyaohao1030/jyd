`timescale 1ns/1ps
`include "define.v"

module bpu_tb;
    reg clk = 1'b0;
    reg rst;
    reg [31:0] lookup_pc;
    wire pred_taken;
    wire btb_hit;
    wire [5:0] lookup_pht_idx;
    reg update_valid;
    reg [31:0] update_pc;
    reg [5:0] update_pht_idx;
    reg update_taken;

    always #5 clk = ~clk;

    bpu dut(
        .clk(clk), .rst(rst)
        ,.lookup_pc(lookup_pc)
        ,.pred_taken(pred_taken)
        ,.btb_hit(btb_hit), .lookup_pht_idx(lookup_pht_idx)
        ,.update_valid(update_valid), .update_pc(update_pc)
        ,.update_pht_idx(update_pht_idx), .update_taken(update_taken)
    );

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task update;
        input [31:0] pc;
        input [5:0] pht_idx;
        input taken;
        begin
            update_pc = pc;
            update_pht_idx = pht_idx;
            update_taken = taken;
            update_valid = 1'b1;
            tick;
            update_valid = 1'b0;
        end
    endtask

    initial begin
        rst = 1'b1;
        lookup_pc = 32'h8000_0040;
        update_valid = 1'b0;
        update_pc = 32'b0;
        update_pht_idx = 6'b0;
        update_taken = 1'b0;
        repeat (2) tick;
        rst = 1'b0;
        #1;

        if (btb_hit !== 1'b0 || pred_taken !== 1'b0)
            $fatal(1, "reset state predicted a branch");

        // Same index as lookup PC, different tag must miss after replacement.
        update(32'h8000_0040, 6'd16, 1'b1);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b10 ||
            dut.u_gshare_btb_core.btb_valid[16] !== 1'b1)
            $fatal(1, "taken update did not allocate BTB/PHT");
        if (dut.u_gshare_btb_core.btb_tag[16] !== 24'h800000)
            $fatal(1, "BTB tag mismatch");

        update(32'h8000_0040, 6'd16, 1'b1);
        update(32'h8000_0040, 6'd16, 1'b1);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b11)
            $fatal(1, "PHT did not saturate high");

        // Saturate low and verify no wraparound.
        update(32'h8000_0040, 6'd16, 1'b0);
        update(32'h8000_0040, 6'd16, 1'b0);
        update(32'h8000_0040, 6'd16, 1'b0);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b00)
            $fatal(1, "PHT did not saturate low");
        update(32'h8000_0040, 6'd16, 1'b0);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b00)
            $fatal(1, "PHT wrapped below zero");

        // Drive GHR to all ones, then train the active Gshare entry.
        repeat (6) update(32'h8000_0040, 6'd16, 1'b1);
        update(32'h8000_0040, 6'd47, 1'b1);
        update(32'h8000_0040, 6'd47, 1'b1);
        lookup_pc = 32'h8000_0040;
        #1;
        if (btb_hit !== 1'b1 || pred_taken !== 1'b1)
            $fatal(1, "BTB lookup failed");

        update(32'h9000_0040, 6'd16, 1'b1);
        lookup_pc = 32'h8000_0040;
        #1;
        if (btb_hit !== 1'b0)
            $fatal(1, "BTB tag collision was not rejected");

        // Runtime reset must invalidate stale RAM contents without clearing them.
        rst = 1'b1;
        tick;
        rst = 1'b0;
        lookup_pc = 32'h9000_0040;
        #1;
        if (btb_hit !== 1'b0 || pred_taken !== 1'b0)
            $fatal(1, "runtime reset did not invalidate predictor state");

        $display("BPU UNIT TEST PASSED (GHR=%0d)", dut.u_gshare_btb_core.ghr);
        $finish;
    end
endmodule
