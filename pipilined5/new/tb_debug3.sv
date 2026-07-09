`timescale 1ns / 1ps
module tb_debug3;
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
        $dumpfile("tb_debug3.vcd");
        $dumpvars(0, tb_debug3);
        wea=0; addra=0; dina=0; web=0; addrb=0; dinb=0;

        // Write 0x12345678 to 0x0020
        @(posedge clka);
        wea = 4'hF; addra = 16'h0020; dina = 32'h12345678;
        @(posedge clka);
        wea = 4'h0;
        @(posedge clka);
        @(posedge clka);
        @(posedge clka);

        // Simultaneous: write 0x0021 on A, read 0x0020 on B
        @(posedge clka);
        $display("t=%0t clka edge: setting wea and addrb", $time);
        wea = 4'hF; addra = 16'h0021; dina = 32'hFFFFFFFF;
        web = 4'h0; addrb = 16'h0020; dinb = 32'h0;

        @(posedge clka);
        $display("t=%0t clka edge: clearing wea, doutb=0x%08x", $time, doutb);
        wea = 4'h0;

        @(posedge clkb);
        $display("t=%0t clkb edge+1: doutb=0x%08x", $time, doutb);
        @(posedge clkb);
        $display("t=%0t clkb edge+2: doutb=0x%08x", $time, doutb);

        #100; $finish;
    end
endmodule
