module alu_mul(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [1:0]  op,
    input  wire        en,
    output wire [31:0] out
);

    // Deprecated compatibility stub. RV32M MUL* is implemented by
    // mul_ip_wrapper in KLDJ_exu so synthesis does not infer a wide
    // single-cycle combinational multiplier from this module.
    assign out = 32'b0;

endmodule