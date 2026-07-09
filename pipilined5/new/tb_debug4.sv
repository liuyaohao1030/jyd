`timescale 1ns / 1ps
module tb_debug4;
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
        $dumpfile("tb_debug4.vcd");
        $dumpvars(0, tb_debug4);
        wea=0; addra=0; dina=0; web=0; addrb=0; dinb=0;

        // Test 3: Multiple addresses
        port_a_write(16'h0010, 32'hAAAA_0000, 4'b1111);
        port_a_write(16'h0011, 32'hBBBB_0000, 4'b1111);
        port_a_write(16'h0012, 32'hCCCC_0000, 4'b1111);
        @(posedge clka); @(posedge clka);
        port_b_read(16'h0010);
        port_b_read(16'h0011);
        port_b_read(16'h0012);
        $display("t=%0t After Test 3, addrb=0x%04x", $time, addrb);

        // Test 4: Simultaneous
        $display("t=%0t Starting Test 4", $time);
        port_a_write(16'h0020, 32'h12345678, 4'b1111);
        $display("t=%0t After writing 0x0020, wea=%b addra=0x%04x", $time, wea, addra);
        @(posedge clka); @(posedge clka); @(posedge clka);
        $display("t=%0t Ready for simultaneous, addrb=0x%04x mem[0x0020]=0x%08x", $time, addrb, u_dut.mem[16'h0020]);

        @(posedge clka);
        wea = 4'hF; addra = 16'h0021; dina = 32'hFFFFFFFF;
        web = 4'h0; addrb = 16'h0020; dinb = 32'h0;
        $display("t=%0t Set simultaneous: addrb=0x%04x", $time, addrb);

        @(posedge clka); wea = 4'h0;
        $display("t=%0t After clka: doutb=0x%08x", $time, doutb);
        @(posedge clkb);
        $display("t=%0t After clkb+1: doutb=0x%08x", $time, doutb);
        @(posedge clkb);
        $display("t=%0t After clkb+2: doutb=0x%08x", $time, doutb);

        #100; $finish;
    end
endmodule
