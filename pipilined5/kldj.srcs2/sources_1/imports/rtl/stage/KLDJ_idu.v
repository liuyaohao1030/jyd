`include "../define.v"
`include "../zb/zb_cfg.vh"

module KLDJ_idu(
    //system input
    input      wire [`KLDJ_INST]        inst_i
    ,input      wire [`KLDJ_PC]        pc_i
    ,input      wire [`KLDJ_PC]         snpc

    //regfile signal
    ,output    wire [`KLDJ_REGADDR] rs1_addr
    ,output    wire                     rs1_ren
    ,input     wire [`KLDJ_REG]     rs1_data

    ,output    wire [`KLDJ_REGADDR] rs2_addr
    ,output    wire                    rs2_ren
    ,input     wire [`KLDJ_REG]     rs2_data

      ,output    wire [`KLDJ_REGADDR] rd_addr

    //control out signal
    ,output    wire [17:0]            exu_op
    ,output    wire [9:0]             alu_ctrl
    ,output    wire                  wbctl_op

    //id out signal
    ,output    wire [`KLDJ_DATA]      data1
    ,output    wire [`KLDJ_DATA]      data2
    ,output    wire [`KLDJ_DATA]      data3
    ,output    wire [`KLDJ_DATA]    data4
        ,output    wire [3:0]           id_ls_ctl

    // CSR signals
    ,output    wire [11:0]          csr_addr
    ,output    wire                 csr_op
    ,output    wire [4:0]          csr_zimm
);

//----------------------------------decode---------------------------//
wire   [ 4:0]   rd     ;
wire   [ 4:0]   rs1    ;
wire   [ 4:0]   rs2    ;
assign  rd       =  inst_i [11:7]   ;
assign  rs1      =  inst_i [19:15]  ;
assign  rs2      =  inst_i [24:20]  ;

wire [6:0] opcode ;
wire [2:0] funct3 ;

/* verilator lint_off UNUSEDSIGNAL */
wire [6:0] funct7 ;
/* verilator lint_on UNUSEDSIGNAL */

wire [31:0] i_imm ;
wire [31:0] j_imm ;
wire [31:0] u_imm ;
wire [31:0] s_imm ;
wire [31:0] b_imm ;

wire [31:0] inst = inst_i;
wire [31:0] pc = pc_i;

assign opcode = inst[6:0];
assign funct3 = inst[14:12];
assign funct7 = inst[31:25];

assign i_imm = {{20{inst[31]}}, inst[31:20]};
assign j_imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
assign u_imm = {inst[31:12], {12{1'b0}}};
assign s_imm = {{21{inst[31]}}, inst[30:25], inst[11:7]};
assign b_imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};

//===== [OPT] Common funct3/funct7 sub-expressions (1-level LUT) =====//
wire f3_000 = ~funct3[2] & ~funct3[1] & ~funct3[0];
wire f3_001 = ~funct3[2] & ~funct3[1] &  funct3[0];
wire f3_010 = ~funct3[2] &  funct3[1] & ~funct3[0];
wire f3_011 = ~funct3[2] &  funct3[1] &  funct3[0];
wire f3_100 =  funct3[2] & ~funct3[1] & ~funct3[0];
wire f3_101 =  funct3[2] & ~funct3[1] &  funct3[0];
wire f3_110 =  funct3[2] &  funct3[1] & ~funct3[0];
wire f3_111 =  funct3[2] &  funct3[1] &  funct3[0];

//-----------------------------------decode--------------------------------//

wire type_i = (opcode[6:2] == `KLDJ_OPIMM)    ;
wire type_r = (opcode[6:2] == `KLDJ_OP)    ;
wire type_branch = (opcode[6:2] == `KLDJ_BRANCH)    ;
wire type_load = (opcode[6:2] == `KLDJ_LOAD) & (opcode[1:0] == 2'b11)     ;
wire type_store = (opcode[6:2] == `KLDJ_STORE)     ;

wire inst_lui   = (opcode[6:2] == `KLDJ_LUI)    ;
wire inst_auipc = (opcode[6:2] == `KLDJ_AUIPC)  ;
wire inst_jal   = (opcode[6:2] == `KLDJ_JAL)    ;
wire inst_jalr  = (opcode[6:2] == `KLDJ_JALR)   ;

// SYSTEM type detection
wire type_system = (opcode[6:2] == `KLDJ_SYSTEM) && (opcode[1:0] == 2'b11);

//===== [OPT] M-extension common condition =====//
wire m_ext = type_r & (funct7 == 7'b0000001);

//===== [OPT] Use f3_xxx for CSR/Branch/Load/Store decode =====//
// CSR instruction detection (funct3 != 000)
wire inst_csrrw  = type_system & f3_001;
wire inst_csrrs  = type_system & f3_010;
wire inst_csrrc  = type_system & f3_011;
wire inst_csrrwi = type_system & f3_101;
wire inst_csrrsi = type_system & f3_110;
wire inst_csrrci = type_system & f3_111;

// ecall: SYSTEM + funct3=000 + all zeros in csr/rs1/rd fields
wire inst_ecall = type_system & f3_000 &
                 (inst[31:20] == 12'h000) & (inst[19:15] == 5'b0) & (inst[11:7] == 5'b0);

// mret: SYSTEM + funct3=000 + inst[31:20]=001100000010
wire inst_mret = type_system & f3_000 & (inst[31:20] == 12'h302);

// CSR operation flag
wire csr_op_w = inst_csrrw | inst_csrrs | inst_csrrc |
                inst_csrrwi | inst_csrrsi | inst_csrrci;

// CSR address and zimm
assign csr_addr = inst[31:20];
assign csr_zimm = inst[19:15];
assign csr_op   = csr_op_w;

//===== [OPT] Use f3_xxx for store/load/branch/R-type decode =====//
wire inst_sb    = type_store & f3_000;
wire inst_sh    = type_store & f3_001;
wire inst_sw    = type_store & f3_010;

wire inst_lb    = type_load & f3_000;
wire inst_lh    = type_load & f3_001;
wire inst_lw    = type_load & f3_010;
wire inst_ld    = type_load & f3_011;
wire inst_lbu   = type_load & f3_100;
wire inst_lhu   = type_load & f3_101;

wire inst_beq   = type_branch & f3_000;
wire inst_bne   = type_branch & f3_001;
wire inst_blt   = type_branch & f3_100;
wire inst_bge   = type_branch & f3_101;
wire inst_bltu  = type_branch & f3_110;
wire inst_bgeu  = type_branch & f3_111;

wire inst_add   = type_r & f3_000 & ~funct7[5] & ~funct7[0];
wire inst_sub   = type_r & f3_000 &  funct7[5] & ~funct7[0];
wire inst_sll   = type_r & f3_001 & ~funct7[0];
wire inst_slt   = type_r & f3_010 & ~funct7[0];
wire inst_sltu  = type_r & f3_011 & ~funct7[0];
wire inst_xor   = type_r & f3_100 & ~funct7[0];
wire inst_srl   = type_r & f3_101 & ~funct7[5] & ~funct7[0];
wire inst_sra   = type_r & f3_101 &  funct7[5] & ~funct7[0];
wire inst_or    = type_r & f3_110 & ~funct7[0];
wire inst_and   = type_r & f3_111 & ~funct7[0];

//===== [OPT] Use m_ext for M-extension decode =====//
wire inst_mul    = m_ext & f3_000;
wire inst_mulh   = m_ext & f3_001;
wire inst_mulhsu = m_ext & f3_010;
wire inst_mulhu  = m_ext & f3_011;
wire inst_div    = m_ext & f3_100;
wire inst_divu   = m_ext & f3_101;
wire inst_rem    = m_ext & f3_110;
wire inst_remu   = m_ext & f3_111;

wire inst_addi  = type_i & f3_000;
wire inst_slti  = type_i & f3_010;
wire inst_sltiu = type_i & f3_011;
wire inst_xori  = type_i & f3_100;
wire inst_ori   = type_i & f3_110;
wire inst_andi  = type_i & f3_111;
wire inst_slli  = type_i & f3_001;
wire inst_srli  = type_i & f3_101 & ~i_imm[10];
wire inst_srai  = type_i & f3_101 &  i_imm[10];

wire jump = inst_jal | inst_jalr;

//===== [OPT] rd_wen simplified: RISC-V only S-type and B-type have no rd =====//
wire rd_wen = ~(type_store | type_branch);

//decode IMM
wire i_imm_en = type_load | inst_jalr | type_i;
wire j_imm_en = inst_jal;
wire u_imm_en = inst_lui | inst_auipc;
wire s_imm_en = type_store;
wire b_imm_en = type_branch;

wire [31:0] imm;
assign imm = i_imm & {32{i_imm_en}} | j_imm & {32{j_imm_en}} |
    u_imm & {32{u_imm_en}} | s_imm & {32{s_imm_en}} | b_imm & {32{b_imm_en}};

// The Zb decoder exists only in an extension build.  In the default build the
// following block is fully preprocessed out, leaving the original IDU logic
// and its timing unchanged.
`ifdef KLDJ_EXT_ENABLE
wire       zb_hit;
wire [7:0] zb_uop;
wire [1:0] zb_op2_sel;

KLDJ_zb_decode #(
     .GROUP  (`KLDJ_ZB_GROUP_SEL)
    ,.ONLY_OP(`KLDJ_CFG_OP      )
) u_KLDJ_zb_decode (
     .inst   (inst      )
    ,.hit    (zb_hit    )
    ,.uop    (zb_uop    )
    ,.op2_sel(zb_op2_sel)
);
`endif

reg                         rs1_ren_r;
reg                         rs2_ren_r;
reg [`KLDJ_REGADDR]         rs1_addr_r;
reg [`KLDJ_REGADDR]         rs2_addr_r;
reg [`KLDJ_REGADDR]         rd_addr_r;
reg [17:0]                  exu_op_r;
reg [9:0]                   alu_ctrl_r;
reg                         wbctl_op_r;
reg [`KLDJ_DATA]            data1_r;
reg [`KLDJ_DATA]            data2_r;
reg [`KLDJ_DATA]            data3_r;
reg [`KLDJ_DATA]            data4_r;
reg [3:0]                   id_ls_ctl_r;

//===== [OPT] Parallel case decode — replaces 47-level priority if-else chain =====//
always @(*) begin
    rs1_ren_r  = type_store | type_load | type_branch | type_i | type_r | inst_jalr |
                 inst_csrrw | inst_csrrs | inst_csrrc;
    rs2_ren_r  = type_branch | type_store | type_r;
    rs1_addr_r = rs1_ren_r ? rs1 : 5'd0;
    rs2_addr_r = rs2_ren_r ? rs2 : 5'd0;
    rd_addr_r  = rd_wen ? rd : 5'd0;
    wbctl_op_r = rd_wen;

    exu_op_r   = 18'd0;
    alu_ctrl_r = 10'd0;
    data1_r    = `KLDJ_ZERO32;
    data2_r    = `KLDJ_ZERO32;
    data3_r    = `KLDJ_ZERO32;
    data4_r    = `KLDJ_ZERO32;
    id_ls_ctl_r = 4'd0;

`ifdef KLDJ_EXT_ENABLE
    if (zb_hit) begin
        // All supported RV32 Zb encodings are OP or OP-IMM, hence the
        // existing generic rs1/rs2 read-enable and forwarding machinery is
        // already correct.  Only data2 needs an explicit IMM5 selection.
        exu_op_r = `KLDJ_EXU_ZB_TAG | {10'd0, zb_uop};
        data1_r  = rs1_data;
        case (zb_op2_sel)
            `KLDJ_ZB_OP2_RS2:  data2_r = rs2_data;
            `KLDJ_ZB_OP2_IMM5: data2_r = {27'd0, inst[24:20]};
            default:            data2_r = `KLDJ_ZERO32;
        endcase
    end else begin
`endif
    case (1'b1)
        //---------- I-type ALU ----------//
        inst_addi: begin
            exu_op_r   = 18'h0;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_slti: begin
            exu_op_r   = 18'h1;
            alu_ctrl_r = 10'h220;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_sltiu: begin
            exu_op_r   = 18'h2;
            alu_ctrl_r = 10'h230;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_xori: begin
            exu_op_r   = 18'h3;
            alu_ctrl_r = 10'h100;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_ori: begin
            exu_op_r   = 18'h4;
            alu_ctrl_r = 10'h080;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_andi: begin
            exu_op_r   = 18'h5;
            alu_ctrl_r = 10'h040;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_slli: begin
            exu_op_r   = 18'h6;
            alu_ctrl_r = 10'h004;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_srli: begin
            exu_op_r   = 18'h7;
            alu_ctrl_r = 10'h005;
            data1_r    = rs1_data;
            data2_r    = imm;
        end
        inst_srai: begin
            exu_op_r   = 18'h8;
            alu_ctrl_r = 10'h007;
            data1_r    = rs1_data;
            data2_r    = imm;
        end

        //---------- JALR ----------//
        inst_jalr: begin
            exu_op_r   = 18'h9;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            data3_r    = snpc;
        end

        //---------- R-type ALU ----------//
        inst_add: begin
            exu_op_r   = 18'ha;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_sub: begin
            exu_op_r   = 18'hb;
            alu_ctrl_r = 10'h028;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_sll: begin
            exu_op_r   = 18'hc;
            alu_ctrl_r = 10'h004;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_slt: begin
            exu_op_r   = 18'hd;
            alu_ctrl_r = 10'h220;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_sltu: begin
            exu_op_r   = 18'he;
            alu_ctrl_r = 10'h230;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_xor: begin
            exu_op_r   = 18'hf;
            alu_ctrl_r = 10'h100;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_srl: begin
            exu_op_r   = 18'h10;
            alu_ctrl_r = 10'h005;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_sra: begin
            exu_op_r   = 18'h11;
            alu_ctrl_r = 10'h007;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_or: begin
            exu_op_r   = 18'h12;
            alu_ctrl_r = 10'h080;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_and: begin
            exu_op_r   = 18'h13;
            alu_ctrl_r = 10'h040;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end

        //---------- M extension ----------//
        inst_mul: begin
            exu_op_r   = 18'h25;
            alu_ctrl_r = 10'h001;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_mulh: begin
            exu_op_r   = 18'h26;
            alu_ctrl_r = 10'h002;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_mulhsu: begin
            exu_op_r   = 18'h27;
            alu_ctrl_r = 10'h003;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_mulhu: begin
            exu_op_r   = 18'h28;
            alu_ctrl_r = 10'h010;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_div: begin
            exu_op_r   = 18'h29;
            alu_ctrl_r = 10'h011;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_divu: begin
            exu_op_r   = 18'h2a;
            alu_ctrl_r = 10'h012;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_rem: begin
            exu_op_r   = 18'h2b;
            alu_ctrl_r = 10'h013;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end
        inst_remu: begin
            exu_op_r   = 18'h2c;
            alu_ctrl_r = 10'h020;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
        end

        //---------- Branch ----------//
        inst_beq: begin
            exu_op_r   = 18'h14;
            alu_ctrl_r = 10'h028;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
            data3_r    = pc;
            data4_r    = imm;
        end
        inst_bne: begin
            exu_op_r   = 18'h15;
            alu_ctrl_r = 10'h028;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
            data3_r    = pc;
            data4_r    = imm;
        end
        inst_blt: begin
            exu_op_r   = 18'h16;
            alu_ctrl_r = 10'h028;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
            data3_r    = pc;
            data4_r    = imm;
        end
        inst_bge: begin
            exu_op_r   = 18'h17;
            alu_ctrl_r = 10'h028;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
            data3_r    = pc;
            data4_r    = imm;
        end
        inst_bltu: begin
            exu_op_r   = 18'h18;
            alu_ctrl_r = 10'h038;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
            data3_r    = pc;
            data4_r    = imm;
        end
        inst_bgeu: begin
            exu_op_r   = 18'h19;
            alu_ctrl_r = 10'h038;
            data1_r    = rs1_data;
            data2_r    = rs2_data;
            data3_r    = pc;
            data4_r    = imm;
        end

        //---------- U-type ----------//
        inst_lui: begin
            exu_op_r   = 18'h1a;
            alu_ctrl_r = 10'h008;
            data2_r    = imm;
        end
        inst_auipc: begin
            exu_op_r   = 18'h1b;
            alu_ctrl_r = 10'h008;
            data1_r    = pc;
            data2_r    = imm;
        end

        //---------- JAL ----------//
        inst_jal: begin
            exu_op_r   = 18'h1c;
            alu_ctrl_r = 10'h008;
            data1_r    = pc;
            data2_r    = imm;
            data3_r    = snpc;
        end

        //---------- Load ----------//
        inst_lb: begin
            exu_op_r   = 18'h1d;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            id_ls_ctl_r = 4'b1100;
        end
        inst_lh: begin
            exu_op_r   = 18'h1e;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            id_ls_ctl_r = 4'b1101;
        end
        inst_lw: begin
            exu_op_r   = 18'h1f;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            id_ls_ctl_r = 4'b1110;
        end
        inst_lbu: begin
            exu_op_r   = 18'h20;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            id_ls_ctl_r = 4'b1000;
        end
        inst_lhu: begin
            exu_op_r   = 18'h21;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            id_ls_ctl_r = 4'b1001;
        end

        //---------- Store ----------//
        inst_sb: begin
            exu_op_r   = 18'h22;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            data3_r    = rs2_data;
            id_ls_ctl_r = 4'b0000;
        end
        inst_sh: begin
            exu_op_r   = 18'h23;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            data3_r    = rs2_data;
            id_ls_ctl_r = 4'b0001;
        end
        inst_sw: begin
            exu_op_r   = 18'h24;
            alu_ctrl_r = 10'h008;
            data1_r    = rs1_data;
            data2_r    = imm;
            data3_r    = rs2_data;
            id_ls_ctl_r = 4'b0010;
        end

        //---------- CSR ----------//
        inst_csrrw: begin
            exu_op_r   = `KLDJ_EXU_CSRRW;
            data1_r    = rs1_data;
        end
        inst_csrrs: begin
            exu_op_r   = `KLDJ_EXU_CSRRS;
            data1_r    = rs1_data;
        end
        inst_csrrc: begin
            exu_op_r   = `KLDJ_EXU_CSRRC;
            data1_r    = rs1_data;
        end
        inst_csrrwi: begin
            exu_op_r   = `KLDJ_EXU_CSRRWI;
            data1_r    = {27'b0, inst[19:15]};
        end
        inst_csrrsi: begin
            exu_op_r   = `KLDJ_EXU_CSRRSI;
            data1_r    = {27'b0, inst[19:15]};
        end
        inst_csrrci: begin
            exu_op_r   = `KLDJ_EXU_CSRRCI;
            data1_r    = {27'b0, inst[19:15]};
        end

        //---------- System ----------//
        inst_ecall: begin
            exu_op_r   = `KLDJ_EXU_ECALL;
        end
        inst_mret: begin
            exu_op_r   = `KLDJ_EXU_MRET;
        end

        default: ;  // NOP — all defaults from above
    endcase
`ifdef KLDJ_EXT_ENABLE
    end
`endif
end

assign rs1_ren  = rs1_ren_r;
assign rs2_ren  = rs2_ren_r;
assign rs1_addr = rs1_addr_r;
assign rs2_addr = rs2_addr_r;
assign rd_addr  = rd_addr_r;
assign exu_op   = exu_op_r;
assign alu_ctrl = alu_ctrl_r;
assign wbctl_op = wbctl_op_r;
assign data1    = data1_r;
assign data2    = data2_r;
assign data3    = data3_r;
assign data4    = data4_r;
assign id_ls_ctl = id_ls_ctl_r;
endmodule
