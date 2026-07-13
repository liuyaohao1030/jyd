`include "../define.v"

module bpu #(
     parameter INDEX_WIDTH     = 6
    ,parameter BHT_RESET_VALUE = 2'b01
)(
     input  wire                  clk
    ,input  wire                  rst

    // IF stage lookup
    ,input  wire [`KLDJ_PC]       lookup_pc
    ,output wire                  pred_taken
    ,output wire [`KLDJ_PC]       pred_target
    ,output wire                  btb_hit
    ,output wire [INDEX_WIDTH-1:0] lookup_pht_idx

    // EX stage update
    ,input  wire                  update_valid
    ,input  wire [`KLDJ_PC]       update_pc
    ,input  wire [INDEX_WIDTH-1:0] update_pht_idx
    ,input  wire                  update_taken
    ,input  wire [`KLDJ_PC]       update_target
);

    gshare_btb_core #(
         .INDEX_WIDTH     (INDEX_WIDTH     )
        ,.BHT_RESET_VALUE (BHT_RESET_VALUE )
    ) u_gshare_btb_core(
         .clk            (clk            )
        ,.rst            (rst            )
        ,.lookup_pc      (lookup_pc      )
        ,.pred_taken     (pred_taken     )
        ,.pred_target    (pred_target    )
        ,.btb_hit        (btb_hit        )
        ,.lookup_pht_idx (lookup_pht_idx )
        ,.update_valid   (update_valid   )
        ,.update_pc      (update_pc      )
        ,.update_pht_idx (update_pht_idx )
        ,.update_taken   (update_taken   )
        ,.update_target  (update_target  )
    );

endmodule

module gshare_btb_core #(
     parameter INDEX_WIDTH     = 6
    ,parameter BHT_RESET_VALUE = 2'b01
)(
     input  wire                  clk
    ,input  wire                  rst

    // IF stage lookup
    ,input  wire [`KLDJ_PC]       lookup_pc
    ,output wire                  pred_taken
    ,output wire [`KLDJ_PC]       pred_target
    ,output wire                  btb_hit
    ,output wire [INDEX_WIDTH-1:0] lookup_pht_idx

    // EX stage update
    ,input  wire                  update_valid
    ,input  wire [`KLDJ_PC]       update_pc
    ,input  wire [INDEX_WIDTH-1:0] update_pht_idx
    ,input  wire                  update_taken
    ,input  wire [`KLDJ_PC]       update_target
);

    localparam ENTRY_NUM      = (1 << INDEX_WIDTH);
    localparam TAG_WIDTH      = 32 - INDEX_WIDTH - 2;
    localparam BTB_DATA_WIDTH = TAG_WIDTH + 32;

    reg [INDEX_WIDTH-1:0] ghr;

    // Keep GHR resolution timing unchanged, but pipeline table writes by one
    // cycle so the EX result does not directly drive the distributed RAM ports.
    reg                         update_valid_q;
    reg [`KLDJ_PC]              update_pc_q;
    reg [INDEX_WIDTH-1:0]       update_pht_idx_q;
    reg                         update_taken_q;
    reg [`KLDJ_PC]              update_target_q;

    // The data arrays intentionally have no reset. Keeping resettable validity
    // bits separate allows Vivado to infer asynchronous-read distributed RAM.
    (* ram_style = "distributed" *) reg [1:0] pht [0:ENTRY_NUM-1];
    (* ram_style = "distributed" *) reg [BTB_DATA_WIDTH-1:0] btb_data [0:ENTRY_NUM-1];
    reg [ENTRY_NUM-1:0] pht_valid;
    reg [ENTRY_NUM-1:0] btb_valid;

    wire [INDEX_WIDTH-1:0] lookup_btb_idx;
    wire [TAG_WIDTH-1:0]   lookup_tag;
    wire [INDEX_WIDTH-1:0] update_btb_idx;
    wire [TAG_WIDTH-1:0]   update_tag;
    wire [1:0]             lookup_pht_value;
    wire [1:0]             update_pht_value;
    wire [1:0]             update_pht_next;
    wire [BTB_DATA_WIDTH-1:0] lookup_btb_data;
    wire [TAG_WIDTH-1:0]   lookup_btb_tag;
    wire [`KLDJ_PC]        lookup_btb_target;

    assign lookup_btb_idx = lookup_pc[INDEX_WIDTH+1:2];
    assign lookup_pht_idx = lookup_btb_idx ^ ghr;
    assign lookup_tag     = lookup_pc[31:INDEX_WIDTH+2];
    assign update_btb_idx = update_pc_q[INDEX_WIDTH+1:2];
    assign update_tag     = update_pc_q[31:INDEX_WIDTH+2];

    assign lookup_pht_value = pht_valid[lookup_pht_idx] ?
                              pht[lookup_pht_idx] : BHT_RESET_VALUE;
    assign update_pht_value = pht_valid[update_pht_idx_q] ?
                              pht[update_pht_idx_q] : BHT_RESET_VALUE;
    assign update_pht_next  = update_taken_q ?
                              ((update_pht_value == 2'b11) ? 2'b11 : update_pht_value + 2'b01) :
                              ((update_pht_value == 2'b00) ? 2'b00 : update_pht_value - 2'b01);

    assign lookup_btb_data   = btb_data[lookup_btb_idx];
    assign lookup_btb_tag    = lookup_btb_data[BTB_DATA_WIDTH-1:32];
    assign lookup_btb_target = lookup_btb_data[31:0];

    assign btb_hit     = btb_valid[lookup_btb_idx] && (lookup_btb_tag == lookup_tag);
    assign pred_taken  = btb_hit && lookup_pht_value[1];
    assign pred_target = lookup_btb_target;

    always @(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            ghr       <= {INDEX_WIDTH{1'b0}};
            pht_valid <= {ENTRY_NUM{1'b0}};
            btb_valid <= {ENTRY_NUM{1'b0}};
            update_valid_q <= 1'b0;
        end else begin
            update_valid_q <= update_valid;
            if(update_valid) begin
                update_pc_q      <= update_pc;
                update_pht_idx_q <= update_pht_idx;
                update_taken_q   <= update_taken;
                update_target_q  <= update_target;

                ghr <= {ghr[INDEX_WIDTH-2:0], update_taken};
            end

            if(update_valid_q) begin
                pht[update_pht_idx_q]       <= update_pht_next;
                pht_valid[update_pht_idx_q] <= 1'b1;

                if(update_taken_q) begin
                    btb_valid[update_btb_idx] <= 1'b1;
                    btb_data[update_btb_idx]  <= {update_tag, update_target_q};
                end
            end
        end
    end

endmodule
