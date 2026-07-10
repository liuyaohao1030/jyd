`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: dram_driver
// Description: DRAM driver with True Dual Port BRAM + Store Buffer
//
//   Port A: Write path - registered (WEA/addr/data), breaks critical path
//   Port B: Read path  - combinational address, 1-cycle registered output
//
//   Write latency: 1 cycle (register) + 1 cycle (BRAM) = 2 cycles total
//   Read latency:  1 cycle (BRAM registered output)
//
//   Store buffer: 1-entry, holds pending write for 2 cycles.
//   When a load address matches the pending store, data is forwarded
//   from the buffer instead of reading stale BRAM output.
//
//   The forwarding decision (fwd_r) is REGISTERED to align with the
//   BRAM's registered output. At the output stage, the registered
//   forwarding decision selects between:
//   - bram_din_r (store buffer) for bytes that were stored
//   - bram_dout (BRAM output) for bytes that were NOT stored
//
//   Since bram_dout at the output stage has already read the correct
//   address (the load address matched the store address), the byte-level
//   mixing produces correct results.
//////////////////////////////////////////////////////////////////////////////////

module dram_driver(
    input  logic         clk            ,
    input  logic [17:0]  perip_addr     ,
    input  logic [31:0]  perip_wdata    ,
    input  logic [3:0]   perip_be       ,
    input  logic         dram_wen       ,
    output logic [31:0]  perip_rdata
);

    // ================================================================
    // Write register bank: register write signals for 1 cycle
    // to break the critical path from EX stage to BRAM WEA.
    // Registers HOLD their values when dram_wen=0 so the store buffer
    // can use them for forwarding.
    // ================================================================
    logic [15:0] bram_addr_r;
    logic [ 3:0] bram_we_r;
    logic [31:0] bram_din_r;

    always @(posedge clk) begin
        if (dram_wen) begin
            bram_addr_r <= perip_addr[17:2];
            bram_we_r   <= perip_be;
            bram_din_r  <= perip_wdata;
        end
        // When dram_wen=0, registers HOLD their values so the
        // store-to-load forwarding can use them while buf_valid_sr != 0.
    end

    // ================================================================
    // Store buffer: track pending write validity
    //   buf_valid_sr = 2'b11 → 2'b01 → 2'b00
    // ================================================================
    logic buf_valid;
    logic [1:0] buf_valid_sr = 2'b00;

    always @(posedge clk) begin
        if (dram_wen)
            buf_valid_sr <= 2'b11;
        else
            buf_valid_sr <= {1'b0, buf_valid_sr[1]};
    end
    assign buf_valid = buf_valid_sr[0];

    // ================================================================
    // Read address: combinational, no extra read latency
    // ================================================================
    logic [15:0] bram_addr_rd;
    assign bram_addr_rd = perip_addr[17:2];

    // ================================================================
    // BRAM write enable: single-cycle pulse via buf_valid_sr[1]
    // ================================================================
    logic [3:0] bram_we_actual;
    assign bram_we_actual = buf_valid_sr[1] ? bram_we_r : 4'b0000;

    // ================================================================
    // True Dual Port BRAM instantiation
    // ================================================================
    logic [31:0] bram_dout;

    DRAM_TDP u_dram_tdp (
        .clka   (clk            ),
        .wea    (bram_we_actual ),
        .addra  (bram_addr_r    ),
        .dina   (bram_din_r     ),
        .douta  (               ),

        .clkb   (clk            ),
        .web    (4'b0000        ),
        .addrb  (bram_addr_rd   ),
        .dinb   (32'b0          ),
        .doutb  (bram_dout      )
    );

    // ================================================================
    // Store-to-load forwarding (REGISTERED decision, CURRENT bram_dout)
    //
    //   The forwarding decision is computed combinationally and then
    //   REGISTERED (fwd_r). At the output stage (1 cycle later):
    //   - fwd_r indicates whether forwarding should be applied
    //   - bram_we_r indicates which bytes were stored
    //   - bram_din_r has the stored data
    //   - bram_dout has the BRAM's output from reading the load address
    //     (which matches the store address when fwd_r=1)
    //
    //   The output MUX selects bram_din_r for stored bytes and
    //   bram_dout for non-stored bytes, producing correct results
    //   for both full-word and partial (byte/halfword) stores.
    // ================================================================
    wire fwd_comb = buf_valid && (bram_addr_rd == bram_addr_r);

    logic fwd_r;
    always @(posedge clk) begin
        fwd_r <= fwd_comb;
    end

    // Output MUX: byte-level forwarding using registered decision
    assign perip_rdata[ 7: 0] = (fwd_r && bram_we_r[0]) ? bram_din_r[ 7: 0] : bram_dout[ 7: 0];
    assign perip_rdata[15: 8] = (fwd_r && bram_we_r[1]) ? bram_din_r[15: 8] : bram_dout[15: 8];
    assign perip_rdata[23:16] = (fwd_r && bram_we_r[2]) ? bram_din_r[23:16] : bram_dout[23:16];
    assign perip_rdata[31:24] = (fwd_r && bram_we_r[3]) ? bram_din_r[31:24] : bram_dout[31:24];

endmodule
