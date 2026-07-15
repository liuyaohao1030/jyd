`timescale 1ns/1ps
`include "define.v"

module bpu_tb;
    reg clk = 1'b0;
    reg rst;
    reg [31:0] lookup_pc;
    wire pred_taken;
    wire [31:0] pred_target;
    wire btb_hit;
    wire pred_is_jalr;
    wire [5:0] lookup_pht_idx;
    reg update_valid;
    reg [31:0] update_pc;
    reg [5:0] update_pht_idx;
    reg update_taken;
    reg [31:0] update_target;
    reg update_is_jalr;

    always #5 clk = ~clk;

    bpu dut(
         .clk(clk), .rst(rst)
        ,.lookup_pc(lookup_pc)
        ,.pred_taken(pred_taken), .pred_target(pred_target)
        ,.btb_hit(btb_hit), .pred_is_jalr(pred_is_jalr)
        ,.lookup_pht_idx(lookup_pht_idx)
        ,.update_valid(update_valid), .update_pc(update_pc)
        ,.update_pht_idx(update_pht_idx), .update_taken(update_taken)
        ,.update_target(update_target), .update_is_jalr(update_is_jalr)
    );

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task update;
        input [31:0] pc;
        input [5:0] pht_idx;
        input taken;
        input [31:0] target;
        begin
            update_pc = pc;
            update_pht_idx = pht_idx;
            update_taken = taken;
            update_target = target;
            update_is_jalr = 1'b0;
            update_valid = 1'b1;
            tick;
            update_valid = 1'b0;
            // Predictor table writes are intentionally pipelined by one cycle.
            tick;
        end
    endtask

    task update_jalr;
        input [31:0] pc;
        input [5:0] pht_idx;
        input [31:0] target;
        begin
            update_pc = pc;
            update_pht_idx = pht_idx;
            update_taken = 1'b1;
            update_target = target;
            update_is_jalr = 1'b1;
            update_valid = 1'b1;
            tick;
            update_valid = 1'b0;
            tick;
        end
    endtask

    initial begin
        rst = 1'b1;
        lookup_pc = 32'h8000_0040;
        update_valid = 1'b0;
        update_pc = 32'b0;
        update_pht_idx = 6'b0;
        update_taken = 1'b0;
        update_target = 32'b0;
        update_is_jalr = 1'b0;
        repeat (2) tick;
        rst = 1'b0;
        #1;

        if (btb_hit !== 1'b0 || pred_taken !== 1'b0)
            $fatal(1, "reset state predicted a branch");

        // Same index as lookup PC, different tag must miss after replacement.
        update(32'h8000_0040, 6'd16, 1'b1, 32'h8000_0080);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b10 ||
            dut.u_gshare_btb_core.btb_valid[16] !== 1'b1)
            $fatal(1, "taken update did not allocate BTB/PHT");
        if (dut.u_gshare_btb_core.btb_data[16][31:0] !== 32'h8000_0080)
            $fatal(1, "BTB target mismatch");

        update(32'h8000_0040, 6'd16, 1'b1, 32'h8000_0080);
        update(32'h8000_0040, 6'd16, 1'b1, 32'h8000_0080);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b11)
            $fatal(1, "PHT did not saturate high");

        // Saturate low and verify no wraparound.
        update(32'h8000_0040, 6'd16, 1'b0, 32'h8000_0080);
        update(32'h8000_0040, 6'd16, 1'b0, 32'h8000_0080);
        update(32'h8000_0040, 6'd16, 1'b0, 32'h8000_0080);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b00)
            $fatal(1, "PHT did not saturate low");
        update(32'h8000_0040, 6'd16, 1'b0, 32'h8000_0080);
        if (dut.u_gshare_btb_core.pht[16] !== 2'b00)
            $fatal(1, "PHT wrapped below zero");

        // Drive GHR to all ones, then train the active Gshare entry.
        repeat (6) update(32'h8000_0040, 6'd16, 1'b1, 32'h8000_0080);
        update(32'h8000_0040, 6'd47, 1'b1, 32'h8000_0080);
        update(32'h8000_0040, 6'd47, 1'b1, 32'h8000_0080);
        lookup_pc = 32'h8000_0040;
        #1;
        if (btb_hit !== 1'b1 || pred_taken !== 1'b1 ||
            pred_target !== 32'h8000_0080)
            $fatal(1, "BTB lookup failed");

        update(32'h9000_0040, 6'd16, 1'b1, 32'h9000_0100);
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

        // Consecutive updates must pass through the one-entry write pipeline
        // without dropping either request.
        update_pc = 32'h8000_000c;
        update_pht_idx = 6'd3;
        update_taken = 1'b1;
        update_target = 32'h8000_0100;
        update_valid = 1'b1;
        tick;
        update_pc = 32'h8000_0014;
        update_pht_idx = 6'd5;
        update_target = 32'h8000_0200;
        tick;
        update_valid = 1'b0;
        tick;
        if (dut.u_gshare_btb_core.pht[3] !== 2'b10 ||
            dut.u_gshare_btb_core.pht[5] !== 2'b10)
            $fatal(1, "back-to-back PHT updates were not preserved");
        if (dut.u_gshare_btb_core.btb_data[3][31:0] !== 32'h8000_0100 ||
            dut.u_gshare_btb_core.btb_data[5][31:0] !== 32'h8000_0200)
            $fatal(1, "back-to-back BTB updates were not preserved");

        // A JALR allocates an unconditional indirect BTB entry without
        // changing directional history or the PHT.
        rst = 1'b1;
        tick;
        rst = 1'b0;
        lookup_pc = 32'h8000_0040;
        update_jalr(32'h8000_0040, 6'd16, 32'h8000_0300);
        #1;
        if (btb_hit !== 1'b1 || pred_taken !== 1'b1 ||
            pred_is_jalr !== 1'b1 || pred_target !== 32'h8000_0300)
            $fatal(1, "JALR BTB prediction failed");
        if (dut.u_gshare_btb_core.ghr !== 6'd0 ||
            dut.u_gshare_btb_core.pht_valid[16] !== 1'b0 ||
            dut.u_gshare_btb_core.btb_is_jalr[16] !== 1'b1)
            $fatal(1, "JALR update polluted GShare state or lost type");

        // A later direct-control update at the same PC must clear the
        // indirect type and restore PHT-controlled prediction.
        update(32'h8000_0040, 6'd16, 1'b1, 32'h8000_0080);
        #1;
        if (btb_hit !== 1'b1 || pred_is_jalr !== 1'b0 ||
            pred_target !== 32'h8000_0080 ||
            dut.u_gshare_btb_core.pht[16] !== 2'b10)
            $fatal(1, "direct update did not replace JALR BTB type");

        $display("BPU UNIT TEST PASSED (GHR=%0d)", dut.u_gshare_btb_core.ghr);
        $finish;
    end
endmodule
