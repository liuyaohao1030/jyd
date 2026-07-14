`include "../define.v"

module KLDJ_lsu(
     input  wire [3:0]          ls_ctl
    ,input  wire [1:0]          addr_low
    ,input  wire [`KLDJ_DATA]   mem_rdata
    ,output wire [`KLDJ_DATA]   lsu_res
);

    // MEM2 only formats the raw, registered memory response.  Request
    // generation and store alignment are handled in EX by ex_mem_req_ctrl.
    // ls_ctl[1:0]: 00=byte, 01=half, 10=word; ls_ctl[2]: signed load.
    wire [1:0] size        = ls_ctl[1:0];
    wire       signed_load = ls_ctl[2];

    // Explicit small muxes synthesize more predictably than two variable
    // barrel shifts on the memory-return timing path.
    wire [7:0] loaded_byte = (addr_low == 2'b00) ? mem_rdata[ 7: 0] :
                             (addr_low == 2'b01) ? mem_rdata[15: 8] :
                             (addr_low == 2'b10) ? mem_rdata[23:16] :
                                                   mem_rdata[31:24];
    wire [15:0] loaded_half = addr_low[1] ? mem_rdata[31:16] :
                                                        mem_rdata[15:0];

    assign lsu_res = (size == 2'b00) ?
                         {{24{signed_load & loaded_byte[7]}}, loaded_byte} :
                     (size == 2'b01) ?
                         {{16{signed_load & loaded_half[15]}}, loaded_half} :
                         mem_rdata;

endmodule
