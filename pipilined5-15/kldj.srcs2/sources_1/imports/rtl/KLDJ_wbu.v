`include "define.v"

module KLDJ_wbu(
      input     wire                      wb_ctl
     ,input     wire  [`KLDJ_DATA]        exu_res
     ,output    wire  [`KLDJ_DATA]        wb_data
     ,output    wire                      wb_wen
);

  assign wb_data = exu_res;
  assign wb_wen  = wb_ctl;

endmodule
