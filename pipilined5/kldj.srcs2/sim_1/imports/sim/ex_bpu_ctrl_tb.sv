`timescale 1ns/1ps

module ex_bpu_ctrl_tb;
    reg         id_ex_valid;
    reg  [31:0] id_ex_pc;
    reg  [31:0] id_ex_snpc;
    reg         id_ex_pred_taken;
    reg  [31:0] id_ex_pred_target;
    reg  [5:0]  id_ex_pred_pht_idx;
    reg  [17:0] id_ex_exu_op;
    reg  [4:0]  id_ex_rd_addr;
    reg  [4:0]  id_ex_rs1_addr;
    reg  [31:0] id_ex_data2;
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
    wire        ras_push;
    wire        ras_pop;
    wire [31:0] ras_push_addr;

    integer checks;

    ex_bpu_ctrl dut (
         .id_ex_valid(id_ex_valid)
        ,.id_ex_pc(id_ex_pc)
        ,.id_ex_snpc(id_ex_snpc)
        ,.id_ex_pred_taken(id_ex_pred_taken)
        ,.id_ex_pred_target(id_ex_pred_target)
        ,.id_ex_pred_pht_idx(id_ex_pred_pht_idx)
        ,.id_ex_exu_op(id_ex_exu_op)
        ,.id_ex_rd_addr(id_ex_rd_addr)
        ,.id_ex_rs1_addr(id_ex_rs1_addr)
        ,.id_ex_data2(id_ex_data2)
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
        ,.ras_push(ras_push)
        ,.ras_pop(ras_pop)
        ,.ras_push_addr(ras_push_addr)
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
            id_ex_pred_target  = 32'h8000_0200;
            id_ex_pred_pht_idx = 6'h25;
            id_ex_exu_op       = 18'h00;
            id_ex_rd_addr      = 5'd0;
            id_ex_rs1_addr     = 5'd0;
            id_ex_data2        = 32'd0;
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
        id_ex_valid  = 1'b0;
        id_ex_exu_op = 18'h14;
        exu_jump_raw = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b0, "invalid actual taken");
        expect_bit(ex_redirect, 1'b0, "invalid redirect");
        expect_bit(bpu_update_valid, 1'b0, "invalid update");

        // A correctly predicted not-taken branch continues at SNPC.
        apply_defaults();
        id_ex_exu_op = 18'h14;
        #1;
        expect_bit(ex_redirect, 1'b0, "correct not-taken redirect");
        expect_word(ex_correct_pc, id_ex_snpc, "correct not-taken PC");
        expect_bit(bpu_update_valid, 1'b1, "not-taken branch update valid");
        expect_bit(bpu_update_taken, 1'b0, "not-taken branch update value");

        // An unpredicted taken branch redirects to the resolved target.
        apply_defaults();
        id_ex_exu_op = 18'h15;
        exu_jump_raw = 1'b1;
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
        id_ex_exu_op     = 18'h16;
        id_ex_pred_taken = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "not-taken branch direction miss");
        expect_word(ex_correct_pc, id_ex_snpc, "not-taken recovery PC");
        expect_bit(bpu_update_taken, 1'b0, "not-taken branch training");

        // A taken prediction with a mismatched target must recover.  This is
        // essential for indirect/RAS predictions where direction is correct
        // but the target can be stale.
        apply_defaults();
        id_ex_exu_op      = 18'h17;
        id_ex_pred_taken  = 1'b1;
        id_ex_pred_target = 32'hdead_beef;
        exu_jump_raw      = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "target mismatch redirects");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "direct resolved target");

        // A correctly predicted JAL does not recover and still trains the BTB.
        apply_defaults();
        id_ex_exu_op     = 18'h1c;
        id_ex_rd_addr    = 5'd1;
        id_ex_pred_taken = 1'b1;
        id_ex_pred_target = exu_jump_pc_raw;
        exu_jump_raw     = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b0, "correct JAL prediction");
        expect_bit(bpu_update_valid, 1'b1, "JAL update valid");
        expect_bit(bpu_update_taken, 1'b1, "JAL update taken");
        expect_bit(ras_push, 1'b1, "JAL call pushes RAS");
        expect_bit(ras_pop, 1'b0, "JAL call does not pop RAS");
        expect_word(ras_push_addr, id_ex_snpc, "JAL RAS return address");

        // An indirect JALR call also pushes its resolved return address.
        apply_defaults();
        id_ex_exu_op   = 18'h09;
        id_ex_rd_addr  = 5'd1;
        id_ex_rs1_addr = 5'd5;
        exu_jump_raw   = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "unpredicted JALR call redirect");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "JALR recovery PC");
        expect_bit(bpu_update_valid, 1'b0, "JALR does not train current BPU");
        expect_bit(ras_push, 1'b1, "JALR call pushes RAS");
        expect_bit(ras_pop, 1'b0, "JALR call does not pop RAS");

        // A canonical ret has a predicted target and pops the RAS.  No
        // redirect is needed when the predicted target matches EX.
        apply_defaults();
        id_ex_exu_op      = 18'h09;
        id_ex_rd_addr     = 5'd0;
        id_ex_rs1_addr    = 5'd1;
        id_ex_data2       = 32'd0;
        id_ex_pred_taken  = 1'b1;
        id_ex_pred_target = exu_jump_pc_raw;
        exu_jump_raw      = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b0, "correct RAS return prediction");
        expect_bit(ras_push, 1'b0, "return does not push RAS");
        expect_bit(ras_pop, 1'b1, "canonical return pops RAS");

        // A stale RAS top is a target miss even though both prediction and
        // resolved return are taken, so EX must redirect to the true target.
        apply_defaults();
        id_ex_exu_op      = 18'h09;
        id_ex_rd_addr     = 5'd0;
        id_ex_rs1_addr    = 5'd1;
        id_ex_data2       = 32'd0;
        id_ex_pred_taken  = 1'b1;
        id_ex_pred_target = 32'hdead_beef;
        exu_jump_raw      = 1'b1;
        #1;
        expect_bit(ex_redirect, 1'b1, "stale RAS target redirects");
        expect_bit(ras_pop, 1'b1, "stale return still pops RAS");

        // A JALR through x5 that writes x1 is a call, not a return.  Also
        // reject non-zero-offset JALR x0,x1 as a RAS pop hint.
        apply_defaults();
        id_ex_exu_op   = 18'h09;
        id_ex_rd_addr  = 5'd0;
        id_ex_rs1_addr = 5'd1;
        id_ex_data2    = 32'd4;
        exu_jump_raw   = 1'b1;
        #1;
        expect_bit(ras_pop, 1'b0, "noncanonical JALR does not pop RAS");

        // ECALL recovers to mtvec even though exu_jump_raw is low.
        apply_defaults();
        id_ex_exu_op = 18'h34;
        is_ecall     = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b1, "ECALL actual taken");
        expect_bit(ex_redirect, 1'b1, "ECALL redirect");
        expect_word(ex_correct_pc, mtvec_val, "ECALL mtvec target");
        expect_bit(bpu_update_valid, 1'b0, "ECALL no BPU update");

        // MRET recovers through the resolved EXU target.
        apply_defaults();
        id_ex_exu_op = 18'h35;
        is_mret      = 1'b1;
        #1;
        expect_bit(ex_actual_taken, 1'b1, "MRET actual taken");
        expect_bit(ex_redirect, 1'b1, "MRET redirect");
        expect_word(ex_correct_pc, exu_jump_pc_raw, "MRET recovery PC");
        expect_bit(bpu_update_valid, 1'b0, "MRET no BPU update");

        $display("PASS: ex_bpu_ctrl_tb (%0d checks)", checks);
        $finish;
    end
endmodule
