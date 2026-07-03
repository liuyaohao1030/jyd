module alu_mul(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [1:0]  op,
    input  wire        en,
    output reg  [31:0] out
);

    reg signed [32:0] mul_a;
    reg signed [32:0] mul_b;
    reg signed [65:0] product;

    always @(*) begin
        mul_a = 33'b0;
        mul_b = 33'b0;
        product = 66'b0;
        out = 32'b0;

        if (en) begin
            case (op)
                2'b00: begin
                    mul_a = {a[31], a};
                    mul_b = {b[31], b};
                end
                2'b01: begin
                    mul_a = {a[31], a};
                    mul_b = {b[31], b};
                end
                2'b10: begin
                    mul_a = {a[31], a};
                    mul_b = {1'b0, b};
                end
                2'b11: begin
                    mul_a = {1'b0, a};
                    mul_b = {1'b0, b};
                end
                default: begin
                    mul_a = 33'b0;
                    mul_b = 33'b0;
                end
            endcase

            product = mul_a * mul_b;

            case (op)
                2'b00: out = product[31:0];
                2'b01: out = product[63:32];
                2'b10: out = product[63:32];
                2'b11: out = product[63:32];
                default: out = 32'b0;
            endcase
        end
    end

endmodule
