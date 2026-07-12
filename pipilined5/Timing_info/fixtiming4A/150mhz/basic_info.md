### Design Timing Summary (Requirement: 6.7 ns)

**Setup (建立时间)**
* Worst Negative Slack (WNS): 0.361 ns
* Total Negative Slack (TNS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 11109

**Hold (保持时间)**
* Worst Hold Slack (WHS): 0.074 ns
* Total Hold Slack (THS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 11109

**Status:**
All user specified timing constraints are met.

---

### Intra-Clock Paths - clk_out2_pll - Setup (Margin Paths)

| Name | Slack | Levels | High Fanout | From | To | Total Delay | Logic Delay | Net Delay | Requirement | Source Clock | Destination Clock | Exception | Clock Uncertainty |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Path 21 | 0.361 | 10 | 38 | student_top_ins..._addr_reg[2]/C | student_top_in...6.ram/ENBWREN | 5.905 | 1.081 | 4.824 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 22 | 0.375 | 10 | 38 | student_top_ins..._addr_reg[2]/C | student_top_in...6.ram/ENBWREN | 5.796 | 1.090 | 4.706 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 23 | 0.409 | 10 | 8 | student_top_i...am/CLKBWRCLK | student_top_ins..._data_reg[13]/D | 5.846 | 2.386 | 3.460 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 24 | 0.419 | 10 | 8 | student_top_i...am/CLKBWRCLK | student_top_inst...b_data_reg[9]/D | 5.835 | 2.388 | 3.447 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 25 | 0.436 | 10 | 38 | student_top_ins..._addr_reg[2]/C | student_top_in...6.ram/ENBWREN | 5.733 | 1.089 | 4.644 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 26 | 0.438 | 9 | 38 | student_top_ins..._addr_reg[2]/C | student_top_in...6.ram/ENBWREN | 5.683 | 0.982 | 4.701 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 27 | 0.467 | 10 | 38 | student_top_ins..._addr_reg[2]/C | student_top_in...6.ram/ENBWREN | 5.543 | 1.081 | 4.462 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 28 | 0.474 | 10 | 8 | student_top_i...am/CLKBWRCLK | student_top_ins..._data_reg[11]/D | 5.780 | 2.386 | 3.394 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 29 | 0.477 | 10 | 38 | student_top_ins..._addr_reg[2]/C | student_top_in...6.ram/ENBWREN | 5.617 | 1.081 | 4.536 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 30 | 0.482 | 10 | 8 | student_top_i...am/CLKBWRCLK | student_top_inst...b_data_reg[8]/D | 5.748 | 2.378 | 3.370 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |