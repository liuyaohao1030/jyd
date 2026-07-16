`include "define.v"

// ============================================================================
// KLDJ Performance Counters
//
// Non-intrusive hardware performance counters for profiling program execution.
// Each counter increments by 1 when its associated event signal is asserted.
// Counters are reset to 0 on reset and are read-only (no CSR interface).
//
// Counters:
//   perf_cycle_count         — total cycles since reset de-assertion
//   perf_instret_count       — instructions committed (mem_wb_valid)
//   perf_frontend_stall_count— frontend frozen cycles (load_use || mul/div stall)
//   perf_load_use_stall_count— load-use hazard stall cycles
//   perf_mul_stall_count     — multiplier busy stall cycles
//   perf_div_stall_count     — divider busy stall cycles
//   perf_redirect_count      — EX-stage PC redirects (branch/jump/ecall)
//   perf_load_count          — load requests issued from EX stage
//   perf_store_count         — store requests issued from EX stage
// ============================================================================

module KLDJ_perf_counters(
     input wire clk
    ,input wire rst

    // Event signals (active-high, single-cycle pulses or level signals)
    ,input wire event_instret            // mem_wb_valid
    ,input wire event_frontend_stall     // frontend_stall
    ,input wire event_load_use_stall     // load_use_stall
    ,input wire event_mul_stall          // mul_stall
    ,input wire event_div_stall          // div_stall
    ,input wire event_redirect           // ex_redirect
    ,input wire event_load               // load request (id_ex_valid && !ex_stall && ex_req_load)
    ,input wire event_store              // store request (id_ex_valid && !ex_stall && ex_req_store)

    // Counter outputs
    ,output reg [31:0] perf_cycle_count
    ,output reg [31:0] perf_instret_count
    ,output reg [31:0] perf_frontend_stall_count
    ,output reg [31:0] perf_load_use_stall_count
    ,output reg [31:0] perf_mul_stall_count
    ,output reg [31:0] perf_div_stall_count
    ,output reg [31:0] perf_redirect_count
    ,output reg [31:0] perf_load_count
    ,output reg [31:0] perf_store_count
);

    always @(posedge clk) begin
        if (rst) begin
            perf_cycle_count          <= 32'd0;
            perf_instret_count        <= 32'd0;
            perf_frontend_stall_count <= 32'd0;
            perf_load_use_stall_count <= 32'd0;
            perf_mul_stall_count      <= 32'd0;
            perf_div_stall_count      <= 32'd0;
            perf_redirect_count       <= 32'd0;
            perf_load_count           <= 32'd0;
            perf_store_count          <= 32'd0;
        end else begin
            perf_cycle_count          <= perf_cycle_count          + {31'd0, 1'b1};
            perf_instret_count        <= perf_instret_count        + {31'd0, event_instret};
            perf_frontend_stall_count <= perf_frontend_stall_count + {31'd0, event_frontend_stall};
            perf_load_use_stall_count <= perf_load_use_stall_count + {31'd0, event_load_use_stall};
            perf_mul_stall_count      <= perf_mul_stall_count      + {31'd0, event_mul_stall};
            perf_div_stall_count      <= perf_div_stall_count      + {31'd0, event_div_stall};
            perf_redirect_count       <= perf_redirect_count       + {31'd0, event_redirect};
            perf_load_count           <= perf_load_count           + {31'd0, event_load};
            perf_store_count          <= perf_store_count          + {31'd0, event_store};
        end
    end

endmodule
