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

    localparam ENTRY_NUM = (1 << INDEX_WIDTH);
    localparam TAG_WIDTH = 32 - INDEX_WIDTH - 2;

    reg [INDEX_WIDTH-1:0] ghr;
    reg [1:0]             pht        [0:ENTRY_NUM-1];
    reg                   btb_valid  [0:ENTRY_NUM-1];
    reg [TAG_WIDTH-1:0]   btb_tag    [0:ENTRY_NUM-1];
    reg [`KLDJ_PC]        btb_target [0:ENTRY_NUM-1];

    wire [INDEX_WIDTH-1:0] lookup_btb_idx;
    wire [TAG_WIDTH-1:0]   lookup_tag;
    wire [INDEX_WIDTH-1:0] update_btb_idx;
    wire [TAG_WIDTH-1:0]   update_tag;

    integer i;

    assign lookup_btb_idx = lookup_pc[INDEX_WIDTH+1:2];
    assign lookup_pht_idx = lookup_btb_idx ^ ghr;
    assign lookup_tag     = lookup_pc[31:INDEX_WIDTH+2];
    assign update_btb_idx = update_pc[INDEX_WIDTH+1:2];
    assign update_tag     = update_pc[31:INDEX_WIDTH+2];

    assign btb_hit     = btb_valid[lookup_btb_idx] && (btb_tag[lookup_btb_idx] == lookup_tag);
    assign pred_taken  = btb_hit && pht[lookup_pht_idx][1];
    assign pred_target = btb_target[lookup_btb_idx];

    always @(posedge clk) begin
        if(rst == `KLDJ_RSTABLE) begin
            ghr <= {INDEX_WIDTH{1'b0}};
            for(i = 0; i < ENTRY_NUM; i = i + 1) begin
                pht[i]        <= BHT_RESET_VALUE;
                btb_valid[i]  <= 1'b0;
                btb_tag[i]    <= {TAG_WIDTH{1'b0}};
                btb_target[i] <= `KLDJ_ZERO32;
            end
        end else if(update_valid) begin
            if(update_taken) begin
                if(pht[update_pht_idx] != 2'b11) begin
                    pht[update_pht_idx] <= pht[update_pht_idx] + 2'b01;
                end
                btb_valid[update_btb_idx]  <= 1'b1;
                btb_tag[update_btb_idx]    <= update_tag;
                btb_target[update_btb_idx] <= update_target;
            end else begin
                if(pht[update_pht_idx] != 2'b00) begin
                    pht[update_pht_idx] <= pht[update_pht_idx] - 2'b01;
                end
            end
            ghr <= {ghr[INDEX_WIDTH-2:0], update_taken};
        end
    end

endmodule
