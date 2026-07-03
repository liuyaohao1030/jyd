module alu_slt(
    input  wire          lt,
    output wire  [31:0]  out
);

assign out = {31'b0, lt};

endmodule
