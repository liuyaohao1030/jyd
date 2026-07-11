### Design Timing Summary (Requirement: 6.7 ns)

**Setup (建立时间)**
* Worst Negative Slack (WNS): -0.663 ns
* Total Negative Slack (TNS): -32.862 ns
* Number of Failing Endpoints: 98
* Total Number of Endpoints: 18213

**Hold (保持时间)**
* Worst Hold Slack (WHS): 0.037 ns
* Total Hold Slack (THS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 18213

**Pulse Width (脉冲宽度)**
* Worst Pulse Width Slack (WPWS): 1.100 ns
* Total Pulse Width Negative Slack (TPWS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 9891

**Status:**
Timing constraints are not met.

---

### Intra-Clock Paths - clk_out2_pll - Setup

| Name | Slack | Levels | High Fanout | From | To | Total Delay | Logic Delay | Net Delay | Requirement | Source Clock | Destination Clock | Exception | Clock Uncertainty |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Path 21 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[11]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 22 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[13]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 23 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[28]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 24 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[31]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 25 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[5]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 26 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[8]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 27 | -0.663 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[9]/CE | 7.018 | 1.576 | 5.442 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 28 | -0.608 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[12]/CE | 6.964 | 1.576 | 5.388 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 29 | -0.608 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_ins..._reg_reg[19]/CE | 6.964 | 1.576 | 5.388 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 30 | -0.608 | 19 | 65 | student_top_in...em_valid_reg/C | student_top_in...g[4]_rep__2/CE | 6.964 | 1.576 | 5.388 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |