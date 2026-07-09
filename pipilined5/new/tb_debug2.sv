`timescale 1ns / 1ps
module tb_debug2;
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
        $dumpfile("tb_debug2.vcd");
        $dumpvars(0, tb_debug2);
        wea=0; addra=0; dina=0; web=0; addrb=0; dinb=0;

        // Write 0x12345678 to 0x0020 using port_a_write-like sequence
        @(posedge clka);
        wea = 4'hF; addra = 16'h0020; dina = 32'h12345678;
        @(posedge clka);
        wea = 4'h0;
        @(posedge clka);
        @(posedge clka);
        @(posedge clka);
        // Now try reading 0x0020 via Port B
        @(posedge clkb);
        web = 4'h0; addrb = 16'h0020; dinb = 32'h0;
        $display("t=%0t After setting addrb=0x0020, doutb=0x%08x", $time, doutb);
        @(posedge clkb);
        $display("t=%0t After 1 clkb, doutb=0x%08x", $time, doutb);
        @(posedge clkb);
        $display("t=%0t After 2 clkb, doutb=0x%08x", $time, doutb);

        // Check memory content directly
        $display("mem[0x0020] = 0x%08x", u_dut.mem[16'h0020]);

        #100; $finish;
    end
endmodule
