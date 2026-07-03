module alu_div(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [1:0]  op,
    input  wire        en,
    output reg  [31:0] out
);

    wire signed [31:0] a_signed;
    wire signed [31:0] b_signed;

    assign a_signed = a;
    assign b_signed = b;

    always @(*) begin
        if (!en) begin
            out = 32'b0;
        end else begin
            case (op)
                2'b00: begin
                    if (b == 32'b0) begin
                        out = 32'hffffffff;
                    end else if ((a == 32'h80000000) && (b == 32'hffffffff)) begin
                        out = 32'h80000000;
                    end else begin
                        out = a_signed / b_signed;
                    end
                end
                2'b01: begin
                    if (b == 32'b0) begin
                        out = 32'hffffffff;
                    end else begin
                        out = a / b;
                    end
                end
                2'b10: begin
                    if (b == 32'b0) begin
                        out = a;
                    end else if ((a == 32'h80000000) && (b == 32'hffffffff)) begin
                        out = 32'b0;
                    end else begin
                        out = a_signed % b_signed;
                    end
                end
                2'b11: begin
                    if (b == 32'b0) begin
                        out = a;
                    end else begin
                        out = a % b;
                    end
                end
                default: begin
                    out = 32'b0;
                end
            endcase
        end
    end

endmodule
