`include "../define.v"


module KLDJ_regfile (
     input    wire                               clk
    ,input    wire                               rst

    ,input    wire   [`KLDJ_REGADDR]             waddr
    ,input    wire   [`KLDJ_REG]                 wdata
    ,input    wire                               wen

    ,input    wire   [`KLDJ_REGADDR]             raddr1
    ,output   wire   [`KLDJ_REG]                 rdata1
    ,input    wire                               ren1

    ,input    wire   [`KLDJ_REGADDR]             raddr2
    ,output   wire   [`KLDJ_REG]                 rdata2
    ,input    wire                               ren2

);

    reg  [`KLDJ_REG] regs [0:31];

 always@(posedge clk) begin
     if(rst == `KLDJ_RSTABLE) begin
         regs[0]  <= `KLDJ_ZERO32;
         regs[1]  <= `KLDJ_ZERO32;
         regs[2]  <= `KLDJ_ZERO32;
         regs[3]  <= `KLDJ_ZERO32;
         regs[4]  <= `KLDJ_ZERO32;
         regs[5]  <= `KLDJ_ZERO32;
         regs[6]  <= `KLDJ_ZERO32;
         regs[7]  <= `KLDJ_ZERO32;
         regs[8]  <= `KLDJ_ZERO32;
         regs[9]  <= `KLDJ_ZERO32;
         regs[10] <= `KLDJ_ZERO32;
         regs[11] <= `KLDJ_ZERO32;
         regs[12] <= `KLDJ_ZERO32;
         regs[13] <= `KLDJ_ZERO32;
         regs[14] <= `KLDJ_ZERO32;
         regs[15] <= `KLDJ_ZERO32;
         regs[16] <= `KLDJ_ZERO32;
         regs[17] <= `KLDJ_ZERO32;
         regs[18] <= `KLDJ_ZERO32;
         regs[19] <= `KLDJ_ZERO32;
         regs[20] <= `KLDJ_ZERO32;
         regs[21] <= `KLDJ_ZERO32;
         regs[22] <= `KLDJ_ZERO32;
         regs[23] <= `KLDJ_ZERO32;
         regs[24] <= `KLDJ_ZERO32;
         regs[25] <= `KLDJ_ZERO32;
         regs[26] <= `KLDJ_ZERO32;
         regs[27] <= `KLDJ_ZERO32;
         regs[28] <= `KLDJ_ZERO32;
         regs[29] <= `KLDJ_ZERO32;
         regs[30] <= `KLDJ_ZERO32;
         regs[31] <= `KLDJ_ZERO32;
     end
   else begin
         if(wen == `KLDJ_WENABLE && waddr != 5'd0)begin
             regs[waddr]<=wdata;
         end
     end
 end

 wire write_valid = (wen == `KLDJ_WENABLE) && (waddr != 5'd0);
 wire read1_valid = (rst != `KLDJ_RSTABLE) && (ren1 == `KLDJ_RENABLE);
 wire read2_valid = (rst != `KLDJ_RSTABLE) && (ren2 == `KLDJ_RENABLE);

 assign rdata1 = read1_valid ? ((write_valid && (waddr == raddr1)) ? wdata : regs[raddr1]) : `KLDJ_ZERO32;
 assign rdata2 = read2_valid ? ((write_valid && (waddr == raddr2)) ? wdata : regs[raddr2]) : `KLDJ_ZERO32;

 endmodule
