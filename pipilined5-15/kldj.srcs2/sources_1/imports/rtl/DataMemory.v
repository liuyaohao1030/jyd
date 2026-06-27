`include "define.v"

module DataMemory(
    input wire                  clk,
    input wire                  mem_read,
    input wire                  mem_write,
    input wire [`KLDJ_DATA]    addr,
    input wire [`KLDJ_DATA]    wdata,
    input wire [3:0]           mem_be,      // Byte enable mask (one-hot per byte)
    output reg [`KLDJ_DATA]    rdata
);

    // 4KB memory: 1024 x 32-bit words
    reg [31:0] mem [0:1023];

    // Address decoding
    wire [9:0] word_addr = addr[11:2];

    // Write operation (synchronous)
    always @(posedge clk) begin
        if (mem_write) begin
            if (mem_be[0]) mem[word_addr][7:0]   <= wdata[7:0];
            if (mem_be[1]) mem[word_addr][15:8]  <= wdata[15:8];
            if (mem_be[2]) mem[word_addr][23:16] <= wdata[23:16];
            if (mem_be[3]) mem[word_addr][31:24] <= wdata[31:24];
        end
    end

    // Read operation (combinational, asynchronous)
    always @(*) begin
        if (mem_read) begin
            rdata = mem[word_addr];
        end else begin
            rdata = 32'b0;
        end
    end

endmodule