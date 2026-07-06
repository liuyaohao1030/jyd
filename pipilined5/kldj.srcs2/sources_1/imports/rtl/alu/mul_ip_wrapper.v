module mul_ip_wrapper #(
    // Must match the latency reported by the mult_gen_u33 GUI/veo.
    // Keep this automatic/high-performance IP latency rather than reducing it
    // manually until post-implementation timing is clean.
    parameter integer MUL_LATENCY = 4
)(
     input  wire        clk
    ,input  wire        rst
    ,input  wire        start
    ,input  wire [1:0]  op
    ,input  wire [31:0] rs1
    ,input  wire [31:0] rs2
    ,output wire        busy
    ,output reg         done
    ,output reg  [31:0] result
);

    localparam [1:0] OP_MUL    = 2'b00;
    localparam [1:0] OP_MULH   = 2'b01;
    localparam [1:0] OP_MULHSU = 2'b10;
    localparam [1:0] OP_MULHU  = 2'b11;

    localparam ST_IDLE = 1'b0;
    localparam ST_WAIT = 1'b1;

    reg        state;
    reg [1:0]  op_q;
    reg [31:0] rs1_q;
    reg [31:0] rs2_q;
    reg [31:0] wait_count;

    wire signed [32:0] a_ext_start = ((op == OP_MULHU) || (op == OP_MUL)) ? {1'b0, rs1} : {rs1[31], rs1};
    wire signed [32:0] b_ext_start = ((op == OP_MULH) || (op == OP_MUL))  ? {rs2[31], rs2} : {1'b0, rs2};

    wire signed [32:0] a_ext_q = ((op_q == OP_MULHU) || (op_q == OP_MUL)) ? {1'b0, rs1_q} : {rs1_q[31], rs1_q};
    wire signed [32:0] b_ext_q = ((op_q == OP_MULH) || (op_q == OP_MUL))  ? {rs2_q[31], rs2_q} : {1'b0, rs2_q};

    wire signed [32:0] mult_a = (state == ST_IDLE && start) ? a_ext_start : a_ext_q;
    wire signed [32:0] mult_b = (state == ST_IDLE && start) ? b_ext_start : b_ext_q;
    wire [65:0] product;

    assign busy = (state == ST_WAIT);

    wire [31:0] product_result = (op_q == OP_MUL) ? product[31:0] : product[63:32];
    // The 33x33 product is 66 bits, but RV32M defines MULH/MULHSU/MULHU from
    // the low 64 bits of the original 32x32 product. Therefore the high word is
    // product[63:32], not product[64:33] or product[65:34].

    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            op_q       <= OP_MUL;
            rs1_q      <= 32'b0;
            rs2_q      <= 32'b0;
            wait_count <= 32'b0;
            done       <= 1'b0;
            result     <= 32'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    wait_count <= 32'b0;
                    if (start) begin
                        op_q  <= op;
                        rs1_q <= rs1;
                        rs2_q <= rs2;
                        // P is updated by the pipelined IP on the latency
                        // clock edge, so capture it one cycle later.
                        wait_count <= MUL_LATENCY + 1;
                        state      <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (wait_count <= 32'd1) begin
                        result     <= product_result;
                        done       <= 1'b1;
                        wait_count <= 32'b0;
                        state      <= ST_IDLE;
                    end else begin
                        wait_count <= wait_count - 32'd1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    reg signed [65:0] product_sim_q;
    assign product = product_sim_q;

    always @(posedge clk) begin
        if (rst) begin
            product_sim_q <= 66'b0;
        end else if (state == ST_IDLE && start) begin
            product_sim_q <= a_ext_start * b_ext_start;
        end
    end
`else
    mult_gen_u33 u_mult_gen_u33 (
         .CLK (clk)
        ,.A   (mult_a)
        ,.B   (mult_b)
        ,.P   (product)
    );
`endif

endmodule
