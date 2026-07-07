module alu_shifter (
    input   wire    [31:0]  data,
    input   wire    [4:0]   shamt,
    input   wire    [1:0]   op,
    output  reg     [31:0]  out
);

/*
    00 逻辑左移 logical left
    01 逻辑右移 logical right
    11 算术右移 arithmetical right
*/
    always @(*) begin
        case(op)
            2'b00: out = data << shamt;
            2'b01: out = data >> shamt;
            2'b11: out = $signed(data) >>> shamt; // $signed 让综合工具知道这是算术右移
            default: out = 32'b0;
        endcase
    end

endmodule
