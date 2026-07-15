`include "../define.v"

module ex_bpu_ctrl #(
     parameter BPU_INDEX_WIDTH = 6
)(
     input  wire                  id_ex_valid
    ,input  wire [`KLDJ_PC]       id_ex_pc
    ,input  wire [`KLDJ_PC]       id_ex_snpc
    ,input  wire                  id_ex_pred_taken
    ,input  wire                  id_ex_pred_is_jalr
    ,input  wire [`KLDJ_PC]       id_ex_pred_target
    ,input  wire [BPU_INDEX_WIDTH-1:0] id_ex_pred_pht_idx
    ,input  wire                  id_ex_branch_op
    ,input  wire                  id_ex_jal_op
    ,input  wire                  id_ex_jalr_op
    ,input  wire                  id_ex_jalr_check_en
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
    ,output wire                  bpu_update_is_jalr
);

    wire ex_actual_redirect;
    wire direction_miss;
    wire indirect_target_miss;

    assign ex_actual_redirect = exu_jump_raw || is_ecall || is_mret;
    assign ex_actual_taken    = id_ex_valid && ex_actual_redirect;
    assign ex_correct_pc      = is_ecall ? mtvec_val :
                                ex_actual_redirect ? exu_jump_pc_raw :
                                id_ex_snpc;

    assign direction_miss = id_ex_pred_taken ^ ex_actual_redirect;
    // Only an adopted indirect prediction needs target validation. Direct
    // branches and static JAL predictions stay off the 32-bit compare path.
    assign indirect_target_miss = id_ex_jalr_check_en &&
                                  (id_ex_pred_target[31:1] != exu_jump_pc_raw[31:1]);
    assign ex_redirect = id_ex_valid && (direction_miss || indirect_target_miss);

    assign bpu_update_valid  = id_ex_valid &&
                               (id_ex_branch_op || id_ex_jal_op || id_ex_jalr_op);
    assign bpu_update_pc     = id_ex_pc;
    assign bpu_update_pht_idx = id_ex_pred_pht_idx;
    assign bpu_update_taken  = (id_ex_jal_op || id_ex_jalr_op) ? 1'b1 :
                               id_ex_branch_op ? exu_jump_raw :
                               1'b0;
    assign bpu_update_target = exu_jump_pc_raw;
    assign bpu_update_is_jalr = id_ex_jalr_op;

endmodule
