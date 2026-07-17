`include "zb_cfg.vh"

// Small iterative GF(2) multiplier for Zbc.  It deliberately avoids a 32x32
// combinational XOR array, so enabling Zbc does not put a large multiplier in
// the normal EX combinational cone.  The core holds ID/EX until done, just as
// it already does for RV32M MUL/DIV.
module KLDJ_zb_clmul_iter(
     input  wire        clk
    ,input  wire        rst
    ,input  wire        start
    ,input  wire [7:0]  uop
    ,input  wire [31:0] rs1
    ,input  wire [31:0] rs2
    ,output wire        busy
    ,output wire        done
    ,output wire [31:0] result
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [1:0]  state;
    reg [7:0]  uop_q;
    // Keep the shifted multiplicand at product width.  A 32-bit register
    // would silently discard terms contributing to CLMULH/CLMULR.
    reg [63:0] a_q;
    reg [31:0] b_q;
    reg [63:0] accum_q;
    reg [63:0] product_q;
    reg [5:0]  bit_count_q;

    wire [63:0] partial_product = b_q[0] ? (accum_q ^ a_q) : accum_q;

    assign busy = (state == ST_RUN);
    assign done = (state == ST_DONE);
    assign result = (uop_q == `KLDJ_ZB_OP_CLMUL)  ? product_q[31:0]  :
                    (uop_q == `KLDJ_ZB_OP_CLMULH) ? product_q[63:32] :
                    (uop_q == `KLDJ_ZB_OP_CLMULR) ? product_q[62:31] :
                                                     32'b0;

    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            uop_q       <= 8'd0;
            a_q         <= 64'd0;
            b_q         <= 32'd0;
            accum_q     <= 64'd0;
            product_q   <= 64'd0;
            bit_count_q <= 6'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        uop_q       <= uop;
                        a_q         <= {32'd0, rs1};
                        b_q         <= rs2;
                        accum_q     <= 64'd0;
                        product_q   <= 64'd0;
                        bit_count_q <= 6'd0;
                        state       <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (bit_count_q == 6'd31) begin
                        // Include the final partial product before reporting
                        // completion; nonblocking assignment would otherwise
                        // drop rs2[31]'s contribution.
                        product_q <= partial_product;
                        state     <= ST_DONE;
                    end else begin
                        accum_q     <= partial_product;
                        a_q         <= a_q << 1;
                        b_q         <= b_q >> 1;
                        bit_count_q <= bit_count_q + 6'd1;
                    end
                end

                ST_DONE: state <= ST_IDLE;

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
