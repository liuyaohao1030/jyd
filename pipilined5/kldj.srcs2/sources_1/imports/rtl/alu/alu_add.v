module alu_add(
    input  wire [31:0] a,      // 输入a
    input  wire [31:0] b,      // 输入b
    input  wire        is_sub, // 是否做减法
    input  wire        is_unsigned, // 是否为无符号数
    output wire [31:0] out,    // 输出结果
    output wire        lt,     // less than
    output wire        equ,    // equal
    output wire        ne,     // not equal
    output wire        ge      // greater or equal
);

    // Please complete the code
    wire [31:0] complement = b ^ {32{is_sub}};
    assign out = a + complement + {31'b0, is_sub};

    // 比较逻辑：直接使用 Verilog 比较符
    // 综合工具会把它们映射到专用的硬件比较器/进位链上，速度比手写逻辑快得多
    wire signed_lt   = $signed(a) < $signed(b);
    wire unsigned_lt = a < b;
    assign lt  = is_unsigned ? unsigned_lt : signed_lt;

    //我添加了这个
    assign equ = (a == b);
    assign ne  = (a != b);  
    assign ge  = ~lt; 

endmodule
