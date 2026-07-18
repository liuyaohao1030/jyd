`timescale 1ns / 1ps

`include "define.v"
`include "zb_cfg.vh"

// Board-path regression for the generated demo/zb_irom/irom-v2-*.coe files.
// It uses the same KLDJ_top -> perip_bridge path as student_top.  The test
// image writes a persistent pass/fail word to the LED and seven-segment MMIO
// registers before the original demo is resumed.
module KLDJ_zb_irom_board_tb #(
    parameter integer IMAGE_GROUP = 0
);

    localparam integer MAX_CYCLES = 100000;
    localparam [31:0] PASS_LED =
        (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBA ) ? 32'h5a5a0001 :
        (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBB ) ? 32'h5a5a0002 :
        (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBC ) ? 32'h5a5a0003 :
        (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBS ) ? 32'h5a5a0004 :
        (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBKB) ? 32'h5a5a0005 :
        (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_ZBKX) ? 32'h5a5a0006 :
                                                          32'h00000000;

    reg         clk;
    reg         cnt_clk;
    reg         rst;
    reg [63:0]  virtual_sw;
    reg [7:0]   virtual_key;

    reg  [31:0] inst_mem [0:4095];
    wire [31:0] if_pc;
    wire [31:0] inst_rdata;
    wire [11:0] inst_word_addr = if_pc[13:2];

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire [31:0] mem_rdata;
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    assign inst_rdata = inst_mem[inst_word_addr];

    KLDJ_top u_dut (
         .clk          (clk          )
        ,.rst          (rst          )
        ,.tb_if_inst   (inst_rdata   )
        ,.tb_if_pc     (if_pc        )
        ,.tb_ex_jump   (             )
        ,.tb_ex_jump_pc(             )
        ,.tb_ex_res    (             )
        ,.mem_addr     (mem_addr     )
        ,.mem_wdata    (mem_wdata    )
        ,.mem_we       (mem_we       )
        ,.mem_be       (mem_be       )
        ,.mem_rdata    (mem_rdata    )
        ,.core_clk_o   (             )
    );

    perip_bridge u_bridge (
         .clk                (clk          )
        ,.cnt_clk            (cnt_clk      )
        ,.rst                (rst          )
        ,.perip_addr         (mem_addr     )
        ,.perip_wdata        (mem_wdata    )
        ,.perip_wen          (mem_we       )
        ,.perip_be           (mem_be       )
        ,.perip_rdata        (mem_rdata    )
        ,.virtual_sw_input   (virtual_sw   )
        ,.virtual_key_input  (virtual_key  )
        ,.virtual_seg_output (virtual_seg  )
        ,.virtual_led_output (virtual_led  )
    );

    initial clk     = 1'b0;
    initial cnt_clk = 1'b0;
    always #5  clk     = ~clk;
    always #10 cnt_clk = ~cnt_clk;

    // COE parser shared in spirit with KLDJ_demo_perf_tb: the two header
    // lines are ignored and each hexadecimal data word is loaded in order.
    task automatic load_coe;
        input string file_name;
        integer fd;
        integer rc;
        integer word_index;
        reg [8*1024-1:0] line;
        reg [31:0] word_data;
        begin
            fd = $fopen(file_name, "r");
            if (fd == 0)
                $fatal(1, "Cannot open IROM COE image: %0s", file_name);
            word_index = 0;
            while (!$feof(fd)) begin
                line = {8*1024{1'b0}};
                rc = $fgets(line, fd);
                if ($sscanf(line, "%h", word_data) == 1) begin
                    if (word_index >= 4096)
                        $fatal(1, "IROM COE exceeds 4096 words: %0s", file_name);
                    inst_mem[word_index] = word_data;
                    word_index = word_index + 1;
                end
            end
            $fclose(fd);
            $display("[IROM_ZB] loaded %0d words from %0s", word_index, file_name);
        end
    endtask

    initial begin : run_test
        string irom_coe;
        integer i;
        integer cycles;

        if (`KLDJ_ZB_CONFIG_COUNT != 1)
            $fatal(1, "IROM Zb test requires exactly one enabled extension, got %0d",
                   `KLDJ_ZB_CONFIG_COUNT);
        if (`KLDJ_ZB_GROUP_SEL == `KLDJ_ZB_GROUP_NONE)
            $fatal(1, "IROM Zb test has no selected extension group");
        if (`KLDJ_ZB_GROUP_SEL != IMAGE_GROUP)
            $fatal(1, "COE image group %0d does not match RTL group %0d",
                   IMAGE_GROUP, `KLDJ_ZB_GROUP_SEL);
        if (`KLDJ_CFG_OP != `KLDJ_ZB_OP_ALL)
            $fatal(1, "IROM Zb image covers a full group; KLDJ_RTL_EXT_OP must be ALL");
        if (!$value$plusargs("IROM_COE=%s", irom_coe))
            $fatal(1, "Pass +IROM_COE=demo/zb_irom/irom-v2-<group>.coe");

        rst         = `KLDJ_RSTABLE;
        virtual_sw  = 64'd0;
        virtual_key = 8'd0;
        for (i = 0; i < 4096; i = i + 1)
            inst_mem[i] = 32'h00000013;

        // Allow the peripheral model's initialization blocks to complete.
        #1;
        load_coe(irom_coe);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = ~`KLDJ_RSTABLE;

        for (cycles = 0; cycles < MAX_CYCLES; cycles = cycles + 1) begin
            @(posedge clk);
            if (virtual_led === PASS_LED) begin
                repeat (4) @(posedge clk);
                if (virtual_led !== PASS_LED)
                    $fatal(1, "pass LED was not retained: got 0x%08x", virtual_led);
                $display("IROM_ZB_BOARD_PASS group=%0d led=0x%08x cycles=%0d",
                         `KLDJ_ZB_GROUP_SEL, virtual_led, cycles + 1);
                $finish;
            end
            if (virtual_led[31:28] === 4'he)
                $fatal(1, "IROM_ZB_BOARD_FAIL group=%0d led=0x%08x cycles=%0d",
                       `KLDJ_ZB_GROUP_SEL, virtual_led, cycles + 1);
        end

        $fatal(1, "IROM Zb test timed out after %0d cycles; PC=0x%08x LED=0x%08x",
               MAX_CYCLES, if_pc, virtual_led);
    end

endmodule
