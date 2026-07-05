module div_ip_wrapper(
     input  wire        clk
    ,input  wire        rst
    ,input  wire        start
    ,input  wire [1:0]  op
    ,input  wire [31:0] rs1
    ,input  wire [31:0] rs2
    ,output wire        busy
    ,output wire        done
    ,output wire [31:0] result
);

    localparam [1:0] OP_DIV  = 2'b00;
    localparam [1:0] OP_DIVU = 2'b01;
    localparam [1:0] OP_REM  = 2'b10;
    localparam [1:0] OP_REMU = 2'b11;

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_LAUNCH      = 3'd1;
    localparam [2:0] ST_WAIT_RESULT = 3'd2;
    localparam [2:0] ST_DONE        = 3'd3;

    reg [2:0]  state;
    reg [1:0]  op_q;
    reg [31:0] dividend_abs_q;
    reg [31:0] divisor_abs_q;
    reg        quotient_neg_q;      
    reg        remainder_neg_q;         
    reg        dividend_sent_q;
    reg        divisor_sent_q;
    reg [31:0] result_q;

    wire signed_op       = (op == OP_DIV) || (op == OP_REM);
    wire div_by_zero     = (rs2 == 32'b0);
    wire signed_overflow = ((op == OP_DIV) || (op == OP_REM)) &&
                           (rs1 == 32'h8000_0000) && (rs2 == 32'hffff_ffff);

    wire [31:0] rs1_abs = (signed_op && rs1[31]) ? (~rs1 + 32'd1) : rs1;
    wire [31:0] rs2_abs = (signed_op && rs2[31]) ? (~rs2 + 32'd1) : rs2;

    wire [31:0] div_by_zero_result =
        ((op == OP_DIV) || (op == OP_DIVU)) ? 32'hffff_ffff : rs1;
    wire [31:0] overflow_result = (op == OP_DIV) ? 32'h8000_0000 : 32'h0000_0000;

    reg  [1:0]  ip_rst_sync;
    wire        ip_rst = ip_rst_sync[1];
    wire        s_axis_dividend_tvalid;
    wire [31:0] s_axis_dividend_tdata;
    wire        s_axis_divisor_tvalid;
    wire [31:0] s_axis_divisor_tdata;
    wire        m_axis_dout_tvalid;
    wire [63:0] m_axis_dout_tdata;


    always @(posedge clk) begin
        if (rst) begin
            ip_rst_sync <= 2'b11;
        end else begin
            ip_rst_sync <= {ip_rst_sync[0], 1'b0};
        end
    end
    assign s_axis_dividend_tvalid = (state == ST_LAUNCH) && !dividend_sent_q;
    assign s_axis_divisor_tvalid  = (state == ST_LAUNCH) && !divisor_sent_q;
    assign s_axis_dividend_tdata  = dividend_abs_q;
    assign s_axis_divisor_tdata   = divisor_abs_q;
    wire dividend_fire = s_axis_dividend_tvalid;
    wire divisor_fire  = s_axis_divisor_tvalid;
    wire launch_done   = (dividend_sent_q || dividend_fire) &&
                         (divisor_sent_q  || divisor_fire);

    // Radix-2 / NonBlocking div_gen_u32 has no TREADY ports in this configuration.
    // Vivado Divider Generator standard AXI remainder mode packs quotient in
    // the low 32 bits and remainder in the high 32 bits. Confirm this against
    // div_gen_u32.veo after generating the IP; if the template differs, swap
    // these two slices only.
    wire [31:0] quotient_abs  = m_axis_dout_tdata[31:0];
    wire [31:0] remainder_abs = m_axis_dout_tdata[63:32];
    wire [31:0] quotient_res  = quotient_neg_q  ? (~quotient_abs  + 32'd1) : quotient_abs;
    wire [31:0] remainder_res = remainder_neg_q ? (~remainder_abs + 32'd1) : remainder_abs;
    wire [31:0] ip_result     = ((op_q == OP_DIV) || (op_q == OP_DIVU)) ? quotient_res : remainder_res;

    assign busy   = (state == ST_LAUNCH) || (state == ST_WAIT_RESULT);
    assign done   = (state == ST_DONE);
    assign result = result_q;

    always @(posedge clk) begin
        if (rst) begin
            state           <= ST_IDLE;
            op_q            <= OP_DIV;
            dividend_abs_q  <= 32'b0;
            divisor_abs_q   <= 32'b0;
            quotient_neg_q  <= 1'b0;
            remainder_neg_q <= 1'b0;
            dividend_sent_q <= 1'b0;
            divisor_sent_q  <= 1'b0;
            result_q        <= 32'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    dividend_sent_q <= 1'b0;
                    divisor_sent_q  <= 1'b0;
                    if (start && !ip_rst) begin
                        op_q            <= op;
                        dividend_abs_q  <= rs1_abs;
                        divisor_abs_q   <= rs2_abs;
                        quotient_neg_q  <= ((op == OP_DIV) && (rs1[31] ^ rs2[31]));
                        remainder_neg_q <= ((op == OP_REM) && rs1[31]);
                        if (div_by_zero) begin
                            result_q <= div_by_zero_result;
                            state    <= ST_DONE;
                        end else if (signed_overflow) begin
                            result_q <= overflow_result;
                            state    <= ST_DONE;
                        end else begin
                            state <= ST_LAUNCH;
                        end
                    end
                end

                ST_LAUNCH: begin
                    if (dividend_fire) begin
                        dividend_sent_q <= 1'b1;
                    end
                    if (divisor_fire) begin
                        divisor_sent_q <= 1'b1;
                    end
                    if (launch_done) begin
                        state <= ST_WAIT_RESULT;
                    end
                end

                ST_WAIT_RESULT: begin
                    if (m_axis_dout_tvalid) begin
                        result_q <= ip_result;
                        state    <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    reg [3:0]  sim_count_q;
    reg        sim_valid_q;
    reg [63:0] sim_data_q;

    assign m_axis_dout_tvalid     = sim_valid_q;
    assign m_axis_dout_tdata      = sim_data_q;

    always @(posedge clk) begin
        if (rst) begin
            sim_count_q <= 4'd0;
            sim_valid_q <= 1'b0;
            sim_data_q  <= 64'b0;
        end else begin
            if (sim_valid_q) begin
                sim_valid_q <= 1'b0;
            end

            if (launch_done && (state == ST_LAUNCH)) begin
                sim_count_q <= 4'd8;
                sim_valid_q <= 1'b0;
                sim_data_q  <= {dividend_abs_q % divisor_abs_q,
                                dividend_abs_q / divisor_abs_q};
            end else if (sim_count_q != 4'd0) begin
                sim_count_q <= sim_count_q - 4'd1;
                if (sim_count_q == 4'd1) begin
                    sim_valid_q <= 1'b1;
                end
            end
        end
    end
`else
    div_gen_u32 u_div_gen_u32 (
         .aclk                   (clk)
        ,.aresetn                (~ip_rst)
        ,.s_axis_dividend_tvalid (s_axis_dividend_tvalid)
        ,.s_axis_dividend_tdata  (s_axis_dividend_tdata)
        ,.s_axis_divisor_tvalid  (s_axis_divisor_tvalid)
        ,.s_axis_divisor_tdata   (s_axis_divisor_tdata)
        ,.m_axis_dout_tvalid     (m_axis_dout_tvalid)
        ,.m_axis_dout_tdata      (m_axis_dout_tdata)
    );
`endif

endmodule
