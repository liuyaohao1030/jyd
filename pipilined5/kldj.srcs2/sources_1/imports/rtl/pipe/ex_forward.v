`include "../define.v"

module ex_forward #(
     // When enabled, MEM2 carries a registered, already formatted load value.
     // This makes FWD_MEM2 valid for loads and removes the second bubble.
     parameter ENABLE_MEM2_LOAD_FWD = 1'b0
)(
     // from ID/EX pipeline register
     input wire                  id_ex_valid
    ,input wire [`KLDJ_REGADDR]  id_ex_rd_addr
    ,input wire                  id_ex_load_op
    // A load in EX/MEM becomes a MEM2 response on the next edge.
    ,input wire                  ex_mem_valid
    ,input wire [`KLDJ_REGADDR]  ex_mem_rd_addr
    ,input wire                  ex_mem_load_op
    ,input wire [1:0]            id_ex_rs1_fwd_sel
    ,input wire [1:0]            id_ex_rs2_fwd_sel
    ,input wire [`KLDJ_DATA]     id_ex_data1
    ,input wire [`KLDJ_DATA]     id_ex_data2
    ,input wire [`KLDJ_DATA]     id_ex_data3
    ,input wire [`KLDJ_DATA]     id_ex_data4
    // from EX/MEM pipeline register
    ,input wire [`KLDJ_DATA]     ex_mem_exu_res
    // from MEM2 stage.  With ENABLE_MEM2_LOAD_FWD this is a registered,
    // already formatted load result for load producers; otherwise it is the
    // legacy raw EX result and FWD_MEM2 remains non-load-only.
    ,input wire [`KLDJ_DATA]     mem2_forward_data
    // from MEM/WB pipeline register
    ,input wire [`KLDJ_DATA]     mem_wb_wb_data
    // from IF/ID stage
    ,input wire                  if_id_valid
    ,input wire [`KLDJ_REGADDR]  id_reg_rs1_addr
    ,input wire [`KLDJ_REGADDR]  id_reg_rs2_addr
    ,input wire                  id_reg_rs1_ren
    ,input wire                  id_reg_rs2_ren
    // outputs to EXU
    ,output wire [`KLDJ_DATA]    ex_data1
    ,output wire [`KLDJ_DATA]    ex_data2
    ,output wire [`KLDJ_DATA]    ex_data3
    ,output wire [`KLDJ_DATA]    ex_data4
    ,output wire [`KLDJ_DATA]    ex_store_wdata
    // outputs to pipeline control
    ,output wire                 load_use_stall
);

    // First interlock: the traditional immediate load-use hazard.
    wire id_ex_load_use = id_ex_valid && id_ex_load_op &&
                          (id_ex_rd_addr != 5'd0) && if_id_valid &&
                          ((id_reg_rs1_ren && (id_reg_rs1_addr == id_ex_rd_addr)) ||
                           (id_reg_rs2_ren && (id_reg_rs2_addr == id_ex_rd_addr)));

    // Legacy second interlock.  It is retained as an observable raw event for
    // regression, but only blocks the front end when MEM2 cannot yet forward
    // a registered formatted load value.
    wire ex_mem_load_use = ex_mem_valid && ex_mem_load_op &&
                           (ex_mem_rd_addr != 5'd0) && if_id_valid &&
                           ((id_reg_rs1_ren && (id_reg_rs1_addr == ex_mem_rd_addr)) ||
                            (id_reg_rs2_ren && (id_reg_rs2_addr == ex_mem_rd_addr)));

    assign load_use_stall = id_ex_load_use ||
                            (!ENABLE_MEM2_LOAD_FWD && ex_mem_load_use);

    localparam [1:0] FWD_EX_MEM = 2'b01;
    localparam [1:0] FWD_MEM2   = 2'b10;
    localparam [1:0] FWD_MEM_WB = 2'b11;

    // A registered two-bit selector plus four 32-bit inputs maps to one LUT6
    // per result bit.  The old implementation performed three live rd-address
    // comparisons followed by a priority chain in the timing-critical EX cycle.
    function [`KLDJ_DATA] forward_mux;
        input [1:0] sel;
        input [`KLDJ_DATA] base_data;
        input [`KLDJ_DATA] ex_mem_data;
        input [`KLDJ_DATA] mem2_data;
        input [`KLDJ_DATA] mem_wb_data;
        begin
            case (sel)
                FWD_EX_MEM: forward_mux = ex_mem_data;
                FWD_MEM2:   forward_mux = mem2_data;
                FWD_MEM_WB: forward_mux = mem_wb_data;
                default:    forward_mux = base_data;
            endcase
        end
    endfunction

    assign ex_data1 = forward_mux(id_ex_rs1_fwd_sel, id_ex_data1,
                                  ex_mem_exu_res, mem2_forward_data, mem_wb_wb_data);
    // For a store, a non-zero rs2 selector also changes ex_data2, but the AGU
    // uses the dedicated ls_imm input.  ex_store_wdata uses the same selector
    // with id_ex_data3 as its unforwarded store-data source.
    assign ex_data2 = forward_mux(id_ex_rs2_fwd_sel, id_ex_data2,
                                  ex_mem_exu_res, mem2_forward_data, mem_wb_wb_data);
    assign ex_data3 = id_ex_data3;
    assign ex_data4 = id_ex_data4;
    assign ex_store_wdata = forward_mux(id_ex_rs2_fwd_sel, id_ex_data3,
                                        ex_mem_exu_res, mem2_forward_data, mem_wb_wb_data);

endmodule
