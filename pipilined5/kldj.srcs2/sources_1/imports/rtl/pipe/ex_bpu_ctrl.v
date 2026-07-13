`include "../define.v"

module ex_bpu_ctrl #(
     parameter BPU_INDEX_WIDTH = 6
)(
     input  wire                  ex1_ex2_valid
    ,input  wire [`KLDJ_PC]       ex1_ex2_pc
    ,input  wire [`KLDJ_PC]       ex1_ex2_snpc
    ,input  wire                  ex1_ex2_pred_taken
    // Reserved for target validation when indirect/RAS prediction is added.
    ,input  wire [`KLDJ_PC]       ex1_ex2_pred_target
    ,input  wire [BPU_INDEX_WIDTH-1:0] ex1_ex2_pred_pht_idx
    ,input  wire [17:0]           ex1_ex2_exu_op
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
);

    wire ex_is_branch_op;
    wire ex_is_jal_op;
    wire ex_actual_redirect;
    wire direction_miss;

    assign ex_is_branch_op = (ex1_ex2_exu_op >= 18'h14) && (ex1_ex2_exu_op <= 18'h19);
    assign ex_is_jal_op    = (ex1_ex2_exu_op == 18'h1c);

    assign ex_actual_redirect = exu_jump_raw || is_ecall || is_mret;
    assign ex_actual_taken    = ex1_ex2_valid && ex_actual_redirect;
    assign ex_correct_pc      = is_ecall ? mtvec_val :
                                ex_actual_redirect ? exu_jump_pc_raw :
                                ex1_ex2_snpc;

    assign direction_miss = ex1_ex2_pred_taken ^ ex_actual_redirect;
    assign ex_redirect    = ex1_ex2_valid && direction_miss;

    assign bpu_update_valid  = ex1_ex2_valid && (ex_is_branch_op || ex_is_jal_op);
    assign bpu_update_pc     = ex1_ex2_pc;
    assign bpu_update_pht_idx = ex1_ex2_pred_pht_idx;
    assign bpu_update_taken  = ex_is_jal_op ? 1'b1 :
                               ex_is_branch_op ? exu_jump_raw :
                               1'b0;
    assign bpu_update_target = exu_jump_pc_raw;

endmodule
