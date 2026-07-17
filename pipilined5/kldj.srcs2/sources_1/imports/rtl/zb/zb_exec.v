`include "zb_cfg.vh"

// Execute the selected Zb micro-op in EX.  All non-Zbc operations are local
// combinational logic.  Zbc is delegated to the iterative unit below so its
// carry-less multiplier does not degrade the base ALU's timing cone.
module KLDJ_zb_exec #(
    parameter [2:0] GROUP   = `KLDJ_ZB_GROUP_NONE,
    parameter [7:0] ONLY_OP = `KLDJ_ZB_OP_ALL
)(
     input  wire        clk
    ,input  wire        rst
    ,input  wire        start
    ,input  wire [7:0]  uop
    ,input  wire [31:0] rs1
    ,input  wire [31:0] rs2
    ,output wire [31:0] result
    ,output wire        busy
    ,output wire        done
);

    function op_allowed;
        input [7:0] candidate;
        begin
            op_allowed = (ONLY_OP == `KLDJ_ZB_OP_ALL) ||
                         (ONLY_OP == candidate);
        end
    endfunction

    function [31:0] f_clz;
        input [31:0] x;
        integer i;
        begin
            f_clz = 32'd32;
            for (i = 31; i >= 0; i = i - 1)
                if (x[i] && (f_clz == 32'd32))
                    f_clz = 31 - i;
        end
    endfunction

    function [31:0] f_ctz;
        input [31:0] x;
        integer i;
        begin
            f_ctz = 32'd32;
            for (i = 0; i < 32; i = i + 1)
                if (x[i] && (f_ctz == 32'd32))
                    f_ctz = i;
        end
    endfunction

    function [31:0] f_cpop;
        input [31:0] x;
        integer i;
        begin
            f_cpop = 32'd0;
            for (i = 0; i < 32; i = i + 1)
                f_cpop = f_cpop + x[i];
        end
    endfunction

    function [31:0] f_rol;
        input [31:0] x;
        input [4:0] shamt;
        reg [5:0] rshamt;
        begin
            rshamt = 6'd32 - {1'b0, shamt};
            f_rol = (x << shamt) | (x >> rshamt);
        end
    endfunction

    function [31:0] f_ror;
        input [31:0] x;
        input [4:0] shamt;
        reg [5:0] lshamt;
        begin
            lshamt = 6'd32 - {1'b0, shamt};
            f_ror = (x >> shamt) | (x << lshamt);
        end
    endfunction

    function [31:0] f_orc_b;
        input [31:0] x;
        begin
            f_orc_b = {(|x[31:24]) ? 8'hff : 8'h00,
                       (|x[23:16]) ? 8'hff : 8'h00,
                       (|x[15: 8]) ? 8'hff : 8'h00,
                       (|x[ 7: 0]) ? 8'hff : 8'h00};
        end
    endfunction

    function [7:0] f_bitreverse8;
        input [7:0] x;
        begin
            f_bitreverse8 = {x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7]};
        end
    endfunction

    function [31:0] f_brev8;
        input [31:0] x;
        begin
            f_brev8 = {f_bitreverse8(x[31:24]), f_bitreverse8(x[23:16]),
                       f_bitreverse8(x[15:8]),  f_bitreverse8(x[7:0])};
        end
    endfunction

    function [31:0] f_zip;
        input [31:0] x;
        reg [31:0] y;
        integer i;
        begin
            y = 32'd0;
            for (i = 0; i < 16; i = i + 1) begin
                y[2*i]     = x[i];
                y[2*i + 1] = x[i + 16];
            end
            f_zip = y;
        end
    endfunction

    function [31:0] f_unzip;
        input [31:0] x;
        reg [31:0] y;
        integer i;
        begin
            y = 32'd0;
            for (i = 0; i < 16; i = i + 1) begin
                y[i]      = x[2*i];
                y[i + 16] = x[2*i + 1];
            end
            f_unzip = y;
        end
    endfunction

    function [31:0] f_xperm4;
        input [31:0] x;
        input [31:0] selectors;
        reg [31:0] y;
        reg [3:0] selector;
        integer i;
        integer source_index;
        begin
            y = 32'd0;
            for (i = 0; i < 8; i = i + 1) begin
                selector = selectors[4*i +: 4];
                source_index = selector;
                if (selector < 4'd8)
                    y[4*i +: 4] = x[source_index * 4 +: 4];
            end
            f_xperm4 = y;
        end
    endfunction

    function [31:0] f_xperm8;
        input [31:0] x;
        input [31:0] selectors;
        reg [31:0] y;
        reg [7:0] selector;
        integer i;
        integer source_index;
        begin
            y = 32'd0;
            for (i = 0; i < 4; i = i + 1) begin
                selector = selectors[8*i +: 8];
                source_index = selector;
                if (selector < 8'd4)
                    y[8*i +: 8] = x[source_index * 8 +: 8];
            end
            f_xperm8 = y;
        end
    endfunction

    reg [31:0] comb_result_r;
    wire [31:0] comb_result = comb_result_r;

    always @(*) begin
        comb_result_r = 32'd0;

        case (GROUP)
            `KLDJ_ZB_GROUP_ZBA: begin
                case (uop)
                    `KLDJ_ZB_OP_SH1ADD:
                        if (op_allowed(`KLDJ_ZB_OP_SH1ADD)) comb_result_r = rs2 + (rs1 << 1);
                    `KLDJ_ZB_OP_SH2ADD:
                        if (op_allowed(`KLDJ_ZB_OP_SH2ADD)) comb_result_r = rs2 + (rs1 << 2);
                    `KLDJ_ZB_OP_SH3ADD:
                        if (op_allowed(`KLDJ_ZB_OP_SH3ADD)) comb_result_r = rs2 + (rs1 << 3);
                    default: ;
                endcase
            end

            `KLDJ_ZB_GROUP_ZBB: begin
                case (uop)
                    `KLDJ_ZB_OP_ANDN:   if (op_allowed(`KLDJ_ZB_OP_ANDN))   comb_result_r = rs1 & ~rs2;
                    `KLDJ_ZB_OP_ORN:    if (op_allowed(`KLDJ_ZB_OP_ORN))    comb_result_r = rs1 | ~rs2;
                    `KLDJ_ZB_OP_XNOR:   if (op_allowed(`KLDJ_ZB_OP_XNOR))   comb_result_r = ~(rs1 ^ rs2);
                    `KLDJ_ZB_OP_CLZ:    if (op_allowed(`KLDJ_ZB_OP_CLZ))    comb_result_r = f_clz(rs1);
                    `KLDJ_ZB_OP_CTZ:    if (op_allowed(`KLDJ_ZB_OP_CTZ))    comb_result_r = f_ctz(rs1);
                    `KLDJ_ZB_OP_CPOP:   if (op_allowed(`KLDJ_ZB_OP_CPOP))   comb_result_r = f_cpop(rs1);
                    `KLDJ_ZB_OP_MAX:    if (op_allowed(`KLDJ_ZB_OP_MAX))    comb_result_r = ($signed(rs1) > $signed(rs2)) ? rs1 : rs2;
                    `KLDJ_ZB_OP_MAXU:   if (op_allowed(`KLDJ_ZB_OP_MAXU))   comb_result_r = (rs1 > rs2) ? rs1 : rs2;
                    `KLDJ_ZB_OP_MIN:    if (op_allowed(`KLDJ_ZB_OP_MIN))    comb_result_r = ($signed(rs1) < $signed(rs2)) ? rs1 : rs2;
                    `KLDJ_ZB_OP_MINU:   if (op_allowed(`KLDJ_ZB_OP_MINU))   comb_result_r = (rs1 < rs2) ? rs1 : rs2;
                    `KLDJ_ZB_OP_SEXT_B: if (op_allowed(`KLDJ_ZB_OP_SEXT_B)) comb_result_r = {{24{rs1[7]}}, rs1[7:0]};
                    `KLDJ_ZB_OP_SEXT_H: if (op_allowed(`KLDJ_ZB_OP_SEXT_H)) comb_result_r = {{16{rs1[15]}}, rs1[15:0]};
                    `KLDJ_ZB_OP_ZEXT_H: if (op_allowed(`KLDJ_ZB_OP_ZEXT_H)) comb_result_r = {16'd0, rs1[15:0]};
                    `KLDJ_ZB_OP_ROL:    if (op_allowed(`KLDJ_ZB_OP_ROL))    comb_result_r = f_rol(rs1, rs2[4:0]);
                    `KLDJ_ZB_OP_ROR:    if (op_allowed(`KLDJ_ZB_OP_ROR))    comb_result_r = f_ror(rs1, rs2[4:0]);
                    `KLDJ_ZB_OP_RORI:   if (op_allowed(`KLDJ_ZB_OP_RORI))   comb_result_r = f_ror(rs1, rs2[4:0]);
                    `KLDJ_ZB_OP_ORC_B:  if (op_allowed(`KLDJ_ZB_OP_ORC_B))  comb_result_r = f_orc_b(rs1);
                    `KLDJ_ZB_OP_REV8:   if (op_allowed(`KLDJ_ZB_OP_REV8))   comb_result_r = {rs1[7:0], rs1[15:8], rs1[23:16], rs1[31:24]};
                    default: ;
                endcase
            end

            `KLDJ_ZB_GROUP_ZBS: begin
                case (uop)
                    `KLDJ_ZB_OP_BSET:  if (op_allowed(`KLDJ_ZB_OP_BSET))  comb_result_r = rs1 |  (32'h1 << rs2[4:0]);
                    `KLDJ_ZB_OP_BCLR:  if (op_allowed(`KLDJ_ZB_OP_BCLR))  comb_result_r = rs1 & ~(32'h1 << rs2[4:0]);
                    `KLDJ_ZB_OP_BINV:  if (op_allowed(`KLDJ_ZB_OP_BINV))  comb_result_r = rs1 ^  (32'h1 << rs2[4:0]);
                    `KLDJ_ZB_OP_BEXT:  if (op_allowed(`KLDJ_ZB_OP_BEXT))  comb_result_r = {31'd0, rs1[rs2[4:0]]};
                    `KLDJ_ZB_OP_BSETI: if (op_allowed(`KLDJ_ZB_OP_BSETI)) comb_result_r = rs1 |  (32'h1 << rs2[4:0]);
                    `KLDJ_ZB_OP_BCLRI: if (op_allowed(`KLDJ_ZB_OP_BCLRI)) comb_result_r = rs1 & ~(32'h1 << rs2[4:0]);
                    `KLDJ_ZB_OP_BINVI: if (op_allowed(`KLDJ_ZB_OP_BINVI)) comb_result_r = rs1 ^  (32'h1 << rs2[4:0]);
                    `KLDJ_ZB_OP_BEXTI: if (op_allowed(`KLDJ_ZB_OP_BEXTI)) comb_result_r = {31'd0, rs1[rs2[4:0]]};
                    default: ;
                endcase
            end

            `KLDJ_ZB_GROUP_ZBKB: begin
                case (uop)
                    `KLDJ_ZB_OP_ANDN:  if (op_allowed(`KLDJ_ZB_OP_ANDN))  comb_result_r = rs1 & ~rs2;
                    `KLDJ_ZB_OP_ORN:   if (op_allowed(`KLDJ_ZB_OP_ORN))   comb_result_r = rs1 | ~rs2;
                    `KLDJ_ZB_OP_XNOR:  if (op_allowed(`KLDJ_ZB_OP_XNOR))  comb_result_r = ~(rs1 ^ rs2);
                    `KLDJ_ZB_OP_ROL:   if (op_allowed(`KLDJ_ZB_OP_ROL))   comb_result_r = f_rol(rs1, rs2[4:0]);
                    `KLDJ_ZB_OP_ROR:   if (op_allowed(`KLDJ_ZB_OP_ROR))   comb_result_r = f_ror(rs1, rs2[4:0]);
                    `KLDJ_ZB_OP_RORI:  if (op_allowed(`KLDJ_ZB_OP_RORI))  comb_result_r = f_ror(rs1, rs2[4:0]);
                    `KLDJ_ZB_OP_REV8:  if (op_allowed(`KLDJ_ZB_OP_REV8))  comb_result_r = {rs1[7:0], rs1[15:8], rs1[23:16], rs1[31:24]};
                    `KLDJ_ZB_OP_BREV8: if (op_allowed(`KLDJ_ZB_OP_BREV8)) comb_result_r = f_brev8(rs1);
                    `KLDJ_ZB_OP_PACK:  if (op_allowed(`KLDJ_ZB_OP_PACK))  comb_result_r = {rs2[15:0], rs1[15:0]};
                    `KLDJ_ZB_OP_PACKH: if (op_allowed(`KLDJ_ZB_OP_PACKH)) comb_result_r = {16'd0, rs2[7:0], rs1[7:0]};
                    `KLDJ_ZB_OP_ZIP:   if (op_allowed(`KLDJ_ZB_OP_ZIP))   comb_result_r = f_zip(rs1);
                    `KLDJ_ZB_OP_UNZIP: if (op_allowed(`KLDJ_ZB_OP_UNZIP)) comb_result_r = f_unzip(rs1);
                    default: ;
                endcase
            end

            `KLDJ_ZB_GROUP_ZBKX: begin
                case (uop)
                    `KLDJ_ZB_OP_XPERM4: if (op_allowed(`KLDJ_ZB_OP_XPERM4)) comb_result_r = f_xperm4(rs1, rs2);
                    `KLDJ_ZB_OP_XPERM8: if (op_allowed(`KLDJ_ZB_OP_XPERM8)) comb_result_r = f_xperm8(rs1, rs2);
                    default: ;
                endcase
            end

            default: ;
        endcase
    end

    generate
        if (GROUP == `KLDJ_ZB_GROUP_ZBC) begin : g_zbc
            wire [31:0] clmul_result;
            wire        clmul_busy;
            wire        clmul_done;

            KLDJ_zb_clmul_iter u_KLDJ_zb_clmul_iter(
                 .clk   (clk)
                ,.rst   (rst)
                ,.start (start)
                ,.uop   (uop)
                ,.rs1   (rs1)
                ,.rs2   (rs2)
                ,.busy  (clmul_busy)
                ,.done  (clmul_done)
                ,.result(clmul_result)
            );

            assign result = clmul_result;
            assign busy   = clmul_busy;
            assign done   = clmul_done;
        end else begin : g_comb
            assign result = comb_result;
            assign busy   = 1'b0;
            assign done   = 1'b1;
        end
    endgenerate

endmodule
