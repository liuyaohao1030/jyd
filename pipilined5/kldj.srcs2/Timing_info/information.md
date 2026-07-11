### Design Timing Summary (Requirement: 6.7 ns)

**Setup (建立时间)**
* Worst Negative Slack (WNS): -1.369 ns
* Total Negative Slack (TNS): -799.175 ns
* Number of Failing Endpoints: 1940
* Total Number of Endpoints: 18597

**Hold (保持时间)**
* Worst Hold Slack (WHS): 0.063 ns
* Total Hold Slack (THS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 18597

**Pulse Width (脉冲宽度)**
* Worst Pulse Width Slack (WPWS): 1.100 ns
* Total Pulse Width Negative Slack (TPWS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 9905

**Status:**
Timing constraints are not met.

---

### Intra-Clock Paths - clk_out2_pll - Setup

| Name | Slack | Levels | High Fanout | From | To | Total Delay | Logic Delay | Net Delay | Requirement | Source Clock | Destination Clock | Exception | Clock Uncertainty |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Path 21 | -1.369 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_inst...c_reg_reg[22]/D | 7.856 | 1.672 | 6.184 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 22 | -1.331 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins..._reg_reg[13]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 23 | -1.331 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_inst...id_pc_reg[2]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 24 | -1.331 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins...snpc_reg[22]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 25 | -1.331 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins...snpc_reg[5]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 26 | -1.327 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_inst...c_reg_reg[31]/D | 7.803 | 1.672 | 6.131 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 27 | -1.310 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins..._reg_reg[24]/CE | 7.631 | 1.672 | 5.959 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 28 | -1.308 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins..._reg_reg[17]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 29 | -1.308 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins..._reg_reg[19]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 30 | -1.308 | 19 | 109 | student_top_ins...2_addr_reg[0]/C | student_top_ins..._reg_reg[29]/CE | 7.629 | 1.672 | 5.957 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |