### Design Timing Summary (Requirement: 6.7 ns)

**Setup (建立时间)**
* Worst Negative Slack (WNS): 0.142 ns
* Total Negative Slack (TNS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 11521

**Hold (保持时间)**
* Worst Hold Slack (WHS): 0.077 ns
* Total Hold Slack (THS): 0.000 ns
* Number of Failing Endpoints: 0
* Total Number of Endpoints: 11521

**Status:**
All user specified timing constraints are met.

---

### Intra-Clock Paths - clk_out2_pll - Setup (Margin Paths)

| Name | Slack | Levels | Routes | High Fanout | From | To | Total Delay | Logic Delay | Net Delay | Requirement | Source Clock | Destination Clock | Exception | Clock Uncertainty |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Path 21 | 0.142 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[4]_replica_4/D | 6.444 | 1.052 | 5.392 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 22 | 0.160 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[2]_replica_2/D | 6.426 | 1.151 | 5.275 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 23 | 0.174 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[5]_replica_3/D | 6.413 | 1.052 | 5.361 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 24 | 0.178 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[5]_replica_1/D | 6.410 | 1.052 | 5.358 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 25 | 0.208 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[4]_replica_1/D | 6.359 | 1.052 | 5.307 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 26 | 0.243 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_inst...reg[4]_replica/D | 6.321 | 1.052 | 5.269 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 27 | 0.250 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[2]_replica_3/D | 6.338 | 1.151 | 5.187 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 28 | 0.287 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_inst...reg[5]_replica/D | 6.300 | 1.052 | 5.248 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 29 | 0.306 | 10 | 8 | 8 | student_top_i...am/CLKBWRCLK | student_top_ins..._data_reg[13]/D | 6.294 | 2.387 | 3.907 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |
| Path 30 | 0.310 | 14 | 13 | 38 | student_top_ins...exu_op_reg[0]/C | student_top_ins...[6]_replica_3/D | 6.269 | 1.151 | 5.118 | 6.7 | clk_out2_pll | clk_out2_pll | | 0.072 |