### Design Timing Summary (Requirement: 5.7 ns / ~175 MHz)

**Setup (建立时间)**
* Worst Negative Slack (WNS): -0.324 ns
* Total Negative Slack (TNS): -16.745 ns
* Number of Failing Endpoints: 143
* Total Number of Endpoints: 11109

**Hold (保持时间)**
* Worst Hold Slack (WHS): 0.077 ns
* Total Hold Slack (THS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 11109

**Status:**
Timing constraints are not met.

---

### Intra-Clock Paths - clk_out2_pll - Setup (175MHz Margin Paths)

| Name | Slack | Levels | High Fanout | From | To | Total Delay | Logic Delay | Net Delay | Requirement | Source Clock | Destination Clock | Exception | Clock Uncertainty |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Path 21 | -0.324 | 14 | 64 | student_top_ins...exu_op_reg[0]/C | student_top_ins...t/LED_reg[6]/CE | 5.403 | 1.234 | 4.169 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 22 | -0.324 | 14 | 64 | student_top_ins...exu_op_reg[0]/C | student_top_inst...lopt_replica/CE | 5.403 | 1.234 | 4.169 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 23 | -0.309 | 13 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins..._reg_reg[20]/CE | 5.631 | 1.009 | 4.622 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 24 | -0.305 | 14 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins...pc_reg_reg[4]/D | 5.775 | 1.117 | 4.658 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 25 | -0.292 | 13 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins..._reg_reg[10]/CE | 5.614 | 1.009 | 4.605 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 26 | -0.292 | 13 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins..._reg_reg[2]/CE | 5.614 | 1.009 | 4.605 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 27 | -0.287 | 13 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins..._reg_reg[29]/CE | 5.633 | 1.009 | 4.624 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 28 | -0.285 | 13 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins..._reg_reg[21]/CE | 5.608 | 1.009 | 4.599 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 29 | -0.273 | 13 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins..._reg_reg[15]/CE | 5.594 | 1.009 | 4.585 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |
| Path 30 | -0.270 | 14 | 67 | student_top_ins...exu_op_reg[0]/C | student_top_ins...pc_reg_reg[5]/D | 5.760 | 1.112 | 4.648 | 5.7 | clk_out2_pll | clk_out2_pll | | 0.077 |