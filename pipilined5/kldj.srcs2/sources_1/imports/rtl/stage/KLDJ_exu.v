`include "../define.v"

module KLDJ_exu(
     input  wire                clk
    ,input  wire                rst
    ,input  wire                valid
    ,input  wire [`KLDJ_DATA]   data1
    ,input  wire [`KLDJ_DATA]   data2
    ,input  wire [`KLDJ_DATA]   data3
    ,input  wire [`KLDJ_DATA]   data4
    ,input  wire [17:0]         exu_op
    ,input  wire [9:0]          alu_ctrl
    ,output wire                exu_jump
    ,output wire [`KLDJ_DATA]   exu_jump_pc
    ,output wire [`KLDJ_DATA]   exu_res
    ,output wire [`KLDJ_DATA]   ex_mem_addr
    ,output wire                div_stall
    ,output wire                mul_stall
);

    wire [`KLDJ_DATA] alu_res;
    wire [3:0] cmp_res;

    KLDJ_alu u_KLDJ_alu(
         .op1    (data1)
        ,.op2    (data2)
        ,.alu_op (alu_ctrl)
        ,.alu_res(alu_res)
        ,.cmp_res(cmp_res)
    );

    wire is_mul_op = (exu_op == 18'h25) ||
                     (exu_op == 18'h26) ||
                     (exu_op == 18'h27) ||
                     (exu_op == 18'h28);
    wire [1:0] mul_op = (exu_op == 18'h25) ? 2'b00 :
                        (exu_op == 18'h26) ? 2'b01 :
                        (exu_op == 18'h27) ? 2'b10 :
                        (exu_op == 18'h28) ? 2'b11 :
                        2'b00;
    wire        mul_busy;
    wire        mul_done;
    wire [31:0] mul_result;
    wire        mul_start = valid && is_mul_op && !mul_busy && !mul_done;

    mul_ip_wrapper u_mul_ip_wrapper(
         .clk    (clk)
        ,.rst    (rst)
        ,.start  (mul_start)
        ,.op     (mul_op)
        ,.rs1    (data1)
        ,.rs2    (data2)
        ,.busy   (mul_busy)
        ,.done   (mul_done)
        ,.result (mul_result)
    );

    wire is_div_op = (exu_op == 18'h29) ||
                     (exu_op == 18'h2a) ||
                     (exu_op == 18'h2b) ||
                     (exu_op == 18'h2c);
    wire [1:0] div_op = (exu_op == 18'h29) ? 2'b00 :
                        (exu_op == 18'h2a) ? 2'b01 :
                        (exu_op == 18'h2b) ? 2'b10 :
                        (exu_op == 18'h2c) ? 2'b11 :
                        2'b00;
    wire        div_busy;
    wire        div_done;
    wire [31:0] div_result;
    wire        div_start = valid && is_div_op && !div_busy && !div_done;

    div_ip_wrapper u_div_ip_wrapper(
         .clk    (clk)
        ,.rst    (rst)
        ,.start  (div_start)
        ,.op     (div_op)
        ,.rs1    (data1)
        ,.rs2    (data2)
        ,.busy   (div_busy)
        ,.done   (div_done)
        ,.result (div_result)
    );

    assign mul_stall = valid && is_mul_op && !mul_done;
    assign div_stall = valid && is_div_op && !div_done;

    wire is_ge_res  = cmp_res[3];
    wire is_ne_res  = cmp_res[2];
    wire is_equ_res = cmp_res[1];
    wire is_lt_res  = cmp_res[0];

    wire branch_taken =
        (exu_op == 18'h14 && is_equ_res) | // beq
        (exu_op == 18'h15 && is_ne_res)  | // bne
        (exu_op == 18'h16 && is_lt_res)  | // blt
        (exu_op == 18'h17 && is_ge_res)  | // bge
        (exu_op == 18'h18 && is_lt_res)  | // bltu
        (exu_op == 18'h19 && is_ge_res)  ; // bgeu

    wire is_load_or_store = (exu_op >= 18'h1d) && (exu_op <= 18'h24);

    wire [`KLDJ_DATA] load_store_addr = data1 + data2;
    wire [`KLDJ_DATA] branch_target   = data3 + data4;
    wire [`KLDJ_DATA] jal_target      = data1 + data2;
    wire [`KLDJ_DATA] jalr_sum        = data1 + data2;
    wire [`KLDJ_DATA] jalr_target     = {jalr_sum[31:1], 1'b0};

    assign ex_mem_addr = is_load_or_store ? load_store_addr : `KLDJ_ZERO32;

    assign exu_res = is_mul_op ? mul_result :
                     is_div_op ? div_result :
                     (exu_op == 18'h9 | exu_op == 18'h1c) ? data3 :
                     is_load_or_store ? load_store_addr :
                     alu_res;

    assign exu_jump = (exu_op == 18'h9 | exu_op == 18'h1c) | branch_taken;
    assign exu_jump_pc = (exu_op == 18'h9) ? jalr_target :
                         (exu_op == 18'h1c) ? jal_target :
                         (branch_taken) ? branch_target : `KLDJ_ZERO32;

endmodule