`timescale 1ns/1ps

module ex_bpu_ctrl_tb;
    reg         id_ex_valid;
    reg  [31:0] id_ex_pc;
    reg  [31:0] id_ex_snpc;
    reg         id_ex_pred_taken;
    reg         id_ex_pred_is_jalr;
    reg  [31:0] id_ex_pred_target;
    reg  [5:0]  id_ex_pred_pht_idx;
    reg         id_ex_branch_op;
    reg         id_ex_jal_op;
    reg         id_ex_jalr_op;
    wire        id_ex_jalr_check_en = id_ex_pred_taken &&
                                        id_ex_pred_is_jalr && id_ex_jalr_op;
    reg         exu_jump_raw;
    reg  [31:0] exu_jump_pc_raw;
    reg         is_ecall;
    reg         is_mret;
    reg  [31:0] mtvec_val;

    wire        ex_actual_taken;
    wire [31:0] ex_correct_pc;
    wire        ex_redirect;
    wire        bpu_update_valid;
    wire [31:0] bpu_update_pc;
    wire [5:0]  bpu_update_pht_idx;
    wire        bpu_update_taken;
    wire [31:0] bpu_update_target;
    wire        bpu_update_is_jalr;

    integer checks;

    ex_bpu_ctrl dut (
         .id_ex_valid(id_ex_valid)
        ,.id_ex_pc(id_ex_pc)
        ,.id_ex_snpc(id_ex_snpc)
        ,.id_ex_pred_taken(id_ex_pred_taken)
        ,.id_ex_pred_is_jalr(id_ex_pred_is_jalr)
        ,.id_ex_pred_target(id_ex_pred_target)
        ,.id_ex_pred_pht_idx(id_ex_pred_pht_idx)
        ,.id_ex_branch_op(id_ex_branch_op)
        ,.id_ex_jal_op(id_ex_jal_op)
        ,.id_ex_jalr_op(id_ex_jalr_op)
        ,.id_ex_jalr_check_en(id_ex_jalr_check_en)
        ,.exu_jump_raw(exu_jump_raw)
        ,.exu_jump_pc_raw(exu_jump_pc_raw)
        ,.is_ecall(is_ecall)
        ,.is_mret(is_mret)
        ,.mtvec_val(mtvec_val)
        ,.ex_actual_taken(ex_actual_taken)
        ,.ex_correct_pc(ex_correct_pc)
        ,.ex_redirect(ex_redirect)
        ,.bpu_update_valid(bpu_update_valid)
        ,.bpu_update_pc(bpu_update_pc)
        ,.bpu_update_pht_idx(bpu_update_pht_idx)
        ,.bpu_update_taken(bpu_update_taken)
        ,.bpu_update_target(bpu_update_target)
        ,.bpu_update_is_jalr(bpu_update_is_jalr)
    );

    task expect_bit;
        input actual;
        input expected;
        input [8*48-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("FAIL: %0s, expected=%b actual=%b", label, expected, actual);
                $fatal(1);
            end
        end
    endtask

    task expect_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("FAIL: %0s, expected=%h actual=%h", label, expected, actual);
                $fatal(1);
            end
        end
    endtask

    task apply_defaults;
        begin
            id_ex_valid        = 1'b1;
            id_ex_pc           = 32'h8000_0100;
            id_ex_snpc         = 32'h8000_0104;
            id_ex_pred_taken   = 1'b0;
            id_ex_pred_is_jalr = 1'b0;
            id_ex_pred_target  = 32'h8000_0200;
            id_ex_pred_pht_idx = 6'h25;
            id_ex_branch_op    = 1'b0;
            id_ex_jal_op       = 1'b0;
            id_ex_jalr_op      = 1'b0;
            exu_jump_raw       = 1'b0;
            exu_jump_pc_raw    = 32'h8000_0300;
            is_ecall           = 1'b0;
            is_mret            = 1'b0;
            mtvec_val          = 32'h8000_1000;
        end
    endtask

    initial begin
        checks = 0;

        // Invalid pipeline entries must never redirect or train the predictor.
        apply_defaults();
        id_ex_valid     = 1'b0;
        id_ex_branch_op = 1'b1;
        exu_jump_raw    = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b0, "invalid actual taken");
        expect_bit(ex_redirect, 1'b0, "invalid redirect");
        expect_bit(bpu_update_valid, 1'b0, "invalid update");

        // A correctly predicted not-taken branch continues at SNPC.
        apply_defaults();
        id_ex_branch_op = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b0, "correct not-taken redirect");
        expect_word(ex_correct_pc, id_ex_snpc, "correct not-taken PC");
        expect_bit(bpu_update_valid, 1'b1, "not-taken branch update valid");
        expect_bit(bpu_update_taken, 1'b0, "not-taken branch update value");

        // An unpredicted taken branch redirects to the resolved target.
        apply_defaults();
        id_ex_branch_op = 1'b1;
        exu_jump_raw    = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b1, "taken branch actual taken");
        expect_bit(ex_redirect, 1'b1, "taken branch direction miss");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "taken branch target");
        expect_bit(bpu_update_valid, 1'b1, "taken branch update valid");
        expect_bit(bpu_update_taken, 1'b1, "taken branch update value");
        expect_word(bpu_update_pc, id_ex_pc, "branch update PC");
        expect_word({26'b0, bpu_update_pht_idx}, {26'b0, id_ex_pred_pht_idx},
                    "branch update PHT index");
        expect_word(bpu_update_target, exu_jump_pc_raw, "branch update target");

        // A predicted branch that resolves not-taken redirects to SNPC.
        apply_defaults();
        id_ex_branch_op  = 1'b1;
        id_ex_pred_taken = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "not-taken branch direction miss");
        expect_word(ex_correct_pc, id_ex_snpc, "not-taken recovery PC");
        expect_bit(bpu_update_taken, 1'b0, "not-taken branch training");

        // Current predictions are direct; target mismatch alone must not redirect.
        apply_defaults();
        id_ex_branch_op   = 1'b1;
        id_ex_pred_taken  = 1'b1;
        id_ex_pred_target = 32'hdead_beef;
        exu_jump_raw      = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b0, "direct prediction ignores target compare");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "direct resolved target");

        // A correctly predicted JAL does not recover and still trains the BTB.
        apply_defaults();
        id_ex_jal_op     = 1'b1;
        id_ex_pred_taken = 1'b1;
        exu_jump_raw     = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b0, "correct JAL prediction");
        expect_bit(bpu_update_valid, 1'b1, "JAL update valid");
        expect_bit(bpu_update_taken, 1'b1, "JAL update taken");
        expect_bit(bpu_update_is_jalr, 1'b0, "JAL direct update type");

        // A cold JALR creates a direction miss and allocates an indirect entry.
        apply_defaults();
        id_ex_jalr_op = 1'b1;
        exu_jump_raw  = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "unpredicted JALR redirect");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "JALR recovery PC");
        expect_bit(bpu_update_valid, 1'b1, "JALR update valid");
        expect_bit(bpu_update_taken, 1'b1, "JALR update taken");
        expect_bit(bpu_update_is_jalr, 1'b1, "JALR indirect update type");

        // A BTB-predicted JALR with the right target avoids recovery.
        apply_defaults();
        id_ex_jalr_op      = 1'b1;
        id_ex_pred_taken   = 1'b1;
        id_ex_pred_is_jalr = 1'b1;
        id_ex_pred_target  = exu_jump_pc_raw;
        exu_jump_raw       = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b0, "correct JALR target prediction");
        expect_bit(bpu_update_valid, 1'b1, "predicted JALR update valid");

        // Direction is taken in both cases, so a changed indirect target must
        // independently request recovery.
        apply_defaults();
        id_ex_jalr_op      = 1'b1;
        id_ex_pred_taken   = 1'b1;
        id_ex_pred_is_jalr = 1'b1;
        id_ex_pred_target  = 32'h8000_0400;
        exu_jump_raw       = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "JALR target mismatch redirect");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "JALR target recovery PC");

        // ECALL recovers to mtvec even though exu_jump_raw is low.
        apply_defaults();
        is_ecall = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b1, "ECALL actual taken");
        expect_bit(ex_redirect, 1'b1, "ECALL redirect");
        expect_word(ex_correct_pc, mtvec_val, "ECALL mtvec target");
        expect_bit(bpu_update_valid, 1'b0, "ECALL no BPU update");

        // MRET recovers through the resolved EXU target.
        apply_defaults();
        is_mret = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b1, "MRET actual taken");
        expect_bit(ex_redirect, 1'b1, "MRET redirect");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "MRET recovery PC");
        expect_bit(bpu_update_valid, 1'b0, "MRET no BPU update");

        $display("PASS: ex_bpu_ctrl_tb (%0d checks)", checks);
        $finish;
    end
endmodule
