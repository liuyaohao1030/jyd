`include "define.v"

module KLDJ_csr(
     input  wire                  clk
    ,input  wire                  rst

    ,input  wire [11:0]           raddr
    ,output reg  [`KLDJ_DATA]     rdata

    ,input  wire                  wen
    ,input  wire [11:0]           waddr
    ,input  wire [`KLDJ_DATA]     wdata

    ,input  wire                  trap_enter
    ,input  wire [`KLDJ_PC]       trap_pc
    ,input  wire [`KLDJ_DATA]     trap_cause
    ,input  wire                  mret_enter

    ,output wire [`KLDJ_DATA]     mstatus_o
    ,output wire [`KLDJ_DATA]     mtvec_o
    ,output wire [`KLDJ_DATA]     mscratch_o
    ,output wire [`KLDJ_DATA]     mepc_o
    ,output wire [`KLDJ_DATA]     mcause_o
);

    reg [`KLDJ_DATA] mstatus;
    reg [`KLDJ_DATA] mtvec;
    reg [`KLDJ_DATA] mscratch;
    reg [`KLDJ_DATA] mepc;
    reg [`KLDJ_DATA] mcause;

    always @(*) begin
        case (raddr)
            `KLDJ_CSR_MSTATUS:  rdata = mstatus;
            `KLDJ_CSR_MTVEC:    rdata = mtvec;
            `KLDJ_CSR_MSCRATCH: rdata = mscratch;
            `KLDJ_CSR_MEPC:     rdata = mepc;
            `KLDJ_CSR_MCAUSE:   rdata = mcause;
            default:            rdata = `KLDJ_ZERO32;
        endcase
    end

    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            mstatus  <= `KLDJ_ZERO32;
            mtvec    <= `KLDJ_ZERO32;
            mscratch <= `KLDJ_ZERO32;
            mepc     <= `KLDJ_ZERO32;
            mcause   <= `KLDJ_ZERO32;
        end else if (trap_enter) begin
            mepc       <= trap_pc;
            mcause     <= trap_cause;
            mstatus[7] <= mstatus[3];
            mstatus[3] <= 1'b0;
        end else if (mret_enter) begin
            mstatus[3] <= mstatus[7];
            mstatus[7] <= 1'b1;
        end else if (wen) begin
            case (waddr)
                `KLDJ_CSR_MSTATUS:  mstatus  <= wdata;
                `KLDJ_CSR_MTVEC:    mtvec    <= wdata;
                `KLDJ_CSR_MSCRATCH: mscratch <= wdata;
                `KLDJ_CSR_MEPC:     mepc     <= wdata;
                `KLDJ_CSR_MCAUSE:   mcause   <= wdata;
                default: begin
                end
            endcase
        end
    end

    assign mstatus_o  = mstatus;
    assign mtvec_o    = mtvec;
    assign mscratch_o = mscratch;
    assign mepc_o     = mepc;
    assign mcause_o   = mcause;

endmodule
