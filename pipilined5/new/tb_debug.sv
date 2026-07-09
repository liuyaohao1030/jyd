`timescale 1ns / 1ps
module tb_debug;
    reg clka, clkb;
    initial clka = 0;
    always #5 clka = ~clka;
    initial clkb = 0;
    always #7 clkb = ~clkb;

    reg [3:0] wea; reg [15:0] addra; reg [31:0] dina; wire [31:0] douta;
    reg [3:0] web; reg [15:0] addrb; reg [31:0] dinb; wire [31:0] doutb;

    DRAM_TDP u_dut (
        .clka(clka), .wea(wea), .addra(addra), .dina(dina), .douta(douta),
        .clkb(clkb), .web(web), .addrb(addrb), .dinb(dinb), .doutb(doutb)
    );

    initial begin
        $dumpfile("tb_debug.vcd");
        $dumpvars(0, tb_debug);
        wea=0; addra=0; dina=0; web=0; addrb=0; dinb=0;

        // Write 0x12345678 to 0x0020
        @(posedge clka); wea=4'hF; addra=16'h0020; dina=32'h12345678;
        @(posedge clka); wea=4'h0;
        // Wait
        @(posedge clka);
        @(posedge clka);
        // Simultaneous: read 0x0020 on B, write 0x0021 on A
        @(posedge clka);
        wea=4'hF; addra=16'h0021; dina=32'hFFFFFFFF;
        web=4'h0; addrb=16'h0020; dinb=32'h0;
        @(posedge clka); wea=4'h0;
        @(posedge clkb); @(posedge clkb);
        $display("doutb = 0x%08x (expected 0x12345678)", doutb);
        #100; $finish;
    end
endmodule
