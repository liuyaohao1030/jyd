`timescale 1ns / 1ps

`include "define.v"

// -----------------------------------------------------------------------------
// Demo-program performance benchmark
//
// This testbench deliberately uses the board's peripheral bridge and its
// synchronous DRAM model.  It therefore measures the architectural load
// latency seen by the CPU, rather than the shorter latency of a plain
// behavioural array.
//
// Compile this file once with sources_1/imports/rtl (six-stage) and once with
// pipeline5 (five-stage).  run_demo_perf.ps1 does that in separate work dirs.
// -----------------------------------------------------------------------------
module KLDJ_demo_perf_tb;

    localparam [31:0] DONE_PC = 32'h8000_0014; // demo's terminal "jal x0, 0"
    localparam [63:0] FNV_OFFSET = 64'hCBF2_9CE4_8422_2325;
    localparam [63:0] FNV_PRIME  = 64'h0000_0100_0000_01B3;
`ifdef SIX_STATIC_JAL_PRED
    localparam TB_ENABLE_STATIC_JAL_PRED = 1'b1;
`else
    localparam TB_ENABLE_STATIC_JAL_PRED = 1'b0;
`endif
`ifdef SIX_MEM2_LOAD_FWD
    localparam TB_ENABLE_MEM2_LOAD_FWD = 1'b1;
`else
    localparam TB_ENABLE_MEM2_LOAD_FWD = 1'b0;
`endif
`ifdef SIX_RAS_PRED
    localparam TB_ENABLE_RAS_PRED = 1'b1;
`else
    localparam TB_ENABLE_RAS_PRED = 1'b0;
`endif
`ifdef BENCH_TO_COMPLETION
    localparam integer DEFAULT_MAX_CYCLES     = 20_000_000;
    localparam integer MEASURE_INSTRET_LIMIT  = 0;
`else
    // A fixed retired-instruction window gives a fast, fair A/B comparison:
    // both designs execute exactly the same architectural prefix of the demo.
    localparam integer DEFAULT_MAX_CYCLES     = 1_000_000;
    localparam integer MEASURE_INSTRET_LIMIT  = 100_000;
`endif

    reg         clk;
    reg         cnt_clk;
    reg         rst;
    reg [63:0]  virtual_sw;
    reg [7:0]   virtual_key;

    reg  [31:0] inst_mem [0:4095];
    wire [31:0] if_pc;
    wire [31:0] inst_rdata;
    wire [11:0] inst_word_addr;

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire [31:0] mem_rdata;
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    wire        tb_ex_jump;
    wire [31:0] tb_ex_jump_pc;
    wire [31:0] tb_ex_res;

    longint unsigned cycle_count;
    longint unsigned instret_count;
    longint unsigned frontend_stall_count;
    longint unsigned load_use_stall_count;
    longint unsigned mul_stall_count;
    longint unsigned div_stall_count;
    longint unsigned redirect_count;
    longint unsigned ras_return_count;
    longint unsigned ras_pred_hit_count;
    longint unsigned ras_pred_miss_count;
    longint unsigned load_count;
    longint unsigned store_count;
`ifdef BENCH_SIX_STAGE
    // The extra MEM2 interlock is the six-stage-specific behavior under test.
    // Keep this breakdown in the bench so production RTL stays untouched.
    longint unsigned id_ex_load_use_count;
    longint unsigned ex_mem_load_use_count;
    longint unsigned ex_mem_load_use_maskable_count;
`endif
    reg [63:0]       commit_hash;
    integer          max_cycles;
    reg              done;
    reg              terminal_reached;

    assign inst_word_addr = if_pc[13:2];
    assign inst_rdata     = inst_mem[inst_word_addr];

`ifdef BENCH_SIX_STAGE
    wire tb_id_ex_load_use;
    wire tb_ex_mem_load_use;
    wire tb_ex_mem_load_use_maskable;
    wire tb_ex_ras_return;

    assign tb_id_ex_load_use = u_dut.u_ex_forward.id_ex_load_use;
    assign tb_ex_mem_load_use = u_dut.u_ex_forward.ex_mem_load_use;
    // A newer, non-load ID/EX writer of the same rd wins forwarding priority,
    // so the older EX/MEM load cannot be architecturally observed here.
    assign tb_ex_mem_load_use_maskable = tb_ex_mem_load_use &&
                                         u_dut.id_ex_valid &&
                                         u_dut.id_ex_wb_ctl &&
                                         !u_dut.id_ex_load_op &&
                                         (u_dut.id_ex_rd_addr != 5'd0) &&
                                         (u_dut.id_ex_rd_addr == u_dut.ex_mem_rd_addr);
    assign tb_ex_ras_return = u_dut.ex2_valid &&
                              (u_dut.ex2_exu_op == 18'h09) &&
                              (u_dut.ex2_rd_addr == 5'd0) &&
                              ((u_dut.ex2_rs1_addr == 5'd1) ||
                               (u_dut.ex2_rs1_addr == 5'd5)) &&
                              (u_dut.ex2_data2 == 32'd0);
`endif

    initial clk     = 1'b0;
    initial cnt_clk = 1'b0;
    always #5  clk     = ~clk;
    always #10 cnt_clk = ~cnt_clk;

`ifdef BENCH_SIX_STAGE
    // Both switches are six-stage-only attribution experiments.  The default
    // runner remains the production-equivalent baseline.
    KLDJ_top #(
         .ENABLE_STATIC_JAL_PRED(TB_ENABLE_STATIC_JAL_PRED)
        ,.ENABLE_MEM2_LOAD_FWD(TB_ENABLE_MEM2_LOAD_FWD)
        ,.ENABLE_RAS_PRED       (TB_ENABLE_RAS_PRED       )
    ) u_dut (
`else
    KLDJ_top u_dut (
`endif
         .clk          (clk          )
        ,.rst          (rst          )
        ,.tb_if_inst   (inst_rdata   )
        ,.tb_if_pc     (if_pc        )
        ,.tb_ex_jump   (tb_ex_jump   )
        ,.tb_ex_jump_pc(tb_ex_jump_pc)
        ,.tb_ex_res    (tb_ex_res    )
        ,.mem_addr     (mem_addr     )
        ,.mem_wdata    (mem_wdata    )
        ,.mem_we       (mem_we       )
        ,.mem_be       (mem_be       )
        ,.mem_rdata    (mem_rdata    )
        ,.core_clk_o   (             )
    );

    // Match the CPU-visible board memory/peripheral path.  The data image is
    // written below into DRAM_TDP's simulation memory after its zero-fill
    // initial block has completed.
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

    // The two demo COE files have one hexadecimal word per data line.  Keeping
    // this small loader in the bench avoids a second, potentially stale, HEX
    // copy of either program or DRAM initialization image.
    task automatic load_coe;
        input string file_name;
        input integer image_select; // 0 = IROM, 1 = DRAM
        integer fd;
        integer rc;
        integer word_index;
        integer word_limit;
        reg [8*1024-1:0] line;
        reg [31:0] word_data;
        string selected_file;
        begin
            selected_file = file_name;
            fd = $fopen(selected_file, "r");
            // The runner elaborates inside build/demo_perf/<variant>.  Keep
            // direct invocation from the repository root convenient too.
            if (fd == 0) begin
                selected_file = (image_select == 0) ?
                                "demo/irom-v2.coe" :
                                "demo/dram.coe";
                fd = $fopen(selected_file, "r");
            end
            if (fd == 0)
                $fatal(1, "Cannot open COE image: %0s", file_name);

            word_index = 0;
            word_limit = (image_select == 0) ? 4096 : 65536;
            while (!$feof(fd)) begin
                line = {8*1024{1'b0}};
                rc = $fgets(line, fd);
                if ($sscanf(line, "%h", word_data) == 1) begin
                    if (word_index >= word_limit)
                        $fatal(1, "COE image %0s exceeds %0d words",
                               file_name, word_limit);
                    if (image_select == 0)
                        inst_mem[word_index] = word_data;
                    else
                        u_bridge.dram_driver_inst.u_dram_tdp.mem[word_index] = word_data;
                    word_index = word_index + 1;
                end
            end
            $fclose(fd);
            $display("[DEMO_PERF] loaded %0d words from %0s", word_index, selected_file);
        end
    endtask

    // Count internal events directly because the optional top-level perf
    // counter instance is intentionally disabled in the RTL under test.
    always @(posedge clk) begin
        if (rst == `KLDJ_RSTABLE) begin
            cycle_count          <= 0;
            instret_count        <= 0;
            frontend_stall_count <= 0;
            load_use_stall_count <= 0;
            mul_stall_count      <= 0;
            div_stall_count      <= 0;
            redirect_count       <= 0;
            ras_return_count     <= 0;
            ras_pred_hit_count   <= 0;
            ras_pred_miss_count  <= 0;
            load_count           <= 0;
            store_count          <= 0;
`ifdef BENCH_SIX_STAGE
            id_ex_load_use_count <= 0;
            ex_mem_load_use_count <= 0;
            ex_mem_load_use_maskable_count <= 0;
`endif
            commit_hash          <= FNV_OFFSET;
            done                 <= 1'b0;
            terminal_reached     <= 1'b0;
        end else if (!done) begin
            cycle_count          <= cycle_count + 1;
            instret_count        <= instret_count + u_dut.wb_commit_valid;
            frontend_stall_count <= frontend_stall_count + u_dut.frontend_stall;
            load_use_stall_count <= load_use_stall_count + u_dut.load_use_stall;
            mul_stall_count      <= mul_stall_count + u_dut.mul_stall;
            div_stall_count      <= div_stall_count + u_dut.div_stall;
            redirect_count       <= redirect_count + u_dut.ex_redirect;
`ifdef BENCH_SIX_STAGE
            if (tb_ex_ras_return) begin
                ras_return_count <= ras_return_count + 1;
                if (u_dut.ex2_pred_taken &&
                    (u_dut.ex2_pred_target == u_dut.ex2_jump_pc_raw) &&
                    !u_dut.ex_redirect)
                    ras_pred_hit_count <= ras_pred_hit_count + 1;
                else
                    ras_pred_miss_count <= ras_pred_miss_count + 1;
            end
`endif
            load_count           <= load_count +
                                    (u_dut.ex_current_valid && !u_dut.ex_stall &&
                                     u_dut.id_ex_load_op);
            store_count          <= store_count +
                                     (u_dut.ex_current_valid && !u_dut.ex_stall &&
                                      u_dut.id_ex_store_op);
`ifdef BENCH_SIX_STAGE
            id_ex_load_use_count <= id_ex_load_use_count + tb_id_ex_load_use;
            ex_mem_load_use_count <= ex_mem_load_use_count + tb_ex_mem_load_use;
            ex_mem_load_use_maskable_count <= ex_mem_load_use_maskable_count +
                                              tb_ex_mem_load_use_maskable;
`endif

            if (u_dut.wb_commit_valid) begin
                if (u_dut.wb_commit_wb_ctl)
                    commit_hash <= (commit_hash ^
                                    {u_dut.wb_commit_pc, u_dut.wb_commit_wb_data} ^
                                    {59'd0, u_dut.wb_commit_rd_addr}) * FNV_PRIME;
                else
                    commit_hash <= (commit_hash ^
                                    {u_dut.wb_commit_pc, 32'd0}) * FNV_PRIME;
            end

            if (u_dut.wb_commit_valid && (u_dut.wb_commit_pc == DONE_PC)) begin
                terminal_reached <= 1'b1;
                done <= 1'b1;
            end else if ((MEASURE_INSTRET_LIMIT != 0) &&
                         u_dut.wb_commit_valid &&
                         ((instret_count + 1) >= MEASURE_INSTRET_LIMIT)) begin
                done <= 1'b1;
            end
        end
    end

    initial begin : setup_and_run
        string irom_coe;
        string dram_coe;
        integer i;

        rst         = `KLDJ_RSTABLE;
        virtual_sw  = 64'd0;
        virtual_key = 8'd0;
        done        = 1'b0;
        terminal_reached = 1'b0;
        max_cycles  = DEFAULT_MAX_CYCLES;

        if (!$value$plusargs("IROM_COE=%s", irom_coe))
            irom_coe = "../../../demo/irom-v2.coe";
        if (!$value$plusargs("DRAM_COE=%s", dram_coe))
            dram_coe = "../../../demo/dram.coe";

        for (i = 0; i < 4096; i = i + 1)
            inst_mem[i] = 32'h0;

        // DRAM_TDP's initial zero fill and its hierarchy exist at time zero.
        // Wait one simulation tick before overlaying the demo's data image.
        #1;
        load_coe(irom_coe, 0);
        load_coe(dram_coe, 1);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = ~`KLDJ_RSTABLE;

        wait (done == 1'b1);
        #1;
        $display("DEMO_PERF_RESULT cycles=%0d instret=%0d cpi_x1000=%0d load_use_stall=%0d frontend_stall=%0d redirect=%0d ras_return=%0d ras_hit=%0d ras_miss=%0d mul_stall=%0d div_stall=%0d loads=%0d stores=%0d commit_hash=0x%016x terminal=%0d done_pc=0x%08x",
                 cycle_count, instret_count,
                 (instret_count == 0) ? 0 : (cycle_count * 1000) / instret_count,
                 load_use_stall_count, frontend_stall_count, redirect_count,
                  ras_return_count, ras_pred_hit_count, ras_pred_miss_count,
                  mul_stall_count, div_stall_count, load_count, store_count, commit_hash,
                  terminal_reached, DONE_PC);
`ifdef BENCH_SIX_STAGE
        $display("DEMO_PERF_SIX_LOAD_DETAIL id_ex=%0d ex_mem_raw=%0d ex_mem_maskable=%0d",
                 id_ex_load_use_count, ex_mem_load_use_count,
                 ex_mem_load_use_maskable_count);
`endif
        $display("DEMO_PERF_PASS");
        $finish;
    end

    initial begin : timeout_watchdog
        integer timeout_cycles;
        timeout_cycles = DEFAULT_MAX_CYCLES;
        wait (rst != `KLDJ_RSTABLE);
        repeat (timeout_cycles) @(posedge clk);
        if (!done)
            $fatal(1, "[DEMO_PERF_TIMEOUT] exceeded %0d cycles; last commit PC=0x%08x",
                   timeout_cycles, u_dut.wb_commit_pc);
    end

    initial begin
`ifdef BENCH_DUMP_VCD
        begin
`else
        if ($test$plusargs("DUMP_VCD")) begin
`endif
            $dumpfile("KLDJ_demo_perf_tb.vcd");
            $dumpvars(0, KLDJ_demo_perf_tb);
        end
    end

endmodule
