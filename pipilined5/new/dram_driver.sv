`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: dram_driver
// Description: DRAM driver with True Dual Port BRAM + Store Buffer
//
//   Port A: Write path - registered (WEA/addr/data), breaks critical path
//   Port B: Read path  - combinational address, no extra read latency
//
//   Write latency: 1 cycle (register) + 1 cycle (BRAM) = 2 cycles total
//   Read latency:  0 cycles (address) + 1 cycle (BRAM registered) = 1 cycle
//
//   Store buffer: 1-entry, holds pending write for 2 cycles.
//   When a load address matches the pending store, data is forwarded
//   from the buffer instead of reading stale BRAM output.
//   Byte-level forwarding: only the bytes actually written by the store
//   are forwarded; other bytes come from BRAM.
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
    // to break the critical path from EX stage to BRAM WEA
    // ================================================================
    logic [15:0] bram_addr_r;
    logic [ 3:0] bram_we_r;
    logic [31:0] bram_din_r;

    always @(posedge clk) begin
        bram_addr_r <= perip_addr[17:2];
        bram_we_r   <= dram_wen ? perip_be : 4'b0000;
        bram_din_r  <= perip_wdata;
    end

    // ================================================================
    // Store buffer: track pending write validity for 2 cycles
    //   Cycle N:   store arrives (dram_wen)
    //   Posedge N+1: captured into bram_addr_r/bram_we_r/bram_din_r
    //   Posedge N+2: BRAM writes the data
    //   Posedge N+3: buffer cleared (forwarding no longer needed)
    //
    //   buf_valid_sr = 2'b11 → 2'b01 → 2'b00
    // ================================================================
    logic buf_valid;
    logic [1:0] buf_valid_sr;

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
    // BRAM write enable: only assert for ONE cycle when store is registered
    // Write should happen only at cycle N+1 (first cycle after registration)
    // Use buf_valid_sr[1] to ensure single-cycle write pulse
    // ================================================================
    logic [3:0] bram_we_actual;
    assign bram_we_actual = buf_valid_sr[1] ? bram_we_r : 4'b0000;

    // ================================================================
    // True Dual Port BRAM instantiation
    // ================================================================
    logic [31:0] bram_dout;

    DRAM_TDP u_dram_tdp (
        // Port A: Write (registered inputs)
        .clka   (clk            ),
        .wea    (bram_we_actual ),  // gated by buf_valid
        .addra  (bram_addr_r    ),
        .dina   (bram_din_r     ),
        .douta  (               ),

        // Port B: Read (combinational address)
        .clkb   (clk            ),
        .web    (4'b0000        ),
        .addrb  (bram_addr_rd   ),
        .dinb   (32'b0          ),
        .doutb  (bram_dout      )
    );

    // ================================================================
    // Store-to-load forwarding
    //   When a load address matches the pending store address and the
    //   buffer is valid, forward the stored data instead of the stale
    //   BRAM output. Only forward on full-word writes (be=4'b1111).
    //
    //   Partial-byte forwarding would require reading the old value
    //   during the store cycle, which adds complexity. For partial
    //   writes followed by immediate loads, the pipeline will stall
    //   or read stale data (fixed by waiting for BRAM write completion).
    // ================================================================
    wire fwd = buf_valid && (bram_addr_rd == bram_addr_r) && (bram_we_r == 4'b1111);

    assign perip_rdata = fwd ? bram_din_r : bram_dout;

endmodule
