`include "../define.v"

module ex_bpu_ctrl #(
     parameter BPU_INDEX_WIDTH = 6
)(
     input  wire                  id_ex_valid
    ,input  wire [`KLDJ_PC]       id_ex_pc
    ,input  wire [`KLDJ_PC]       id_ex_snpc
    ,input  wire                  id_ex_pred_taken
    // Validates direct, indirect, and RAS-predicted targets in EX.
    ,input  wire [`KLDJ_PC]       id_ex_pred_target
    ,input  wire [BPU_INDEX_WIDTH-1:0] id_ex_pred_pht_idx
    ,input  wire [17:0]           id_ex_exu_op
    ,input  wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input  wire [`KLDJ_REGADDR]  id_ex_rs1_addr
    ,input  wire [`KLDJ_DATA]     id_ex_data2
    ,input  wire                  exu_jump_raw
    ,input  wire [`KLDJ_PC]       exu_jump_pc_raw
    ,input  wire                  is_ecall
    ,input  wire                  is_mret
    ,input  wire [`KLDJ_PC]       mtvec_val

    ,output wire                  ex_actual_taken
    ,output wire [`KLDJ_PC]       ex_correct_pc
    ,output wire                  ex_redirect

    ,output wire                  bpu_update_valid
    ,output wire [`KLDJ_PC]       bpu_update_pc
    ,output wire [BPU_INDEX_WIDTH-1:0] bpu_update_pht_idx
    ,output wire                  bpu_update_taken
    ,output wire [`KLDJ_PC]       bpu_update_target

    ,output wire                  ras_push
    ,output wire                  ras_pop
    ,output wire [`KLDJ_PC]       ras_push_addr
);

    wire ex_is_branch_op;
    wire ex_is_jal_op;
    wire ex_is_jalr_op;
    wire ex_actual_redirect;
    wire direction_miss;
    wire target_miss;
    wire ex_rd_is_link;
    wire ex_rs1_is_link;
    wire ex_is_ras_return;

    assign ex_is_branch_op = (id_ex_exu_op >= 18'h14) && (id_ex_exu_op <= 18'h19);
    assign ex_is_jal_op    = (id_ex_exu_op == 18'h1c);
    assign ex_is_jalr_op   = (id_ex_exu_op == 18'h09);
    assign ex_rd_is_link   = (id_ex_rd_addr == 5'd1) || (id_ex_rd_addr == 5'd5);
    assign ex_rs1_is_link  = (id_ex_rs1_addr == 5'd1) || (id_ex_rs1_addr == 5'd5);
    // Restrict pop to the canonical RISC-V return form.  In particular,
    // jalr x1, 0(x5) is an indirect call in irom-v2, not a return.
    assign ex_is_ras_return = ex_is_jalr_op && (id_ex_rd_addr == 5'd0) &&
                              ex_rs1_is_link && (id_ex_data2 == `KLDJ_ZERO32);

    assign ex_actual_redirect = exu_jump_raw || is_ecall || is_mret;
    assign ex_actual_taken    = id_ex_valid && ex_actual_redirect;
    assign ex_correct_pc      = is_ecall ? mtvec_val :
                                ex_actual_redirect ? exu_jump_pc_raw :
                                id_ex_snpc;

    assign direction_miss = id_ex_pred_taken ^ ex_actual_redirect;
    // A RAS/indirect prediction can have the right direction but the wrong
    // target.  Direction-only recovery would then let the wrong path commit.
    assign target_miss    = id_ex_pred_taken && ex_actual_redirect &&
                            (id_ex_pred_target != ex_correct_pc);
    assign ex_redirect    = id_ex_valid && (direction_miss || target_miss);

    assign bpu_update_valid  = id_ex_valid && (ex_is_branch_op || ex_is_jal_op);
    assign bpu_update_pc     = id_ex_pc;
    assign bpu_update_pht_idx = id_ex_pred_pht_idx;
    assign bpu_update_taken  = ex_is_jal_op ? 1'b1 :
                               ex_is_branch_op ? exu_jump_raw :
                               1'b0;
    assign bpu_update_target = exu_jump_pc_raw;

    // Update RAS only after the control-transfer instruction reaches EX, so
    // instructions squashed by an earlier redirect never perturb the stack.
    // Both direct JAL and indirect JALR calls may use x1 (ra) or x5 (t0) as
    // their link register; only canonical returns pop the stack.
    assign ras_push      = id_ex_valid && (ex_is_jal_op || ex_is_jalr_op) &&
                           ex_rd_is_link;
    assign ras_pop       = id_ex_valid && ex_is_ras_return;
    assign ras_push_addr = id_ex_snpc;

endmodule
