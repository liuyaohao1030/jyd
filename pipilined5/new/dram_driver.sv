module dram_driver(
    input  logic         clk            ,
    input  logic [17:0]  perip_addr     ,
    input  logic [31:0]  perip_wdata    ,
    input  logic [3:0]   perip_be       ,
    input  logic         dram_wen       ,
    output logic [31:0]  perip_rdata
);
    // store buffer - only update on dram_wen (hold when idle)
    logic [15:0] bram_addr_r;
    logic [ 3:0] bram_we_r;
    logic [31:0] bram_din_r;

    always @(posedge clk) begin
        if (dram_wen) begin
            bram_addr_r <= perip_addr[17:2];
            bram_we_r   <= perip_be;
            bram_din_r  <= perip_wdata;
        end
    end

    // buf_valid_sr: 2'b11 -> 2'b01 -> 2'b00
    //   [1]: next cycle BRAM write (raw dram_wen)
    //   [0]: current cycle forwarding (1 cycle after dram_wen)
    logic [1:0] buf_valid_sr = 2'b00;
    always @(posedge clk) begin
        if (dram_wen)
            buf_valid_sr <= 2'b11;
        else
            buf_valid_sr <= {1'b0, buf_valid_sr[1]};
    end

    // Port B read address (combinational, directly from CPU)
    logic [15:0] bram_addr_rd;
    assign bram_addr_rd = perip_addr[17:2];

    // Port A write enable: delayed by 1 cycle via buf_valid_sr[1]
    logic [3:0] bram_we_actual;
    assign bram_we_actual = buf_valid_sr[1] ? bram_we_r : 4'b0000;

    // BRAM
    logic [31:0] bram_dout;
    DRAM_TDP u_dram_tdp (
        .clka  (clk           ),
        .wea   (bram_we_actual),
        .addra (bram_addr_r   ),
        .dina  (bram_din_r    ),
        .douta (              ),
        .clkb  (clk           ),
        .web   (4'b0000       ),
        .addrb (bram_addr_rd  ),
        .dinb  (32'b0         ),
        .doutb (bram_dout     )
    );

    // combinational forwarding: valid 1 cycle after store, compare current read addr with stored write addr
    wire fwd = buf_valid_sr[0] && (bram_addr_rd == bram_addr_r);

    // output mux: forwarding uses held bram_din_r for matched bytes
    assign perip_rdata[ 7: 0] = (fwd && bram_we_r[0]) ? bram_din_r[ 7: 0] : bram_dout[ 7: 0];
    assign perip_rdata[15: 8] = (fwd && bram_we_r[1]) ? bram_din_r[15: 8] : bram_dout[15: 8];
    assign perip_rdata[23:16] = (fwd && bram_we_r[2]) ? bram_din_r[23:16] : bram_dout[23:16];
    assign perip_rdata[31:24] = (fwd && bram_we_r[3]) ? bram_din_r[31:24] : bram_dout[31:24];

endmodule
