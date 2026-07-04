`include "../define.v"

module KLDJ_csr(
     input  wire        clk
    ,input  wire        rst
    ,input  wire [11:0] csr_raddr
    ,output wire [31:0] csr_rdata
    ,input  wire        csr_we
    ,input  wire [11:0] csr_waddr
    ,input  wire [31:0] csr_wdata
    ,input  wire        ecall_en
    ,input  wire [31:0] ecall_pc
    ,input  wire        mret_en
    ,output wire [31:0] mret_pc
    ,output wire [31:0] mtvec_val
);

    reg [31:0] mstatus;  // 0x300
    reg [31:0] mepc;     // 0x341
    reg [31:0] mtvec;    // 0x305
    reg [31:0] mcause;   // 0x342
    reg [31:0] mscratch; // 0x340

    assign mret_pc = mepc;
    assign mtvec_val = mtvec;

    // Per-register write-enable and next-value signals for priority handling
    wire [31:0] mstatus_next;
    wire        mstatus_we;
    wire [31:0] mepc_next;
    wire        mepc_we;
    wire [31:0] mcause_next;
    wire        mcause_we;
    wire [31:0] mtvec_next;
    wire        mtvec_we;
    wire [31:0] mscratch_next;
    wire        mscratch_we;

    // ecall: MPIE=MIE, MIE=0, MPP=2'b11 (M-mode)
    assign mstatus_we   = ecall_en | mret_en | (csr_we && csr_waddr == `CSR_MSTATUS);
    assign mstatus_next = ecall_en ? {mstatus[31:13], 2'b11, mstatus[10:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]} :
                          mret_en  ? {mstatus[31:13], 2'b00, mstatus[10:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]} :
                                     csr_wdata;

    assign mepc_we   = ecall_en | (csr_we && csr_waddr == `CSR_MEPC);
    assign mepc_next = ecall_en ? ecall_pc : csr_wdata;

    assign mcause_we   = ecall_en | (csr_we && csr_waddr == `CSR_MCAUSE);
    assign mcause_next = ecall_en ? 32'h0000_000B : csr_wdata;

    assign mtvec_we   = csr_we && csr_waddr == `CSR_MTVEC;
    assign mtvec_next = csr_wdata;

    assign mscratch_we   = csr_we && csr_waddr == `CSR_MSCRATCH;
    assign mscratch_next = csr_wdata;

    // CSR read: return current register value (no forwarding needed)
    // CSR write takes effect on next clock edge; read is combinational,
    // so a same-cycle read naturally returns the OLD value — which is
    // exactly the CSRRW/CSRRS/CSRRC semantic.
    assign csr_rdata = (csr_raddr == `CSR_MSTATUS)  ? mstatus  :
                       (csr_raddr == `CSR_MTVEC)    ? mtvec    :
                       (csr_raddr == `CSR_MEPC)     ? mepc     :
                       (csr_raddr == `CSR_MCAUSE)   ? mcause   :
                       (csr_raddr == `CSR_MSCRATCH) ? mscratch :
                       32'b0;

    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            mstatus  <= 32'h0000_1800;
            mepc     <= 32'b0;
            mtvec    <= 32'b0;
            mcause   <= 32'b0;
            mscratch <= 32'b0;
        end else begin
            if (mstatus_we)   mstatus  <= mstatus_next;
            if (mepc_we)      mepc     <= mepc_next;
            if (mcause_we)    mcause   <= mcause_next;
            if (mtvec_we)     mtvec    <= mtvec_next;
            if (mscratch_we)  mscratch <= mscratch_next;
        end
    end

endmodule
