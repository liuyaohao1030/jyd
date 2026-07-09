`timescale 1ns / 1ps
module tb_debug5;
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
        $dumpfile("tb_debug5.vcd");
        $dumpvars(0, tb_debug5);
        wea=0; addra=0; dina=0; web=0; addrb=0; dinb=0;

        // Write to 0x0020
        @(posedge clka); wea=4'hF; addra=16'h0020; dina=32'h12345678;
        @(posedge clka); wea=4'h0;
        @(posedge clka); @(posedge clka); @(posedge clka);

        // Set addrb BEFORE the clkb edge
        addrb = 16'h0020;  // blocking, non-synchronized
        $display("t=%0t Set addrb=0x0020 (before clkb)", $time);
        @(posedge clkb);
        $display("t=%0t clkb+1: addrb=0x%04x doutb=0x%08x", $time, addrb, doutb);
        @(posedge clkb);
        $display("t=%0t clkb+2: addrb=0x%04x doutb=0x%08x", $time, addrb, doutb);

        // Now try synchronized
        addrb = 16'h0010; // dummy
        @(posedge clkb); addrb = 16'h0020; // set ON clkb edge
        $display("t=%0t Set addrb=0x0020 ON clkb edge", $time);
        @(posedge clkb);
        $display("t=%0t clkb+1: addrb=0x%04x doutb=0x%08x", $time, addrb, doutb);

        #100; $finish;
    end
endmodule
