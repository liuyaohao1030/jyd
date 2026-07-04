`include "../define.v"

module KLDJ_csr(
     input  wire        clk
    ,input  wire        rst
    // CSR 读接口 (EX 阶段)
    ,input  wire [11:0] csr_raddr
    ,output wire [31:0] csr_rdata
    // CSR 写接口 (EX 阶段)
    ,input  wire        csr_we
    ,input  wire [11:0] csr_waddr
    ,input  wire [31:0] csr_wdata
    // ecall 接口
    ,input  wire        ecall_en
    ,input  wire [31:0] ecall_pc
    // mret 接口
    ,input  wire        mret_en
    ,output wire [31:0] mret_pc
    // mtvec output for ecall jump target
    ,output wire [31:0] mtvec_val
);

    // CSR 寄存器
    reg [31:0] mstatus;  // 0x300
    reg [31:0] mepc;     // 0x341
    reg [31:0] mtvec;    // 0x305
    reg [31:0] mcause;   // 0x342

    // MRET 返回地址
    assign mret_pc = mepc;

    // mtvec output for ecall jump target
    assign mtvec_val = mtvec;

    // CSR 读逻辑 (组合逻辑)
    assign csr_rdata = (csr_raddr == `CSR_MSTATUS) ? mstatus :
                       (csr_raddr == `CSR_MTVEC)   ? mtvec :
                       (csr_raddr == `CSR_MEPC)    ? mepc :
                       (csr_raddr == `CSR_MCAUSE)  ? mcause :
                       32'b0;

    // CSR 写逻辑 (时序逻辑)
    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            // 复位值: MPP=M (bits 12:11=11), 其他位为0
            mstatus <= 32'h0000_1800;
            mepc    <= 32'b0;
            mtvec   <= 32'b0;
            mcause  <= 32'b0;
        end else begin
            // ecall 处理 (优先级最高)
            if (ecall_en) begin
                mepc   <= ecall_pc;            // 保存触发 ecall 的指令地址
                mcause <= 32'h0000_000B;       // Environment call from M-mode
                // mstatus: MPIE = MIE, MIE = 0
                mstatus[7] <= mstatus[3];      // MPIE = MIE
                mstatus[3] <= 1'b0;            // MIE = 0
            end
            // mret 处理
            else if (mret_en) begin
                // mstatus: MIE = MPIE, MPIE = 1
                mstatus[3] <= mstatus[7];      // MIE = MPIE
                mstatus[7] <= 1'b1;            // MPIE = 1
            end
            // CSR 指令写入
            else if (csr_we) begin
                case (csr_waddr)
                    `CSR_MSTATUS: mstatus <= csr_wdata;
                    `CSR_MTVEC:   mtvec   <= csr_wdata;
                    `CSR_MEPC:    mepc    <= csr_wdata;
                    `CSR_MCAUSE:  mcause  <= csr_wdata;
                    default: ;  // 忽略未实现的 CSR
                endcase
            end
        end
    end

endmodule
