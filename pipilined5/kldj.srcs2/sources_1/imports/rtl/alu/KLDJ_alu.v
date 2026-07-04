`include "../define.v"

module KLDJ_alu(
     input  wire [`KLDJ_DATA] op1
    ,input  wire [`KLDJ_DATA] op2
    ,input  wire [9:0]        alu_op
    ,output wire [`KLDJ_DATA] alu_res
    ,output wire [3:0]        cmp_res
);

    // shangcidedaima
    wire [`KLDJ_DATA] adder_alu_res ;
    wire              is_lt         ;
    wire              is_equ;
    wire              is_ge;
    wire              is_ne;

    alu_add u_alu_add(
         .a                 (op1            )//<<i<<
        ,.b                 (op2            )//<<i<<
        ,.is_sub            (alu_op[5]      )//<<i<<
        ,.is_unsigned       (alu_op[4]      )//<<i<<
        ,.out               (adder_alu_res  )//>>o>>
        ,.lt                (is_lt          )//>>o>>
        ,.equ               (is_equ         )//>>o>>
        ,.ne                (is_ne          )//>>o>>
        ,.ge                (is_ge          )//>>o>>
    );

    wire [`KLDJ_DATA] and_alu_res   ;
    alu_and u_alu_and(
         .a                 (op1            )//<<i<<
        ,.b                 (op2            )//<<i<<
        ,.out               (and_alu_res    )//>>o>>
    );

    wire [`KLDJ_DATA] or_alu_res   ;
    alu_or u_alu_or(
         .a                 (op1            )//<<i<<
        ,.b                 (op2            )//<<i<<
        ,.out               (or_alu_res     )//>>o>>
    );

    wire [`KLDJ_DATA] shifter_alu_res   ;
    alu_shifter u_alu_shifter(
         .data              (op1            )//<<i<<
        ,.shamt             (op2[4:0]       )//<<i<<
        ,.op                (alu_op[1:0]    )//<<i<<
        ,.out               (shifter_alu_res)//>>o>>
    );

    wire [`KLDJ_DATA] slt_alu_res   ;
    alu_slt u_alu_slt(
         .lt                 (is_lt          )//<<i<<
        ,.out                (slt_alu_res    )//>>o>>
    );

    wire [`KLDJ_DATA] xor_alu_res   ;
    alu_xor u_alu_xor(
         .a                 (op1             )//<<i<<
        ,.b                 (op2             )//<<i<<
        ,.out               (xor_alu_res      )//>>o>>
    );


    //choose which alu_res
    reg [31:0] alu_res_r;
    always @(*) begin
        case (1'b1)
            alu_op[2]: alu_res_r = shifter_alu_res;
            alu_op[3]: alu_res_r = adder_alu_res;
            alu_op[6]: alu_res_r = and_alu_res;
            alu_op[7]: alu_res_r = or_alu_res;
            alu_op[8]: alu_res_r = xor_alu_res;
            alu_op[9]: alu_res_r = slt_alu_res;
            default:   alu_res_r = 32'b0;
        endcase
    end

    assign alu_res = alu_res_r;

    // TODO cmp_res
    assign cmp_res = {is_ge, is_ne, is_equ, is_lt};
endmodule
