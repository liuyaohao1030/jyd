`timescale 1ns/1ps
`include "define.v"

module rv32m_supported_instr_tb;

localparam [6:0] OPCODE_LUI   = 7'b0110111;
localparam [6:0] OPCODE_JAL   = 7'b1101111;
localparam [6:0] OPCODE_OPIMM = 7'b0010011;
localparam [6:0] OPCODE_OP    = 7'b0110011;
localparam [6:0] OPCODE_LOAD  = 7'b0000011;
localparam [6:0] OPCODE_STORE = 7'b0100011;

localparam [2:0] F3_ADD_SUB = 3'b000;
localparam [2:0] F3_MUL     = 3'b000;
localparam [2:0] F3_MULH    = 3'b001;
localparam [2:0] F3_MULHSU  = 3'b010;
localparam [2:0] F3_MULHU   = 3'b011;
localparam [2:0] F3_DIV     = 3'b100;
localparam [2:0] F3_DIVU    = 3'b101;
localparam [2:0] F3_REM     = 3'b110;
localparam [2:0] F3_REMU    = 3'b111;
localparam [2:0] F3_LW      = 3'b010;
localparam [2:0] F3_SW      = 3'b010;

localparam [6:0] FUNCT7_MULDIV = 7'b0000001;
localparam [31:0] START_PC = `KLDJ_STARTPC;
localparam integer IMEM_WORDS = 512;
localparam integer MAX_CYCLES = 5000;

reg clk;
reg rst;
reg [31:0] tb_if_inst;
wire [31:0] tb_if_pc;
wire tb_ex_jump;
wire [31:0] tb_ex_jump_pc;
wire [31:0] tb_ex_res;

wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire        mem_we;
wire [3:0]  mem_be;
wire [31:0] mem_rdata;
wire        core_clk;

reg [31:0] imem [0:IMEM_WORDS-1];
reg [31:0] dut_dmem [0:1023];
reg [31:0] model_dmem [0:1023];
reg [31:0] model_regs [0:31];
reg [31:0] expected_regs [0:IMEM_WORDS-1][0:31];
reg [31:0] expected_next_pc [0:IMEM_WORDS-1];
reg [31:0] expected_inst [0:IMEM_WORDS-1];
reg        expected_valid [0:IMEM_WORDS-1];

integer i;
integer r;
integer prog_words;
integer step_count;
integer fail_count;
integer done_idx;
integer total_cases;
integer mem_write_count;
integer expected_store_count;
reg done;

assign mem_rdata = (^mem_addr === 1'bx) ? 32'h00000000 : dut_dmem[mem_addr[11:2]];

always @(posedge core_clk) begin
    if (mem_we) begin
        mem_write_count <= mem_write_count + 1;
        if (mem_be[0]) dut_dmem[mem_addr[11:2]][7:0]   <= mem_wdata[7:0];
        if (mem_be[1]) dut_dmem[mem_addr[11:2]][15:8]  <= mem_wdata[15:8];
        if (mem_be[2]) dut_dmem[mem_addr[11:2]][23:16] <= mem_wdata[23:16];
        if (mem_be[3]) dut_dmem[mem_addr[11:2]][31:24] <= mem_wdata[31:24];
    end
end

KLDJ_top dut (
     .clk          (clk)
    ,.rst          (rst)
    ,.tb_if_inst   (tb_if_inst)
    ,.tb_if_pc     (tb_if_pc)
    ,.tb_ex_jump   (tb_ex_jump)
    ,.tb_ex_jump_pc(tb_ex_jump_pc)
    ,.tb_ex_res    (tb_ex_res)
    ,.mem_addr     (mem_addr)
    ,.mem_wdata    (mem_wdata)
    ,.mem_we       (mem_we)
    ,.mem_be       (mem_be)
    ,.mem_rdata    (mem_rdata)
    ,.core_clk_o   (core_clk)
);

always @(*) begin
    if (^tb_if_pc === 1'bx)
        tb_if_inst = 32'h00000013;
    else
        tb_if_inst = imem[tb_if_pc[13:2]];
end

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

function automatic [31:0] curr_pc;
    begin
        curr_pc = START_PC + (prog_words << 2);
    end
endfunction

function automatic [31:0] rv32_r;
    input [6:0] funct7;
    input [4:0] rs2;
    input [4:0] rs1;
    input [2:0] funct3;
    input [4:0] rd;
    input [6:0] opcode;
    begin
        rv32_r = {funct7, rs2, rs1, funct3, rd, opcode};
    end
endfunction

function automatic [31:0] rv32_i;
    input [11:0] imm12;
    input [4:0]  rs1;
    input [2:0]  funct3;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
        rv32_i = {imm12, rs1, funct3, rd, opcode};
    end
endfunction

function automatic [31:0] rv32_u;
    input [19:0] imm20;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
        rv32_u = {imm20, rd, opcode};
    end
endfunction

function automatic [31:0] rv32_j;
    input [20:0] imm21;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
        rv32_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd, opcode};
    end
endfunction


function automatic [31:0] rv32_s;
    input [11:0] imm12;
    input [4:0]  rs2;
    input [4:0]  rs1;
    input [2:0]  funct3;
    input [6:0]  opcode;
    begin
        rv32_s = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], opcode};
    end
endfunction
function automatic [31:0] signed_div_res;
    input [31:0] a;
    input [31:0] b;
    reg signed [31:0] as;
    reg signed [31:0] bs;
    begin
        as = a;
        bs = b;
        if (b == 32'b0)
            signed_div_res = 32'hffffffff;
        else if ((a == 32'h80000000) && (b == 32'hffffffff))
            signed_div_res = 32'h80000000;
        else
            signed_div_res = as / bs;
    end
endfunction

function automatic [31:0] signed_rem_res;
    input [31:0] a;
    input [31:0] b;
    reg signed [31:0] as;
    reg signed [31:0] bs;
    begin
        as = a;
        bs = b;
        if (b == 32'b0)
            signed_rem_res = a;
        else if ((a == 32'h80000000) && (b == 32'hffffffff))
            signed_rem_res = 32'b0;
        else
            signed_rem_res = as % bs;
    end
endfunction

function automatic [31:0] unsigned_div_res;
    input [31:0] a;
    input [31:0] b;
    begin
        if (b == 32'b0)
            unsigned_div_res = 32'hffffffff;
        else
            unsigned_div_res = a / b;
    end
endfunction

function automatic [31:0] unsigned_rem_res;
    input [31:0] a;
    input [31:0] b;
    begin
        if (b == 32'b0)
            unsigned_rem_res = a;
        else
            unsigned_rem_res = a % b;
    end
endfunction

function automatic [31:0] mul_res;
    input [31:0] a;
    input [31:0] b;
    reg signed [63:0] as64;
    reg signed [63:0] bs64;
    reg signed [63:0] prod;
    begin
        as64 = {{32{a[31]}}, a};
        bs64 = {{32{b[31]}}, b};
        prod = as64 * bs64;
        mul_res = prod[31:0];
    end
endfunction

function automatic [31:0] mulh_res;
    input [31:0] a;
    input [31:0] b;
    reg signed [63:0] as64;
    reg signed [63:0] bs64;
    reg signed [63:0] prod;
    begin
        as64 = {{32{a[31]}}, a};
        bs64 = {{32{b[31]}}, b};
        prod = as64 * bs64;
        mulh_res = prod[63:32];
    end
endfunction

function automatic [31:0] mulhsu_res;
    input [31:0] a;
    input [31:0] b;
    reg signed [63:0] as64;
    reg signed [63:0] bu64_as_signed;
    reg signed [63:0] prod;
    begin
        as64 = {{32{a[31]}}, a};
        bu64_as_signed = {32'b0, b};
        prod = as64 * bu64_as_signed;
        mulhsu_res = prod[63:32];
    end
endfunction

function automatic [31:0] mulhu_res;
    input [31:0] a;
    input [31:0] b;
    reg [63:0] au64;
    reg [63:0] bu64;
    reg [63:0] prod;
    begin
        au64 = {32'b0, a};
        bu64 = {32'b0, b};
        prod = au64 * bu64;
        mulhu_res = prod[63:32];
    end
endfunction

task automatic model_write;
    input [4:0] rd;
    input [31:0] value;
    begin
        if (rd != 5'd0)
            model_regs[rd] = value;
        model_regs[0] = 32'b0;
    end
endtask

task automatic record_step;
    input [31:0] inst;
    input [31:0] next_pc;
    begin
        if (prog_words >= IMEM_WORDS)
            $fatal(1, "program too large: prog_words=%0d", prog_words);

        imem[prog_words] = inst;
        expected_inst[prog_words] = inst;
        expected_next_pc[prog_words] = next_pc;
        expected_valid[prog_words] = 1'b1;
        for (r = 0; r < 32; r = r + 1)
            expected_regs[prog_words][r] = model_regs[r];

        prog_words = prog_words + 1;
        step_count = step_count + 1;
    end
endtask

task automatic exec_lui;
    input [4:0] rd;
    input [19:0] imm20;
    begin
        model_write(rd, {imm20, 12'b0});
        record_step(rv32_u(imm20, rd, OPCODE_LUI), curr_pc() + 32'd4);
    end
endtask

task automatic exec_addi;
    input [4:0] rd;
    input [4:0] rs1;
    input integer imm;
    begin
        model_write(rd, model_regs[rs1] + $signed(imm));
        record_step(rv32_i(imm[11:0], rs1, F3_ADD_SUB, rd, OPCODE_OPIMM), curr_pc() + 32'd4);
    end
endtask

task automatic build_li;
    input [4:0] rd;
    input [31:0] value;
    reg signed [63:0] val64;
    reg signed [63:0] upper;
    reg signed [63:0] lower;
    begin
        val64 = $signed(value);
        upper = (val64 + 64'sd2048) >>> 12;
        lower = val64 - (upper <<< 12);

        if (upper == 0) begin
            exec_addi(rd, 5'd0, lower);
        end else begin
            exec_lui(rd, upper[19:0]);
            if (lower != 0)
                exec_addi(rd, rd, lower);
        end
    end
endtask

task automatic exec_m;
    input [2:0] funct3;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    input [31:0] value;
    begin
        model_write(rd, value);
        record_step(rv32_r(FUNCT7_MULDIV, rs2, rs1, funct3, rd, OPCODE_OP), curr_pc() + 32'd4);
    end
endtask


task automatic exec_sw;
    input [4:0] rs1;
    input [4:0] rs2;
    input integer imm;
    reg [31:0] addr;
    begin
        addr = model_regs[rs1] + $signed(imm);
        model_dmem[addr[11:2]] = model_regs[rs2];
        expected_store_count = expected_store_count + 1;
        record_step(rv32_s(imm[11:0], rs2, rs1, F3_SW, OPCODE_STORE), curr_pc() + 32'd4);
    end
endtask

task automatic exec_lw;
    input [4:0] rd;
    input [4:0] rs1;
    input integer imm;
    reg [31:0] addr;
    begin
        addr = model_regs[rs1] + $signed(imm);
        model_write(rd, model_dmem[addr[11:2]]);
        record_step(rv32_i(imm[11:0], rs1, F3_LW, rd, OPCODE_LOAD), curr_pc() + 32'd4);
    end
endtask
task automatic case_m;
    input [12*8-1:0] name;
    input [2:0] funct3;
    input [31:0] a;
    input [31:0] b;
    input [31:0] expected;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, a);
        build_li(5'd2, b);
        exec_m(funct3, 5'd3, 5'd1, 5'd2, expected);
        $display("[CASE] %0s a=0x%08h b=0x%08h expected=0x%08h", name, a, b, expected);
    end
endtask

task automatic case_forward;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, 32'd6);
        build_li(5'd2, 32'd7);
        exec_m(F3_MUL, 5'd3, 5'd1, 5'd2, mul_res(model_regs[5'd1], model_regs[5'd2]));
        exec_m(F3_MUL, 5'd4, 5'd3, 5'd2, mul_res(model_regs[5'd3], model_regs[5'd2]));
        exec_m(F3_MUL, 5'd5, 5'd2, 5'd4, mul_res(model_regs[5'd2], model_regs[5'd4]));
        exec_addi(5'd6, 5'd0, 6);
        exec_m(F3_DIV, 5'd7, 5'd5, 5'd6, signed_div_res(model_regs[5'd5], model_regs[5'd6]));
        exec_m(F3_REM, 5'd8, 5'd5, 5'd6, signed_rem_res(model_regs[5'd5], model_regs[5'd6]));
        $display("[CASE] forwarding chain expected x3=42 x4=294 x5=2058 x7=343 x8=0");
    end
endtask


task automatic case_consecutive_divrem;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, 32'hfffffff9);
        build_li(5'd2, 32'h00000003);
        exec_m(F3_DIV, 5'd3, 5'd1, 5'd2, signed_div_res(model_regs[5'd1], model_regs[5'd2]));
        exec_m(F3_REM, 5'd4, 5'd1, 5'd2, signed_rem_res(model_regs[5'd1], model_regs[5'd2]));
        exec_m(F3_DIVU, 5'd5, 5'd1, 5'd2, unsigned_div_res(model_regs[5'd1], model_regs[5'd2]));
        exec_m(F3_REMU, 5'd6, 5'd1, 5'd2, unsigned_rem_res(model_regs[5'd1], model_regs[5'd2]));
        $display("[CASE] consecutive DIV/REM/DIVU/REMU");
    end
endtask

task automatic case_div_dependent;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, 32'd7);
        build_li(5'd2, 32'd3);
        exec_m(F3_DIV, 5'd3, 5'd1, 5'd2, signed_div_res(model_regs[5'd1], model_regs[5'd2]));
        exec_addi(5'd4, 5'd3, 5);
        exec_m(F3_REM, 5'd5, 5'd4, 5'd2, signed_rem_res(model_regs[5'd4], model_regs[5'd2]));
        $display("[CASE] DIV result consumed by dependent ADDI/REM");
    end
endtask

task automatic case_div_store_no_repeat;
    begin
        total_cases = total_cases + 1;
        build_li(5'd10, 32'd128);
        build_li(5'd11, 32'h11112222);
        exec_sw(5'd10, 5'd11, 0);
        build_li(5'd1, 32'd7);
        build_li(5'd2, 32'd3);
        exec_m(F3_DIV, 5'd12, 5'd1, 5'd2, signed_div_res(model_regs[5'd1], model_regs[5'd2]));
        build_li(5'd11, 32'h33334444);
        exec_sw(5'd10, 5'd11, 4);
        exec_lw(5'd13, 5'd10, 0);
        exec_lw(5'd14, 5'd10, 4);
        $display("[CASE] store before/after DIV, mem_we must not repeat");
    end
endtask

task automatic case_consecutive_mul;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, 32'd3);
        build_li(5'd2, 32'd4);
        exec_m(F3_MUL, 5'd3, 5'd1, 5'd2, mul_res(model_regs[5'd1], model_regs[5'd2]));
        exec_m(F3_MULH, 5'd4, 5'd3, 5'd2, mulh_res(model_regs[5'd3], model_regs[5'd2]));
        exec_m(F3_MULHU, 5'd5, 5'd3, 5'd4, mulhu_res(model_regs[5'd3], model_regs[5'd4]));
        $display("[CASE] consecutive MUL/MULH/MULHU");
    end
endtask

task automatic case_mul_dependent;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, 32'd3);
        build_li(5'd2, 32'd4);
        exec_m(F3_MUL, 5'd3, 5'd1, 5'd2, mul_res(model_regs[5'd1], model_regs[5'd2]));
        exec_addi(5'd4, 5'd3, 5);
        exec_m(F3_MUL, 5'd5, 5'd4, 5'd2, mul_res(model_regs[5'd4], model_regs[5'd2]));
        $display("[CASE] MUL result consumed by dependent ADDI/MUL");
    end
endtask

task automatic case_mul_div_mix;
    begin
        total_cases = total_cases + 1;
        build_li(5'd1, 32'hfffffff9);
        build_li(5'd2, 32'd3);
        exec_m(F3_MUL, 5'd3, 5'd1, 5'd2, mul_res(model_regs[5'd1], model_regs[5'd2]));
        exec_m(F3_DIV, 5'd4, 5'd3, 5'd2, signed_div_res(model_regs[5'd3], model_regs[5'd2]));
        exec_m(F3_REM, 5'd5, 5'd3, 5'd2, signed_rem_res(model_regs[5'd3], model_regs[5'd2]));
        exec_m(F3_MULHSU, 5'd6, 5'd4, 5'd2, mulhsu_res(model_regs[5'd4], model_regs[5'd2]));
        $display("[CASE] MUL before/after DIV/REM");
    end
endtask

task automatic case_mul_store_no_repeat;
    begin
        total_cases = total_cases + 1;
        build_li(5'd10, 32'd160);
        build_li(5'd11, 32'h55556666);
        exec_sw(5'd10, 5'd11, 0);
        build_li(5'd1, 32'd3);
        build_li(5'd2, 32'd4);
        exec_m(F3_MUL, 5'd12, 5'd1, 5'd2, mul_res(model_regs[5'd1], model_regs[5'd2]));
        build_li(5'd11, 32'h77778888);
        exec_sw(5'd10, 5'd11, 4);
        exec_lw(5'd13, 5'd10, 0);
        exec_lw(5'd14, 5'd10, 4);
        $display("[CASE] store before/after MUL, mem_we must not repeat");
    end
endtask
task automatic finish_program;
    reg [31:0] final_pc;
    begin
        final_pc = curr_pc();
        record_step(rv32_j(21'd0, 5'd0, OPCODE_JAL), final_pc);
        done_idx = prog_words - 1;
    end
endtask

task automatic check_step;
    input integer idx;
    reg step_ok;
    begin
        step_ok = 1'b1;
        for (r = 0; r < 32; r = r + 1) begin
            if (dut.reg5.regs[r] !== expected_regs[idx][r]) begin
                step_ok = 1'b0;
                fail_count = fail_count + 1;
                $display("[FAIL] step=%0d pc=0x%08h inst=0x%08h x%0d expected=0x%08h got=0x%08h",
                    idx, START_PC + (idx << 2), expected_inst[idx], r, expected_regs[idx][r], dut.reg5.regs[r]);
            end
        end
        if (step_ok) begin
            $display("[PASS] retire step=%0d pc=0x%08h inst=0x%08h next_pc=0x%08h",
                idx, START_PC + (idx << 2), expected_inst[idx], expected_next_pc[idx]);
        end
    end
endtask

initial begin
    rst = 1'b1;
    tb_if_inst = 32'h00000013;
    prog_words = 0;
    step_count = 0;
    fail_count = 0;
    done_idx = 0;
    total_cases = 0;
    mem_write_count = 0;
    expected_store_count = 0;
    done = 1'b0;

    for (i = 0; i < IMEM_WORDS; i = i + 1) begin
        imem[i] = 32'h00000013;
        expected_next_pc[i] = 32'b0;
        expected_inst[i] = 32'h00000013;
        expected_valid[i] = 1'b0;
        for (r = 0; r < 32; r = r + 1)
            expected_regs[i][r] = 32'b0;
    end

    for (i = 0; i < 32; i = i + 1)
        model_regs[i] = 32'b0;

    for (i = 0; i < 1024; i = i + 1) begin
        dut_dmem[i] = 32'b0;
        model_dmem[i] = 32'b0;
    end

    case_m("MUL_3_4", F3_MUL, 32'h00000003, 32'h00000004, mul_res(32'h00000003, 32'h00000004));
    case_m("MUL_N3_4", F3_MUL, 32'hfffffffd, 32'h00000004, mul_res(32'hfffffffd, 32'h00000004));
    case_m("MUL_FF_FF", F3_MUL, 32'hffffffff, 32'hffffffff, mul_res(32'hffffffff, 32'hffffffff));
    case_m("MULH_N1_N1", F3_MULH, 32'hffffffff, 32'hffffffff, mulh_res(32'hffffffff, 32'hffffffff));
    case_m("MULH_MIN_2", F3_MULH, 32'h80000000, 32'h00000002, mulh_res(32'h80000000, 32'h00000002));
    case_m("MULHSU_N1_2", F3_MULHSU, 32'hffffffff, 32'h00000002, mulhsu_res(32'hffffffff, 32'h00000002));
    case_m("MULHSU_MIN_2", F3_MULHSU, 32'h80000000, 32'h00000002, mulhsu_res(32'h80000000, 32'h00000002));
    case_m("MULHU_FF_FF", F3_MULHU, 32'hffffffff, 32'hffffffff, mulhu_res(32'hffffffff, 32'hffffffff));
    case_m("MUL",    F3_MUL,    32'hffffffff, 32'h00000002, mul_res(32'hffffffff, 32'h00000002));
    case_m("MULH",   F3_MULH,   32'h80000000, 32'h00000002, mulh_res(32'h80000000, 32'h00000002));
    case_m("MULHSU", F3_MULHSU, 32'hfffffffe, 32'h00000003, mulhsu_res(32'hfffffffe, 32'h00000003));
    case_m("MULHU",  F3_MULHU,  32'hffffffff, 32'hffffffff, mulhu_res(32'hffffffff, 32'hffffffff));

    case_m("DIV_7_3", F3_DIV, 32'h00000007, 32'h00000003, signed_div_res(32'h00000007, 32'h00000003));
    case_m("REM_7_3", F3_REM, 32'h00000007, 32'h00000003, signed_rem_res(32'h00000007, 32'h00000003));
    case_m("DIV_N7_3", F3_DIV, 32'hfffffff9, 32'h00000003, signed_div_res(32'hfffffff9, 32'h00000003));
    case_m("REM_N7_3", F3_REM, 32'hfffffff9, 32'h00000003, signed_rem_res(32'hfffffff9, 32'h00000003));
    case_m("DIV_7_N3", F3_DIV, 32'h00000007, 32'hfffffffd, signed_div_res(32'h00000007, 32'hfffffffd));
    case_m("REM_7_N3", F3_REM, 32'h00000007, 32'hfffffffd, signed_rem_res(32'h00000007, 32'hfffffffd));
    case_m("DIV_N7_N3", F3_DIV, 32'hfffffff9, 32'hfffffffd, signed_div_res(32'hfffffff9, 32'hfffffffd));
    case_m("REM_N7_N3", F3_REM, 32'hfffffff9, 32'hfffffffd, signed_rem_res(32'hfffffff9, 32'hfffffffd));
    case_m("DIV",    F3_DIV,    32'h00000007, 32'hfffffffe, signed_div_res(32'h00000007, 32'hfffffffe));
    case_m("DIV_NEG",F3_DIV,    32'hfffffff9, 32'h00000002, signed_div_res(32'hfffffff9, 32'h00000002));
    case_m("DIV_ZERO",F3_DIV,   32'h12345678, 32'h00000000, signed_div_res(32'h12345678, 32'h00000000));
    case_m("DIV_OVF",F3_DIV,    32'h80000000, 32'hffffffff, signed_div_res(32'h80000000, 32'hffffffff));
    case_m("DIVU",   F3_DIVU,   32'hffffffff, 32'h00000002, unsigned_div_res(32'hffffffff, 32'h00000002));
    case_m("DIVU_ZERO",F3_DIVU, 32'h12345678, 32'h00000000, unsigned_div_res(32'h12345678, 32'h00000000));

    case_m("REM",    F3_REM,    32'hfffffff9, 32'h00000002, signed_rem_res(32'hfffffff9, 32'h00000002));
    case_m("REM_POS",F3_REM,    32'h00000007, 32'hfffffffe, signed_rem_res(32'h00000007, 32'hfffffffe));
    case_m("REM_ZERO",F3_REM,   32'h12345678, 32'h00000000, signed_rem_res(32'h12345678, 32'h00000000));
    case_m("REM_OVF",F3_REM,    32'h80000000, 32'hffffffff, signed_rem_res(32'h80000000, 32'hffffffff));
    case_m("REMU",   F3_REMU,   32'hffffffff, 32'h00000002, unsigned_rem_res(32'hffffffff, 32'h00000002));
    case_m("REMU_ZERO",F3_REMU, 32'h12345678, 32'h00000000, unsigned_rem_res(32'h12345678, 32'h00000000));

    case_forward();
    case_consecutive_mul();
    case_mul_dependent();
    case_mul_div_mix();
    case_mul_store_no_repeat();
    case_consecutive_divrem();
    case_div_dependent();
    case_div_store_no_repeat();
    finish_program();

    repeat (5) @(posedge clk);
    rst = 1'b0;
end

initial begin
    integer cycles;
    integer retire_idx;
    reg [31:0] expected_retire_pc;
    reg [31:0] retired_pc;

    @(negedge rst);
    expected_retire_pc = START_PC;

    for (cycles = 0; cycles < MAX_CYCLES; cycles = cycles + 1) begin
        @(posedge core_clk);
        #1;

        if (dut.wb_commit_valid) begin
            retired_pc = dut.wb_commit_pc;
            retire_idx = (retired_pc - START_PC) >> 2;

            if ((retire_idx < 0) || (retire_idx >= IMEM_WORDS))
                $fatal(1, "retire pc out of range: pc=0x%08h idx=%0d", retired_pc, retire_idx);

            if (retired_pc !== expected_retire_pc) begin
                fail_count = fail_count + 1;
                $display("[FAIL] retired pc expected=0x%08h got=0x%08h idx=%0d inst=0x%08h",
                    expected_retire_pc, retired_pc, retire_idx, imem[retire_idx]);
            end

            if (!expected_valid[retire_idx])
                $fatal(1, "unexpected retirement at pc=0x%08h idx=%0d inst=0x%08h",
                    retired_pc, retire_idx, imem[retire_idx]);

            check_step(retire_idx);

            if (retire_idx == done_idx) begin
                if (mem_write_count != expected_store_count) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] mem_write_count expected=%0d got=%0d", expected_store_count, mem_write_count);
                end
                if (fail_count == 0) begin
                    $display("[SUMMARY] rv32m supported pipeline test passed.");
                    $display("[INFO] total_cases=%0d retired_steps=%0d program_words=%0d cycles=%0d",
                        total_cases, step_count, prog_words, cycles + 1);
                end else begin
                    $fatal(1, "[SUMMARY] rv32m supported pipeline test failed, fail_count=%0d", fail_count);
                end
                done = 1'b1;
                $finish;
            end

            expected_retire_pc = expected_next_pc[retire_idx];
        end
    end

    if (!done)
        $fatal(1, "timeout: rv32m supported pipeline test did not finish");
end

endmodule
