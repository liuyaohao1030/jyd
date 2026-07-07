`timescale 1ns/1ps

module m_ext_ip_wrapper_tb;
    reg clk;
    reg rst;

    reg        mul_start;
    reg [1:0]  mul_op;
    reg [31:0] mul_rs1;
    reg [31:0] mul_rs2;
    wire       mul_busy;
    wire       mul_done;
    wire [31:0] mul_result;

    reg        div_start;
    reg [1:0]  div_op;
    reg [31:0] div_rs1;
    reg [31:0] div_rs2;
    wire       div_busy;
    wire       div_done;
    wire [31:0] div_result;

    integer fail_count;

    localparam [1:0] OP_MUL    = 2'b00;
    localparam [1:0] OP_MULH   = 2'b01;
    localparam [1:0] OP_MULHSU = 2'b10;
    localparam [1:0] OP_MULHU  = 2'b11;
    localparam [1:0] OP_DIV    = 2'b00;
    localparam [1:0] OP_DIVU   = 2'b01;
    localparam [1:0] OP_REM    = 2'b10;
    localparam [1:0] OP_REMU   = 2'b11;

    mul_ip_wrapper u_mul (
         .clk    (clk)
        ,.rst    (rst)
        ,.start  (mul_start)
        ,.op     (mul_op)
        ,.rs1    (mul_rs1)
        ,.rs2    (mul_rs2)
        ,.busy   (mul_busy)
        ,.done   (mul_done)
        ,.result (mul_result)
    );

    div_ip_wrapper u_div (
         .clk    (clk)
        ,.rst    (rst)
        ,.start  (div_start)
        ,.op     (div_op)
        ,.rs1    (div_rs1)
        ,.rs2    (div_rs2)
        ,.busy   (div_busy)
        ,.done   (div_done)
        ,.result (div_result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic [31:0] mul_expected;
        input [1:0] op;
        input [31:0] a;
        input [31:0] b;
        reg signed [63:0] ss_prod;
        reg signed [64:0] su_prod;
        reg [63:0] uu_prod;
        begin
            ss_prod = $signed(a) * $signed(b);
            su_prod = $signed({a[31], a}) * $signed({1'b0, b});
            uu_prod = a * b;
            case (op)
                OP_MUL:    mul_expected = uu_prod[31:0];
                OP_MULH:   mul_expected = ss_prod[63:32];
                OP_MULHSU: mul_expected = su_prod[63:32];
                OP_MULHU:  mul_expected = uu_prod[63:32];
                default:   mul_expected = 32'b0;
            endcase
        end
    endfunction

    function automatic [31:0] div_expected;
        input [1:0] op;
        input [31:0] a;
        input [31:0] b;
        reg signed [31:0] as;
        reg signed [31:0] bs;
        begin
            as = a;
            bs = b;
            case (op)
                OP_DIV: begin
                    if (b == 32'b0) div_expected = 32'hffff_ffff;
                    else if (a == 32'h8000_0000 && b == 32'hffff_ffff) div_expected = 32'h8000_0000;
                    else div_expected = as / bs;
                end
                OP_DIVU: begin
                    if (b == 32'b0) div_expected = 32'hffff_ffff;
                    else div_expected = a / b;
                end
                OP_REM: begin
                    if (b == 32'b0) div_expected = a;
                    else if (a == 32'h8000_0000 && b == 32'hffff_ffff) div_expected = 32'b0;
                    else div_expected = as % bs;
                end
                OP_REMU: begin
                    if (b == 32'b0) div_expected = a;
                    else div_expected = a % b;
                end
                default: div_expected = 32'b0;
            endcase
        end
    endfunction

    task automatic check_mul;
        input [1:0] op;
        input [31:0] a;
        input [31:0] b;
        reg [31:0] exp;
        integer timeout;
        begin
            exp = mul_expected(op, a, b);
            @(negedge clk);
            mul_op = op;
            mul_rs1 = a;
            mul_rs2 = b;
            mul_start = 1'b1;
            @(negedge clk);
            mul_start = 1'b0;
            timeout = 0;
            while (!mul_done && timeout < 32) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!mul_done || mul_result !== exp) begin
                fail_count = fail_count + 1;
                $display("[FAIL] MUL op=%0d a=0x%08h b=0x%08h exp=0x%08h got=0x%08h timeout=%0d",
                         op, a, b, exp, mul_result, timeout);
            end else begin
                $display("[PASS] MUL op=%0d a=0x%08h b=0x%08h result=0x%08h", op, a, b, mul_result);
            end
            @(posedge clk);
        end
    endtask

    task automatic check_div;
        input [1:0] op;
        input [31:0] a;
        input [31:0] b;
        reg [31:0] exp;
        integer timeout;
        begin
            exp = div_expected(op, a, b);
            @(negedge clk);
            div_op = op;
            div_rs1 = a;
            div_rs2 = b;
            div_start = 1'b1;
            @(negedge clk);
            div_start = 1'b0;
            timeout = 0;
            while (!div_done && timeout < 128) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!div_done || div_result !== exp) begin
                fail_count = fail_count + 1;
                $display("[FAIL] DIV op=%0d a=0x%08h b=0x%08h exp=0x%08h got=0x%08h timeout=%0d",
                         op, a, b, exp, div_result, timeout);
            end else begin
                $display("[PASS] DIV op=%0d a=0x%08h b=0x%08h result=0x%08h", op, a, b, div_result);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        fail_count = 0;
        mul_start = 1'b0;
        mul_op = OP_MUL;
        mul_rs1 = 32'b0;
        mul_rs2 = 32'b0;
        div_start = 1'b0;
        div_op = OP_DIV;
        div_rs1 = 32'b0;
        div_rs2 = 32'b0;
        rst = 1'b1;
        repeat (8) @(posedge clk);
        rst = 1'b0;
        repeat (8) @(posedge clk);

        check_mul(OP_MUL,    32'hffff_fffd, 32'h0000_0004);
        check_mul(OP_MULH,   32'h8000_0000, 32'h0000_0002);
        check_mul(OP_MULHSU, 32'hffff_fffe, 32'h0000_0003);
        check_mul(OP_MULHU,  32'hffff_ffff, 32'hffff_ffff);

        check_div(OP_DIV,  32'hffff_fff9, 32'h0000_0003);
        check_div(OP_REM,  32'hffff_fff9, 32'h0000_0003);
        check_div(OP_DIVU, 32'hffff_ffff, 32'h0000_0002);
        check_div(OP_REMU, 32'hffff_ffff, 32'h0000_0002);
        check_div(OP_DIV,  32'h1234_5678, 32'h0000_0000);
        check_div(OP_REM,  32'h8000_0000, 32'hffff_ffff);

        if (fail_count == 0) begin
            $display("[SUMMARY] m_ext_ip_wrapper_tb passed.");
        end else begin
            $fatal(1, "[SUMMARY] m_ext_ip_wrapper_tb failed fail_count=%0d", fail_count);
        end
        $finish;
    end
endmodule
