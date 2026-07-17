`timescale 1ns / 1ps

`include "define.v"
`include "zb_cfg.vh"

// Integration regression for the compile-time Zb plug-in.  It accepts either
// the legacy command-line KLDJ_CFG_* selection or the RTL-local selection in
// zb_cfg.vh.  Results are checked at the core's WB commit observation point,
// so the test covers decode, forwarding, EX execution, long-operation
// stalling, and writeback.
module KLDJ_zb_tb;

    localparam [31:0] BASE_PC = 32'h8000_0000;
    localparam [6:0] OP_RTYPE = 7'b0110011;
    localparam [6:0] OP_ITYPE = 7'b0010011;
    localparam [6:0] OP_LUI   = 7'b0110111;
    localparam integer MAX_EXPECT = 64;

    reg clk;
    reg rst;
    always #5 clk = ~clk;

    reg [31:0] inst_mem [0:511];
    wire [31:0] if_pc;
    wire [8:0]  inst_addr = if_pc[10:2];
    wire [31:0] inst_rdata = inst_mem[inst_addr];

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire [31:0] mem_rdata = 32'd0;

    KLDJ_top dut(
         .clk       (clk)
        ,.rst       (rst)
        ,.tb_if_inst(inst_rdata)
        ,.tb_if_pc  (if_pc)
        ,.mem_addr  (mem_addr)
        ,.mem_wdata (mem_wdata)
        ,.mem_we    (mem_we)
        ,.mem_be    (mem_be)
        ,.mem_rdata (mem_rdata)
    );

    reg [31:0] expect_pc    [0:MAX_EXPECT-1];
    reg [4:0]  expect_rd    [0:MAX_EXPECT-1];
    reg [31:0] expect_value [0:MAX_EXPECT-1];
    reg        expect_seen  [0:MAX_EXPECT-1];
    integer expect_count;
    integer seen_count;
    integer fail_count;
    integer zb_stall_seen;
    integer idx;
    integer i;
    integer cycles;

    function [31:0] rv_rtype(
        input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        rv_rtype = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function [31:0] rv_itype(
        input [11:0] imm, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        rv_itype = {imm, rs1, funct3, rd, opcode};
    endfunction

    function [31:0] rv_utype(
        input [19:0] imm, input [4:0] rd, input [6:0] opcode
    );
        rv_utype = {imm, rd, opcode};
    endfunction

    function [31:0] gm_clz;
        input [31:0] x;
        integer n;
        begin
            gm_clz = 32'd32;
            for (n = 31; n >= 0; n = n - 1)
                if (x[n] && (gm_clz == 32'd32)) gm_clz = 31 - n;
        end
    endfunction

    function [31:0] gm_ctz;
        input [31:0] x;
        integer n;
        begin
            gm_ctz = 32'd32;
            for (n = 0; n < 32; n = n + 1)
                if (x[n] && (gm_ctz == 32'd32)) gm_ctz = n;
        end
    endfunction

    function [31:0] gm_cpop;
        input [31:0] x;
        integer n;
        begin
            gm_cpop = 32'd0;
            for (n = 0; n < 32; n = n + 1) gm_cpop = gm_cpop + x[n];
        end
    endfunction

    function [31:0] gm_rol;
        input [31:0] x;
        input [4:0] shamt;
        begin
            gm_rol = (x << shamt) | (x >> (6'd32 - {1'b0, shamt}));
        end
    endfunction

    function [31:0] gm_ror;
        input [31:0] x;
        input [4:0] shamt;
        begin
            gm_ror = (x >> shamt) | (x << (6'd32 - {1'b0, shamt}));
        end
    endfunction

    function [31:0] gm_orc_b;
        input [31:0] x;
        begin
            gm_orc_b = {(|x[31:24]) ? 8'hff : 8'h00,
                        (|x[23:16]) ? 8'hff : 8'h00,
                        (|x[15:8])  ? 8'hff : 8'h00,
                        (|x[7:0])   ? 8'hff : 8'h00};
        end
    endfunction

    function [7:0] gm_bitrev8;
        input [7:0] x;
        begin gm_bitrev8 = {x[0],x[1],x[2],x[3],x[4],x[5],x[6],x[7]}; end
    endfunction

    function [31:0] gm_brev8;
        input [31:0] x;
        begin
            gm_brev8 = {gm_bitrev8(x[31:24]), gm_bitrev8(x[23:16]),
                        gm_bitrev8(x[15:8]), gm_bitrev8(x[7:0])};
        end
    endfunction

    function [31:0] gm_zip;
        input [31:0] x;
        reg [31:0] y;
        integer n;
        begin
            y = 32'd0;
            for (n = 0; n < 16; n = n + 1) begin
                y[2*n] = x[n];
                y[2*n+1] = x[n+16];
            end
            gm_zip = y;
        end
    endfunction

    function [31:0] gm_unzip;
        input [31:0] x;
        reg [31:0] y;
        integer n;
        begin
            y = 32'd0;
            for (n = 0; n < 16; n = n + 1) begin
                y[n] = x[2*n];
                y[n+16] = x[2*n+1];
            end
            gm_unzip = y;
        end
    endfunction

    function [63:0] gm_clmul_full;
        input [31:0] a;
        input [31:0] b;
        reg [63:0] p;
        integer n;
        begin
            p = 64'd0;
            for (n = 0; n < 32; n = n + 1)
                if (b[n]) p = p ^ ({32'd0, a} << n);
            gm_clmul_full = p;
        end
    endfunction

    function [31:0] gm_xperm4;
        input [31:0] x;
        input [31:0] selectors;
        reg [31:0] y;
        integer n;
        integer source_index;
        begin
            y = 32'd0;
            for (n = 0; n < 8; n = n + 1) begin
                source_index = selectors[4*n +: 4];
                if (source_index < 8) y[4*n +: 4] = x[source_index*4 +: 4];
            end
            gm_xperm4 = y;
        end
    endfunction

    function [31:0] gm_xperm8;
        input [31:0] x;
        input [31:0] selectors;
        reg [31:0] y;
        integer n;
        integer source_index;
        begin
            y = 32'd0;
            for (n = 0; n < 4; n = n + 1) begin
                source_index = selectors[8*n +: 8];
                if (source_index < 4) y[8*n +: 8] = x[source_index*8 +: 8];
            end
            gm_xperm8 = y;
        end
    endfunction

    task emit;
        input [31:0] instruction;
        begin
            inst_mem[idx] = instruction;
            idx = idx + 1;
        end
    endtask

    task emit_li;
        input [4:0] rd;
        input [31:0] value;
        reg [19:0] upper;
        reg [11:0] lower;
        begin
            upper = value[31:12];
            lower = value[11:0];
            if (lower[11]) upper = upper + 20'd1;
            emit(rv_utype(upper, rd, OP_LUI));
            emit(rv_itype(lower, rd, 3'b000, rd, OP_ITYPE));
        end
    endtask

    task emit_checked;
        input [31:0] instruction;
        input [4:0] rd;
        input [31:0] expected;
        begin
            if (expect_count >= MAX_EXPECT) $fatal(1, "Zb TB expected-result table overflow");
            expect_pc[expect_count]    = BASE_PC + idx * 4;
            expect_rd[expect_count]    = rd;
            expect_value[expect_count] = expected;
            expect_seen[expect_count]  = 1'b0;
            expect_count = expect_count + 1;
            emit(instruction);
        end
    endtask

    // In normal group regression KLDJ_CFG_OP is ALL and every vector is
    // emitted.  With a numeric KLDJ_CFG_OP only the selected instruction (and
    // its dependent forwarding check, when applicable) is emitted, allowing
    // the same TB to validate the timing-minimal one-instruction build.
    task emit_checked_zb;
        input [7:0] op_id;
        input [31:0] instruction;
        input [4:0] rd;
        input [31:0] expected;
        begin
            if ((`KLDJ_CFG_OP == `KLDJ_ZB_OP_ALL) || (`KLDJ_CFG_OP == op_id))
                emit_checked(instruction, rd, expected);
        end
    endtask

    task build_program;
        reg [31:0] a;
        reg [31:0] b;
        reg [31:0] c;
        reg [63:0] product;
        begin
            if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBA) begin
            a = 32'h12345678;
            b = 32'h01020304;
            emit_li(5'd1, a);
            emit_li(5'd2, b);
            emit_checked_zb(`KLDJ_ZB_OP_SH1ADD, rv_rtype(7'b0010000, 5'd2, 5'd1, 3'b010, 5'd3, OP_RTYPE), 5'd3, b + (a << 1));
            emit_checked_zb(`KLDJ_ZB_OP_SH1ADD, rv_itype(12'd1, 5'd3, 3'b000, 5'd4, OP_ITYPE), 5'd4, b + (a << 1) + 1);
            emit_checked_zb(`KLDJ_ZB_OP_SH2ADD, rv_rtype(7'b0010000, 5'd2, 5'd1, 3'b100, 5'd5, OP_RTYPE), 5'd5, b + (a << 2));
            emit_checked_zb(`KLDJ_ZB_OP_SH3ADD, rv_rtype(7'b0010000, 5'd2, 5'd1, 3'b110, 5'd6, OP_RTYPE), 5'd6, b + (a << 3));
            end

            if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBB) begin
            a = 32'h800100f0;
            b = 32'h7fff0f0f;
            c = 32'h00108001;
            emit_li(5'd1, a);
            emit_li(5'd2, b);
            emit_checked_zb(`KLDJ_ZB_OP_ANDN, rv_rtype(7'b0100000, 5'd2, 5'd1, 3'b111, 5'd3, OP_RTYPE), 5'd3, a & ~b);
            emit_checked_zb(`KLDJ_ZB_OP_ANDN, rv_itype(12'd1, 5'd3, 3'b000, 5'd4, OP_ITYPE), 5'd4, (a & ~b) + 1);
            emit_checked_zb(`KLDJ_ZB_OP_ORN, rv_rtype(7'b0100000, 5'd2, 5'd1, 3'b110, 5'd5, OP_RTYPE), 5'd5, a | ~b);
            emit_checked_zb(`KLDJ_ZB_OP_XNOR, rv_rtype(7'b0100000, 5'd2, 5'd1, 3'b100, 5'd6, OP_RTYPE), 5'd6, ~(a ^ b));
            emit_li(5'd7, c);
            emit_checked_zb(`KLDJ_ZB_OP_CLZ, rv_itype(12'h600, 5'd7, 3'b001, 5'd8, OP_ITYPE), 5'd8, gm_clz(c));
            emit_checked_zb(`KLDJ_ZB_OP_CTZ, rv_itype(12'h601, 5'd7, 3'b001, 5'd9, OP_ITYPE), 5'd9, gm_ctz(c));
            emit_checked_zb(`KLDJ_ZB_OP_CPOP, rv_itype(12'h602, 5'd7, 3'b001, 5'd10, OP_ITYPE), 5'd10, gm_cpop(c));
            emit_checked_zb(`KLDJ_ZB_OP_MAX, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b110, 5'd11, OP_RTYPE), 5'd11, ($signed(a) > $signed(b)) ? a : b);
            emit_checked_zb(`KLDJ_ZB_OP_MAXU, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b111, 5'd12, OP_RTYPE), 5'd12, (a > b) ? a : b);
            emit_checked_zb(`KLDJ_ZB_OP_MIN, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b100, 5'd13, OP_RTYPE), 5'd13, ($signed(a) < $signed(b)) ? a : b);
            emit_checked_zb(`KLDJ_ZB_OP_MINU, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b101, 5'd14, OP_RTYPE), 5'd14, (a < b) ? a : b);
            emit_checked_zb(`KLDJ_ZB_OP_SEXT_B, rv_itype(12'h604, 5'd7, 3'b001, 5'd15, OP_ITYPE), 5'd15, {{24{c[7]}}, c[7:0]});
            emit_checked_zb(`KLDJ_ZB_OP_SEXT_H, rv_itype(12'h605, 5'd7, 3'b001, 5'd16, OP_ITYPE), 5'd16, {{16{c[15]}}, c[15:0]});
            emit_checked_zb(`KLDJ_ZB_OP_ZEXT_H, rv_rtype(7'b0000100, 5'd0, 5'd7, 3'b100, 5'd17, OP_RTYPE), 5'd17, {16'd0, c[15:0]});
            emit_checked_zb(`KLDJ_ZB_OP_ROL, rv_rtype(7'b0110000, 5'd2, 5'd1, 3'b001, 5'd18, OP_RTYPE), 5'd18, gm_rol(a, b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_ROR, rv_rtype(7'b0110000, 5'd2, 5'd1, 3'b101, 5'd19, OP_RTYPE), 5'd19, gm_ror(a, b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_RORI, rv_itype({7'b0110000, 5'd7}, 5'd1, 3'b101, 5'd20, OP_ITYPE), 5'd20, gm_ror(a, 5'd7));
            emit_checked_zb(`KLDJ_ZB_OP_ORC_B, rv_itype(12'h287, 5'd1, 3'b101, 5'd21, OP_ITYPE), 5'd21, gm_orc_b(a));
            emit_checked_zb(`KLDJ_ZB_OP_REV8, rv_itype(12'h698, 5'd1, 3'b101, 5'd22, OP_ITYPE), 5'd22, {a[7:0],a[15:8],a[23:16],a[31:24]});
            end

            if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBC) begin
            a = 32'h12345678;
            b = 32'h9abcdef0;
            product = gm_clmul_full(a, b);
            emit_li(5'd1, a);
            emit_li(5'd2, b);
            emit_checked_zb(`KLDJ_ZB_OP_CLMUL, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b001, 5'd3, OP_RTYPE), 5'd3, product[31:0]);
            emit_checked_zb(`KLDJ_ZB_OP_CLMUL, rv_itype(12'd1, 5'd3, 3'b000, 5'd4, OP_ITYPE), 5'd4, product[31:0] + 1);
            emit_checked_zb(`KLDJ_ZB_OP_CLMULH, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b011, 5'd5, OP_RTYPE), 5'd5, product[63:32]);
            emit_checked_zb(`KLDJ_ZB_OP_CLMULR, rv_rtype(7'b0000101, 5'd2, 5'd1, 3'b010, 5'd6, OP_RTYPE), 5'd6, product[62:31]);
            end

            if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBS) begin
            a = 32'h80000011;
            b = 32'd31;
            emit_li(5'd1, a);
            emit_li(5'd2, b);
            emit_checked_zb(`KLDJ_ZB_OP_BSET, rv_rtype(7'b0010100, 5'd2, 5'd1, 3'b001, 5'd3, OP_RTYPE), 5'd3, a | (32'h1 << b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_BSET, rv_itype(12'd1, 5'd3, 3'b000, 5'd4, OP_ITYPE), 5'd4, (a | (32'h1 << b[4:0])) + 1);
            emit_checked_zb(`KLDJ_ZB_OP_BCLR, rv_rtype(7'b0100100, 5'd2, 5'd1, 3'b001, 5'd5, OP_RTYPE), 5'd5, a & ~(32'h1 << b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_BINV, rv_rtype(7'b0110100, 5'd2, 5'd1, 3'b001, 5'd6, OP_RTYPE), 5'd6, a ^ (32'h1 << b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_BEXT, rv_rtype(7'b0100100, 5'd2, 5'd1, 3'b101, 5'd7, OP_RTYPE), 5'd7, {31'd0, a[b[4:0]]});
            emit_checked_zb(`KLDJ_ZB_OP_BSETI, rv_itype({7'b0010100,5'd5}, 5'd1, 3'b001, 5'd8, OP_ITYPE), 5'd8, a | (32'h1 << 5));
            emit_checked_zb(`KLDJ_ZB_OP_BCLRI, rv_itype({7'b0100100,5'd31}, 5'd1, 3'b001, 5'd9, OP_ITYPE), 5'd9, a & ~(32'h1 << 31));
            emit_checked_zb(`KLDJ_ZB_OP_BINVI, rv_itype({7'b0110100,5'd0}, 5'd1, 3'b001, 5'd10, OP_ITYPE), 5'd10, a ^ 32'h1);
            emit_checked_zb(`KLDJ_ZB_OP_BEXTI, rv_itype({7'b0100100,5'd4}, 5'd1, 3'b101, 5'd11, OP_ITYPE), 5'd11, {31'd0, a[4]});
            end

            if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBKB) begin
            a = 32'h89abcdef;
            b = 32'h13579bdf;
            emit_li(5'd1, a);
            emit_li(5'd2, b);
            emit_checked_zb(`KLDJ_ZB_OP_ANDN, rv_rtype(7'b0100000, 5'd2, 5'd1, 3'b111, 5'd3, OP_RTYPE), 5'd3, a & ~b);
            emit_checked_zb(`KLDJ_ZB_OP_ANDN, rv_itype(12'd1, 5'd3, 3'b000, 5'd4, OP_ITYPE), 5'd4, (a & ~b) + 1);
            emit_checked_zb(`KLDJ_ZB_OP_ORN, rv_rtype(7'b0100000, 5'd2, 5'd1, 3'b110, 5'd5, OP_RTYPE), 5'd5, a | ~b);
            emit_checked_zb(`KLDJ_ZB_OP_XNOR, rv_rtype(7'b0100000, 5'd2, 5'd1, 3'b100, 5'd6, OP_RTYPE), 5'd6, ~(a ^ b));
            emit_checked_zb(`KLDJ_ZB_OP_ROL, rv_rtype(7'b0110000, 5'd2, 5'd1, 3'b001, 5'd7, OP_RTYPE), 5'd7, gm_rol(a, b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_ROR, rv_rtype(7'b0110000, 5'd2, 5'd1, 3'b101, 5'd8, OP_RTYPE), 5'd8, gm_ror(a, b[4:0]));
            emit_checked_zb(`KLDJ_ZB_OP_RORI, rv_itype({7'b0110000,5'd7}, 5'd1, 3'b101, 5'd9, OP_ITYPE), 5'd9, gm_ror(a, 5'd7));
            emit_checked_zb(`KLDJ_ZB_OP_REV8, rv_itype(12'h698, 5'd1, 3'b101, 5'd10, OP_ITYPE), 5'd10, {a[7:0],a[15:8],a[23:16],a[31:24]});
            emit_checked_zb(`KLDJ_ZB_OP_BREV8, rv_itype(12'h687, 5'd1, 3'b101, 5'd11, OP_ITYPE), 5'd11, gm_brev8(a));
            emit_checked_zb(`KLDJ_ZB_OP_PACK, rv_rtype(7'b0000100, 5'd2, 5'd1, 3'b100, 5'd12, OP_RTYPE), 5'd12, {b[15:0],a[15:0]});
            emit_checked_zb(`KLDJ_ZB_OP_PACKH, rv_rtype(7'b0000100, 5'd2, 5'd1, 3'b111, 5'd13, OP_RTYPE), 5'd13, {16'd0,b[7:0],a[7:0]});
            emit_checked_zb(`KLDJ_ZB_OP_ZIP, rv_itype(12'h08f, 5'd1, 3'b001, 5'd14, OP_ITYPE), 5'd14, gm_zip(a));
            emit_checked_zb(`KLDJ_ZB_OP_UNZIP, rv_itype(12'h08f, 5'd1, 3'b101, 5'd15, OP_ITYPE), 5'd15, gm_unzip(a));
            end

            if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBKX) begin
            a = 32'h01234567;
            b = 32'h76543210;
            emit_li(5'd1, a);
            emit_li(5'd2, b);
            emit_checked_zb(`KLDJ_ZB_OP_XPERM4, rv_rtype(7'b0010100, 5'd2, 5'd1, 3'b010, 5'd3, OP_RTYPE), 5'd3, gm_xperm4(a, b));
            emit_checked_zb(`KLDJ_ZB_OP_XPERM4, rv_itype(12'd1, 5'd3, 3'b000, 5'd4, OP_ITYPE), 5'd4, gm_xperm4(a, b) + 1);
            c = 32'h03020100;
            emit_li(5'd2, c);
            emit_checked_zb(`KLDJ_ZB_OP_XPERM8, rv_rtype(7'b0010100, 5'd2, 5'd1, 3'b100, 5'd5, OP_RTYPE), 5'd5, gm_xperm8(a, c));
            end
        end
    endtask

    // Check only the extension program's expected commits.  Other commits are
    // initialization instructions or trailing NOPs and are intentionally
    // ignored.
    always @(negedge clk) begin
        if (!rst) begin
`ifdef KLDJ_EXT_ENABLE
            if (dut.zb_stall) zb_stall_seen = zb_stall_seen + 1;
`endif
            if (dut.wb_commit_valid) begin
                for (i = 0; i < expect_count; i = i + 1) begin
                    if (dut.wb_commit_pc == expect_pc[i]) begin
                        if (expect_seen[i]) begin
                            $display("[FAIL] duplicate commit at PC 0x%08x", expect_pc[i]);
                            fail_count = fail_count + 1;
                        end else if ((dut.wb_commit_rd_addr != expect_rd[i]) ||
                                     (dut.wb_commit_wb_data != expect_value[i])) begin
                            $display("[FAIL] PC 0x%08x rd x%0d got 0x%08x expected x%0d=0x%08x",
                                     expect_pc[i], dut.wb_commit_rd_addr, dut.wb_commit_wb_data,
                                     expect_rd[i], expect_value[i]);
                            expect_seen[i] = 1'b1;
                            seen_count = seen_count + 1;
                            fail_count = fail_count + 1;
                        end else begin
                            $display("[PASS] PC 0x%08x x%0d = 0x%08x",
                                     expect_pc[i], expect_rd[i], expect_value[i]);
                            expect_seen[i] = 1'b1;
                            seen_count = seen_count + 1;
                        end
                    end
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        idx = 0;
        expect_count = 0;
        seen_count = 0;
        fail_count = 0;
        zb_stall_seen = 0;
        for (i = 0; i < 512; i = i + 1) inst_mem[i] = 32'h00000013;
        for (i = 0; i < MAX_EXPECT; i = i + 1) expect_seen[i] = 1'b0;

        if (`KLDJ_ZB_CONFIG_COUNT != 1)
            $fatal(1, "Zb TB requires exactly one selected configuration");
        if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_NONE)
            $fatal(1, "Zb TB has no selected extension group");

        build_program;
        if (expect_count == 0)
            $fatal(1, "Zb TB emitted no vectors; check GROUP and ONLY_OP in zb_cfg.vh");
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycles = 0; (cycles < 4000) && (seen_count < expect_count); cycles = cycles + 1)
            @(posedge clk);
        repeat (8) @(posedge clk);

        if (seen_count != expect_count) begin
            $display("[FAIL] only %0d/%0d expected commits observed", seen_count, expect_count);
            for (i = 0; i < expect_count; i = i + 1)
                if (!expect_seen[i]) $display("       missing PC 0x%08x", expect_pc[i]);
            fail_count = fail_count + 1;
        end
        if (dut.reg5.regs[0] != 32'd0) begin
            $display("[FAIL] x0 changed to 0x%08x", dut.reg5.regs[0]);
            fail_count = fail_count + 1;
        end
        if ((`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBC) && (zb_stall_seen == 0)) begin
            $display("[FAIL] Zbc did not exercise the iterative stall path");
            fail_count = fail_count + 1;
        end

        if (fail_count != 0) begin
            $fatal(1, "Zb integration regression failed (%0d failures)", fail_count);
        end

        case (`KLDJ_ZB_GROUP_SEL)
            `KLDJ_ZB_GROUP_ZBA:  $display("ZB_ZBA_PASS");
            `KLDJ_ZB_GROUP_ZBB:  $display("ZB_ZBB_PASS");
            `KLDJ_ZB_GROUP_ZBC:  $display("ZB_ZBC_PASS");
            `KLDJ_ZB_GROUP_ZBS:  $display("ZB_ZBS_PASS");
            `KLDJ_ZB_GROUP_ZBKB: $display("ZB_ZBKB_PASS");
            `KLDJ_ZB_GROUP_ZBKX: $display("ZB_ZBKX_PASS");
            default: $fatal(1, "Zb TB invalid selected group");
        endcase
        if (`KLDJ_ZB_CFG_RTL_ON)
            $display("ZB_RTL_PASS");
        $finish;
    end

endmodule
