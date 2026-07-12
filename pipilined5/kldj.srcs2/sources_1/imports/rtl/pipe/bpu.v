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
    ,output wire                  btb_hit
    ,output wire [INDEX_WIDTH-1:0] lookup_pht_idx

    // EX stage update
    ,input  wire                  update_valid
    ,input  wire [`KLDJ_PC]       update_pc
    ,input  wire [INDEX_WIDTH-1:0] update_pht_idx
    ,input  wire                  update_taken
);

    gshare_btb_core #(
         .INDEX_WIDTH     (INDEX_WIDTH     )
        ,.BHT_RESET_VALUE (BHT_RESET_VALUE )
    ) u_gshare_btb_core(
         .clk            (clk            )
        ,.rst            (rst            )
        ,.lookup_pc      (lookup_pc      )
        ,.pred_taken     (pred_taken     )
        ,.btb_hit        (btb_hit        )
        ,.lookup_pht_idx (lookup_pht_idx )
        ,.update_valid   (update_valid   )
        ,.update_pc      (update_pc      )
        ,.update_pht_idx (update_pht_idx )
        ,.update_taken   (update_taken   )
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
    ,output wire                  btb_hit
    ,output wire [INDEX_WIDTH-1:0] lookup_pht_idx

    // EX stage update
    ,input  wire                  update_valid
    ,input  wire [`KLDJ_PC]       update_pc
    ,input  wire [INDEX_WIDTH-1:0] update_pht_idx
    ,input  wire                  update_taken
);

    localparam ENTRY_NUM = (1 << INDEX_WIDTH);
    localparam TAG_WIDTH = 32 - INDEX_WIDTH - 2;

    reg [INDEX_WIDTH-1:0] ghr;

    // The data arrays intentionally have no reset. Keeping resettable validity
    // bits separate allows Vivado to infer asynchronous-read distributed RAM.
    (* ram_style = "distributed" *) reg [1:0] pht [0:ENTRY_NUM-1];
    (* ram_style = "distributed" *) reg [TAG_WIDTH-1:0] btb_tag [0:ENTRY_NUM-1];
    reg [ENTRY_NUM-1:0] pht_valid;
    reg [ENTRY_NUM-1:0] btb_valid;

    wire [INDEX_WIDTH-1:0] lookup_btb_idx;
    wire [TAG_WIDTH-1:0]   lookup_tag;
    wire [INDEX_WIDTH-1:0] update_btb_idx;
    wire [TAG_WIDTH-1:0]   update_tag;
    wire [1:0]             lookup_pht_value;
    wire [1:0]             update_pht_value;
    wire [1:0]             update_pht_next;
    wire [TAG_WIDTH-1:0]   lookup_btb_tag;

    assign lookup_btb_idx = lookup_pc[INDEX_WIDTH+1:2];
    assign lookup_pht_idx = lookup_btb_idx ^ ghr;
    assign lookup_tag     = lookup_pc[31:INDEX_WIDTH+2];
    assign update_btb_idx = update_pc[INDEX_WIDTH+1:2];
    assign update_tag     = update_pc[31:INDEX_WIDTH+2];

    assign lookup_pht_value = pht_valid[lookup_pht_idx] ?
                              pht[lookup_pht_idx] : BHT_RESET_VALUE;
    assign update_pht_value = pht_valid[update_pht_idx] ?
                              pht[update_pht_idx] : BHT_RESET_VALUE;
    assign update_pht_next  = update_taken ?
                              ((update_pht_value == 2'b11) ? 2'b11 : update_pht_value + 2'b01) :
                              ((update_pht_value == 2'b00) ? 2'b00 : update_pht_value - 2'b01);

    assign lookup_btb_tag = btb_tag[lookup_btb_idx];

    assign btb_hit     = btb_valid[lookup_btb_idx] && (lookup_btb_tag == lookup_tag);
    assign pred_taken  = btb_hit && lookup_pht_value[1];

    always @(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            ghr       <= {INDEX_WIDTH{1'b0}};
            pht_valid <= {ENTRY_NUM{1'b0}};
            btb_valid <= {ENTRY_NUM{1'b0}};
        end else if(update_valid) begin
            pht[update_pht_idx]       <= update_pht_next;
            pht_valid[update_pht_idx] <= 1'b1;

            if(update_taken) begin
                btb_valid[update_btb_idx] <= 1'b1;
                btb_tag[update_btb_idx]   <= update_tag;
            end

            ghr <= {ghr[INDEX_WIDTH-2:0], update_taken};
        end
    end

endmodule
