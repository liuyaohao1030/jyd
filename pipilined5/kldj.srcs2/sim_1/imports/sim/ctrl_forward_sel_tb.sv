`timescale 1ns/1ps

module ctrl_forward_sel_tb;
    reg        ctrl_rs1_ren;
    reg        ctrl_rs2_ren;
    reg [4:0]  id_rs1_addr;
    reg [4:0]  id_rs2_addr;
    reg        id_ex_valid;
    reg [4:0]  id_ex_rd_addr;
    reg        id_ex_wb_ctl;
    reg        id_ex_load_op;
    reg [4:0]  ex_mem_rd_addr;
    reg        mem_stage_wb_ctl;
    wire [1:0] ctrl_rs1_fwd_sel;
    wire [1:0] ctrl_rs2_fwd_sel;
    integer checks;

    ctrl_forward_sel dut(
         .ctrl_rs1_ren(ctrl_rs1_ren), .ctrl_rs2_ren(ctrl_rs2_ren)
        ,.id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr)
        ,.id_ex_valid(id_ex_valid), .id_ex_rd_addr(id_ex_rd_addr)
        ,.id_ex_wb_ctl(id_ex_wb_ctl), .id_ex_load_op(id_ex_load_op)
        ,.ex_mem_rd_addr(ex_mem_rd_addr), .mem_stage_wb_ctl(mem_stage_wb_ctl)
        ,.ctrl_rs1_fwd_sel(ctrl_rs1_fwd_sel), .ctrl_rs2_fwd_sel(ctrl_rs2_fwd_sel)
    );

    task expect_sel;
        input [1:0] actual;
        input [1:0] expected;
        input [8*56-1:0] label;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("FAIL: %0s expected=%b actual=%b", label, expected, actual);
                $fatal(1);
            end
        end
    endtask

    task defaults;
        begin
            ctrl_rs1_ren = 1'b0;
            ctrl_rs2_ren = 1'b0;
            id_rs1_addr = 5'd0;
            id_rs2_addr = 5'd0;
            id_ex_valid = 1'b0;
            id_ex_rd_addr = 5'd0;
            id_ex_wb_ctl = 1'b0;
            id_ex_load_op = 1'b0;
            ex_mem_rd_addr = 5'd0;
            mem_stage_wb_ctl = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        defaults();
        #1;
        expect_sel(ctrl_rs1_fwd_sel, 2'b00, "no rs1 source uses regfile");
        expect_sel(ctrl_rs2_fwd_sel, 2'b00, "no rs2 source uses regfile");

        // The current ID/EX ALU producer becomes EX/MEM for next cycle.
        defaults();
        ctrl_rs1_ren = 1'b1;
        id_rs1_addr = 5'd7;
        id_ex_valid = 1'b1;
        id_ex_wb_ctl = 1'b1;
        id_ex_rd_addr = 5'd7;
        #1;
        expect_sel(ctrl_rs1_fwd_sel, 2'b01, "rs1 EX producer select");

        // A current MEM load has its data in MEM/WB next cycle and is legal.
        defaults();
        ctrl_rs1_ren = 1'b1;
        id_rs1_addr = 5'd9;
        ex_mem_rd_addr = 5'd9;
        mem_stage_wb_ctl = 1'b1;
        #1;
        expect_sel(ctrl_rs1_fwd_sel, 2'b10, "rs1 MEM writeback select");

        // The nearest writer must win when both pipeline stages match.
        defaults();
        ctrl_rs1_ren = 1'b1;
        ctrl_rs2_ren = 1'b1;
        id_rs1_addr = 5'd11;
        id_rs2_addr = 5'd12;
        id_ex_valid = 1'b1;
        id_ex_wb_ctl = 1'b1;
        id_ex_rd_addr = 5'd11;
        ex_mem_rd_addr = 5'd11;
        mem_stage_wb_ctl = 1'b1;
        #1;
        expect_sel(ctrl_rs1_fwd_sel, 2'b01, "EX writer priority over MEM writer");
        expect_sel(ctrl_rs2_fwd_sel, 2'b00, "unmatched branch rs2 uses regfile");

        // An EX load cannot forward; the existing load-use stall holds ID.
        defaults();
        ctrl_rs1_ren = 1'b1;
        id_rs1_addr = 5'd13;
        id_ex_valid = 1'b1;
        id_ex_wb_ctl = 1'b1;
        id_ex_load_op = 1'b1;
        id_ex_rd_addr = 5'd13;
        #1;
        expect_sel(ctrl_rs1_fwd_sel, 2'b00, "EX load is not selected");

        // x0 must never be considered a forwarding producer.
        defaults();
        ctrl_rs2_ren = 1'b1;
        id_rs2_addr = 5'd0;
        id_ex_valid = 1'b1;
        id_ex_wb_ctl = 1'b1;
        id_ex_rd_addr = 5'd0;
        ex_mem_rd_addr = 5'd0;
        mem_stage_wb_ctl = 1'b1;
        #1;
        expect_sel(ctrl_rs2_fwd_sel, 2'b00, "x0 forwarding producer ignored");

        $display("PASS: ctrl_forward_sel_tb (%0d checks)", checks);
        $finish;
    end
endmodule
