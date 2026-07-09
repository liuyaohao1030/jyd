`timescale 1ns / 1ps
module tb_debug6;
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

    task port_a_write;
        input [15:0] addr; input [31:0] data; input [3:0] be;
        begin
            @(posedge clka); wea = be; addra = addr; dina = data;
            @(posedge clka); wea = 4'b0;
        end
    endtask

    task port_b_read;
        input [15:0] addr;
        begin
            @(posedge clkb); web = 4'b0; addrb = addr; dinb = 32'h0;
            @(posedge clkb);
        end
    endtask

    initial begin
        $dumpfile("tb_debug6.vcd");
        $dumpvars(0, tb_debug6);
        wea=0; addra=0; dina=0; web=0; addrb=0; dinb=0;

        // Test 3 equivalent
        port_a_write(16'h0010, 32'hAAAA_0000, 4'b1111);
        port_a_write(16'h0011, 32'hBBBB_0000, 4'b1111);
        port_a_write(16'h0012, 32'hCCCC_0000, 4'b1111);
        @(posedge clka); @(posedge clka);
        port_b_read(16'h0010);
        port_b_read(16'h0011);
        port_b_read(16'h0012);

        // Test 4 - full sequence from testbench
        port_a_write(16'h0020, 32'h12345678, 4'b1111);
        @(posedge clka); @(posedge clka); @(posedge clka);

        // This is what the testbench does:
        @(posedge clka);
        $display("t=%0t A: about to assign, addrb=0x%04x", $time, addrb);
        wea = 4'hF; addra = 16'h0021; dina = 32'hFFFFFFFF;
        web = 4'h0; addrb = 16'h0020; dinb = 32'h0;
        $display("t=%0t B: assigned, addrb=0x%04x", $time, addrb);

        @(posedge clka);
        $display("t=%0t C: after clka, addrb=0x%04x doutb=0x%08x", $time, addrb, doutb);
        wea = 4'h0;

        @(posedge clkb);
        $display("t=%0t D: after clkb+1, addrb=0x%04x doutb=0x%08x", $time, addrb, doutb);
        @(posedge clkb);
        $display("t=%0t E: after clkb+2, addrb=0x%04x doutb=0x%08x", $time, addrb, doutb);

        #100; $finish;
    end
endmodule
