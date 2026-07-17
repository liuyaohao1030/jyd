`include "zb_cfg.vh"

// Decode exactly one compile-time-selected RV32 Zb group.  The decoder is
// deliberately independent from the base IDU case tree: when no KLDJ_CFG_*
// define is present, this module is not instantiated at all.
module KLDJ_zb_decode #(
    parameter [2:0] GROUP   = `KLDJ_ZB_GROUP_NONE,
    parameter [7:0] ONLY_OP = `KLDJ_ZB_OP_ALL
)(
     input  wire [31:0] inst
    ,output reg         hit
    ,output reg [7:0]   uop
    ,output reg [1:0]   op2_sel
);

    localparam [6:0] OP_RTYPE = 7'b0110011;
    localparam [6:0] OP_ITYPE = 7'b0010011;

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];
    wire [4:0] rs2    = inst[24:20];

    wire rtype = (opcode == OP_RTYPE);
    wire itype = (opcode == OP_ITYPE);

    function op_allowed;
        input [7:0] candidate;
        begin
            op_allowed = (ONLY_OP == `KLDJ_ZB_OP_ALL) ||
                         (ONLY_OP == candidate);
        end
    endfunction

    function op_belongs_to_group;
        input [2:0] group_id;
        input [7:0] candidate;
        begin
            case (group_id)
                `KLDJ_ZB_GROUP_ZBA:
                    op_belongs_to_group = (candidate >= `KLDJ_ZB_OP_SH1ADD) &&
                                          (candidate <= `KLDJ_ZB_OP_SH3ADD);
                `KLDJ_ZB_GROUP_ZBB:
                    op_belongs_to_group = (candidate >= `KLDJ_ZB_OP_ANDN) &&
                                          (candidate <= `KLDJ_ZB_OP_REV8);
                `KLDJ_ZB_GROUP_ZBC:
                    op_belongs_to_group = (candidate >= `KLDJ_ZB_OP_CLMUL) &&
                                          (candidate <= `KLDJ_ZB_OP_CLMULR);
                `KLDJ_ZB_GROUP_ZBS:
                    op_belongs_to_group = (candidate >= `KLDJ_ZB_OP_BSET) &&
                                          (candidate <= `KLDJ_ZB_OP_BEXTI);
                `KLDJ_ZB_GROUP_ZBKB:
                    op_belongs_to_group = (candidate == `KLDJ_ZB_OP_ANDN)  ||
                                          (candidate == `KLDJ_ZB_OP_ORN)   ||
                                          (candidate == `KLDJ_ZB_OP_XNOR)  ||
                                          (candidate == `KLDJ_ZB_OP_ROL)   ||
                                          (candidate == `KLDJ_ZB_OP_ROR)   ||
                                          (candidate == `KLDJ_ZB_OP_RORI)  ||
                                          (candidate == `KLDJ_ZB_OP_REV8)  ||
                                          (candidate >= `KLDJ_ZB_OP_BREV8 &&
                                           candidate <= `KLDJ_ZB_OP_UNZIP);
                `KLDJ_ZB_GROUP_ZBKX:
                    op_belongs_to_group = (candidate >= `KLDJ_ZB_OP_XPERM4) &&
                                          (candidate <= `KLDJ_ZB_OP_XPERM8);
                default: op_belongs_to_group = 1'b0;
            endcase
        end
    endfunction

`ifndef SYNTHESIS
    initial begin
        if (`KLDJ_ZB_CONFIG_COUNT != 1) begin
            $fatal(1, "Zb configuration must select exactly one KLDJ_CFG_* group");
        end
        if (GROUP == `KLDJ_ZB_GROUP_NONE) begin
            $fatal(1, "Zb extension was enabled but no valid group was selected");
        end
        if ((ONLY_OP != `KLDJ_ZB_OP_ALL) && !op_belongs_to_group(GROUP, ONLY_OP)) begin
            $fatal(1, "KLDJ_CFG_OP does not belong to the selected Zb group");
        end
    end
`endif

    always @(*) begin
        hit     = 1'b0;
        uop     = 8'd0;
        op2_sel = `KLDJ_ZB_OP2_ZERO;

        case (GROUP)
            // Zba: RV32 has sh1add/sh2add/sh3add only.  The .uw forms are
            // RV64-only and intentionally absent.
            `KLDJ_ZB_GROUP_ZBA: begin
                if (rtype && (funct7 == 7'b0010000) && (funct3 == 3'b010) &&
                    op_allowed(`KLDJ_ZB_OP_SH1ADD)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_SH1ADD;
                    op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0010000) && (funct3 == 3'b100) &&
                             op_allowed(`KLDJ_ZB_OP_SH2ADD)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_SH2ADD;
                    op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0010000) && (funct3 == 3'b110) &&
                             op_allowed(`KLDJ_ZB_OP_SH3ADD)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_SH3ADD;
                    op2_sel = `KLDJ_ZB_OP2_RS2;
                end
            end

            `KLDJ_ZB_GROUP_ZBB: begin
                if (rtype && (funct7 == 7'b0100000) && (funct3 == 3'b111) &&
                    op_allowed(`KLDJ_ZB_OP_ANDN)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ANDN; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0100000) && (funct3 == 3'b110) &&
                             op_allowed(`KLDJ_ZB_OP_ORN)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ORN; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0100000) && (funct3 == 3'b100) &&
                             op_allowed(`KLDJ_ZB_OP_XNOR)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_XNOR; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (itype && (funct3 == 3'b001) && (inst[31:20] == 12'h600) &&
                             op_allowed(`KLDJ_ZB_OP_CLZ)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_CLZ;
                end else if (itype && (funct3 == 3'b001) && (inst[31:20] == 12'h601) &&
                             op_allowed(`KLDJ_ZB_OP_CTZ)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_CTZ;
                end else if (itype && (funct3 == 3'b001) && (inst[31:20] == 12'h602) &&
                             op_allowed(`KLDJ_ZB_OP_CPOP)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_CPOP;
                end else if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b110) &&
                             op_allowed(`KLDJ_ZB_OP_MAX)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_MAX; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b111) &&
                             op_allowed(`KLDJ_ZB_OP_MAXU)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_MAXU; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b100) &&
                             op_allowed(`KLDJ_ZB_OP_MIN)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_MIN; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_MINU)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_MINU; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (itype && (funct3 == 3'b001) && (inst[31:20] == 12'h604) &&
                             op_allowed(`KLDJ_ZB_OP_SEXT_B)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_SEXT_B;
                end else if (itype && (funct3 == 3'b001) && (inst[31:20] == 12'h605) &&
                             op_allowed(`KLDJ_ZB_OP_SEXT_H)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_SEXT_H;
                end else if (rtype && (funct7 == 7'b0000100) && (funct3 == 3'b100) &&
                             (rs2 == 5'd0) && op_allowed(`KLDJ_ZB_OP_ZEXT_H)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ZEXT_H;
                end else if (rtype && (funct7 == 7'b0110000) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_ROL)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ROL; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0110000) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_ROR)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ROR; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (itype && (funct7 == 7'b0110000) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_RORI)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_RORI; op2_sel = `KLDJ_ZB_OP2_IMM5;
                end else if (itype && (funct3 == 3'b101) && (inst[31:20] == 12'h287) &&
                             op_allowed(`KLDJ_ZB_OP_ORC_B)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ORC_B;
                end else if (itype && (funct3 == 3'b101) && (inst[31:20] == 12'h698) &&
                             op_allowed(`KLDJ_ZB_OP_REV8)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_REV8;
                end
            end

            `KLDJ_ZB_GROUP_ZBC: begin
                if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b001) &&
                    op_allowed(`KLDJ_ZB_OP_CLMUL)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_CLMUL; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b011) &&
                             op_allowed(`KLDJ_ZB_OP_CLMULH)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_CLMULH; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0000101) && (funct3 == 3'b010) &&
                             op_allowed(`KLDJ_ZB_OP_CLMULR)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_CLMULR; op2_sel = `KLDJ_ZB_OP2_RS2;
                end
            end

            `KLDJ_ZB_GROUP_ZBS: begin
                if (rtype && (funct7 == 7'b0010100) && (funct3 == 3'b001) &&
                    op_allowed(`KLDJ_ZB_OP_BSET)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BSET; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0100100) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_BCLR)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BCLR; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0110100) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_BINV)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BINV; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0100100) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_BEXT)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BEXT; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (itype && (funct7 == 7'b0010100) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_BSETI)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BSETI; op2_sel = `KLDJ_ZB_OP2_IMM5;
                end else if (itype && (funct7 == 7'b0100100) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_BCLRI)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BCLRI; op2_sel = `KLDJ_ZB_OP2_IMM5;
                end else if (itype && (funct7 == 7'b0110100) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_BINVI)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BINVI; op2_sel = `KLDJ_ZB_OP2_IMM5;
                end else if (itype && (funct7 == 7'b0100100) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_BEXTI)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BEXTI; op2_sel = `KLDJ_ZB_OP2_IMM5;
                end
            end

            // Zbkb overlaps Zbb for several operations.  Keeping these
            // encodings in the Zbkb selector matters for a -march=..._zbkb
            // test binary even if the same arithmetic is also useful in Zbb.
            `KLDJ_ZB_GROUP_ZBKB: begin
                if (rtype && (funct7 == 7'b0100000) && (funct3 == 3'b111) &&
                    op_allowed(`KLDJ_ZB_OP_ANDN)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ANDN; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0100000) && (funct3 == 3'b110) &&
                             op_allowed(`KLDJ_ZB_OP_ORN)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ORN; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0100000) && (funct3 == 3'b100) &&
                             op_allowed(`KLDJ_ZB_OP_XNOR)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_XNOR; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0110000) && (funct3 == 3'b001) &&
                             op_allowed(`KLDJ_ZB_OP_ROL)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ROL; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0110000) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_ROR)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ROR; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (itype && (funct7 == 7'b0110000) && (funct3 == 3'b101) &&
                             op_allowed(`KLDJ_ZB_OP_RORI)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_RORI; op2_sel = `KLDJ_ZB_OP2_IMM5;
                end else if (itype && (funct3 == 3'b101) && (inst[31:20] == 12'h698) &&
                             op_allowed(`KLDJ_ZB_OP_REV8)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_REV8;
                end else if (itype && (funct3 == 3'b101) && (inst[31:20] == 12'h687) &&
                             op_allowed(`KLDJ_ZB_OP_BREV8)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_BREV8;
                end else if (rtype && (funct7 == 7'b0000100) && (funct3 == 3'b100) &&
                             op_allowed(`KLDJ_ZB_OP_PACK)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_PACK; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0000100) && (funct3 == 3'b111) &&
                             op_allowed(`KLDJ_ZB_OP_PACKH)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_PACKH; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (itype && (funct3 == 3'b001) && (inst[31:20] == 12'h08f) &&
                             op_allowed(`KLDJ_ZB_OP_ZIP)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_ZIP;
                end else if (itype && (funct3 == 3'b101) && (inst[31:20] == 12'h08f) &&
                             op_allowed(`KLDJ_ZB_OP_UNZIP)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_UNZIP;
                end
            end

            `KLDJ_ZB_GROUP_ZBKX: begin
                if (rtype && (funct7 == 7'b0010100) && (funct3 == 3'b010) &&
                    op_allowed(`KLDJ_ZB_OP_XPERM4)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_XPERM4; op2_sel = `KLDJ_ZB_OP2_RS2;
                end else if (rtype && (funct7 == 7'b0010100) && (funct3 == 3'b100) &&
                             op_allowed(`KLDJ_ZB_OP_XPERM8)) begin
                    hit = 1'b1; uop = `KLDJ_ZB_OP_XPERM8; op2_sel = `KLDJ_ZB_OP2_RS2;
                end
            end

            default: ;
        endcase
    end

endmodule
