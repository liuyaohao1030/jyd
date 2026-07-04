module alu_div(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [1:0]  op,
    input  wire        en,
    output wire [31:0] out
);

    // Deprecated compatibility stub. RV32M DIV/REM is implemented by
    // div_ip_wrapper in KLDJ_exu so synthesis never infers a
    // single-cycle combinational divider from this module.
    assign out = 32'b0;

endmodule
