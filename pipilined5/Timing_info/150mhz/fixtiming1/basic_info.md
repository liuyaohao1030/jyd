### Design Timing Summary (Requirement: 6.7 ns)

**Setup (建立时间)**
* Worst Negative Slack (WNS): -0.501 ns
* Total Negative Slack (TNS): -18.963 ns
* Number of Failing Endpoints: 73
* Total Number of Endpoints: 11579

**Hold (保持时间)**
* Worst Hold Slack (WHS): 0.024 ns
* Total Hold Slack (THS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 11579

**Pulse Width (脉冲宽度)**
* Worst Pulse Width Slack (WPWS): 1.100 ns
* Total Pulse Width Negative Slack (TPWS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 6315

**Status:**
Timing constraints are not met.

---

### Intra-Clock Paths - clk_out2_pll - Setup

| Name | Slack | Levels | High Fanout | From | To | Total Delay | Logic Delay | Net Delay | Requirement | Source Clock | Destination Clock | Exception | Clock Uncertainty |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Path 21 | -0.501 | 19 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins...pc_reg_reg[9]/D | 7.051 | 1.594 | 5.457 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 22 | -0.497 | 19 | 41 | student_top_ins..._addr_reg[1]/C | student_top_inst...c_reg_reg[10]/D | 7.054 | 1.594 | 5.460 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 23 | -0.496 | 19 | 41 | student_top_ins..._addr_reg[1]/C | student_top_inst...c_reg_reg[13]/D | 7.045 | 1.594 | 5.451 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 24 | -0.480 | 19 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins...pc_reg_reg[4]/D | 7.028 | 1.594 | 5.434 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 25 | -0.465 | 19 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins...pc_reg_reg[1]/D | 7.024 | 1.594 | 5.430 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 26 | -0.431 | 19 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins...pc_reg_reg[6]/D | 6.979 | 1.594 | 5.385 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 27 | -0.413 | 18 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins..._reg_reg[17]/CE | 6.780 | 1.551 | 5.229 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 28 | -0.413 | 18 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins..._reg_reg[21]/CE | 6.780 | 1.551 | 5.229 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 29 | -0.413 | 18 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins..._reg_reg[22]/CE | 6.780 | 1.551 | 5.229 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 30 | -0.413 | 18 | 41 | student_top_ins..._addr_reg[1]/C | student_top_ins..._reg_reg[26]/CE | 6.780 | 1.551 | 5.229 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |