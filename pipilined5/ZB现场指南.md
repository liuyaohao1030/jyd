# RV32 Zb 现场使用指南（RTL 源码开关）

可以。现场切换不需要设置 Vivado 的 `verilog_define`、Tcl 控制台或任何编译命令行宏；只修改一个 RTL 头文件即可。该开关是**编译期**开关，改完后仍须重新综合、实现并下载比特流。

默认配置完全关闭 Zb：相关 IDU/EXU 接入代码会在预处理阶段移除，基础 RV32IM+Zicsr 核的功能和结构保持原样。

## 一、现场只改这三行

打开 [zb_cfg.vh](kldj.srcs2/sources_1/imports/rtl/zb/zb_cfg.vh)，找到 `RTL-local selector` 段。默认是：

```verilog
// `define KLDJ_RTL_EXT_ENABLE
`define KLDJ_RTL_EXT_GROUP `KLDJ_ZB_GROUP_NONE
`define KLDJ_RTL_EXT_OP    `KLDJ_ZB_OP_ALL
```

例如题目要求 **仅支持 `bext`** 时，改成：

```verilog
`define KLDJ_RTL_EXT_ENABLE
`define KLDJ_RTL_EXT_GROUP `KLDJ_ZB_GROUP_ZBS
`define KLDJ_RTL_EXT_OP    `KLDJ_ZB_OP_BEXT
```

这就是全部的“开关”操作。不要再在 Vivado 的 *Verilog Defines* 里填写 `KLDJ_CFG_*` 宏，也不需要为切换指令改任何工程属性。若工程曾遗留这类宏，首次使用本方案前清掉一次即可。

恢复纯基础版时，只需将 `KLDJ_RTL_EXT_ENABLE` 重新注释掉。后两行可以保留，不会生效。

每次只允许选择一个扩展组和一条指令。`KLDJ_ZB_OP_ALL` 只用于赛前把一个组的全部指令一起回归，不建议作为现场最终构型。

## 二、组和指令宏对照

`KLDJ_RTL_EXT_GROUP` 选择所属扩展，`KLDJ_RTL_EXT_OP` 选择一条指令。指令宏采用“助记符大写、`.` 改为 `_`”的命名；完整定义也在 `zb_cfg.vh` 内。

| 扩展 | `KLDJ_RTL_EXT_GROUP` | 可填入 `KLDJ_RTL_EXT_OP` 的宏 |
| --- | --- | --- |
| Zba | `KLDJ_ZB_GROUP_ZBA` | `KLDJ_ZB_OP_SH1ADD`、`KLDJ_ZB_OP_SH2ADD`、`KLDJ_ZB_OP_SH3ADD` |
| Zbb | `KLDJ_ZB_GROUP_ZBB` | `KLDJ_ZB_OP_ANDN`、`KLDJ_ZB_OP_ORN`、`KLDJ_ZB_OP_XNOR`、`KLDJ_ZB_OP_CLZ`、`KLDJ_ZB_OP_CTZ`、`KLDJ_ZB_OP_CPOP`、`KLDJ_ZB_OP_MAX`、`KLDJ_ZB_OP_MAXU`、`KLDJ_ZB_OP_MIN`、`KLDJ_ZB_OP_MINU`、`KLDJ_ZB_OP_SEXT_B`、`KLDJ_ZB_OP_SEXT_H`、`KLDJ_ZB_OP_ZEXT_H`、`KLDJ_ZB_OP_ROL`、`KLDJ_ZB_OP_ROR`、`KLDJ_ZB_OP_RORI`、`KLDJ_ZB_OP_ORC_B`、`KLDJ_ZB_OP_REV8` |
| Zbc | `KLDJ_ZB_GROUP_ZBC` | `KLDJ_ZB_OP_CLMUL`、`KLDJ_ZB_OP_CLMULH`、`KLDJ_ZB_OP_CLMULR` |
| Zbs | `KLDJ_ZB_GROUP_ZBS` | `KLDJ_ZB_OP_BSET`、`KLDJ_ZB_OP_BCLR`、`KLDJ_ZB_OP_BINV`、`KLDJ_ZB_OP_BEXT`、`KLDJ_ZB_OP_BSETI`、`KLDJ_ZB_OP_BCLRI`、`KLDJ_ZB_OP_BINVI`、`KLDJ_ZB_OP_BEXTI` |
| Zbkb | `KLDJ_ZB_GROUP_ZBKB` | `KLDJ_ZB_OP_ANDN`、`KLDJ_ZB_OP_ORN`、`KLDJ_ZB_OP_XNOR`、`KLDJ_ZB_OP_ROL`、`KLDJ_ZB_OP_ROR`、`KLDJ_ZB_OP_RORI`、`KLDJ_ZB_OP_REV8`、`KLDJ_ZB_OP_BREV8`、`KLDJ_ZB_OP_PACK`、`KLDJ_ZB_OP_PACKH`、`KLDJ_ZB_OP_ZIP`、`KLDJ_ZB_OP_UNZIP` |
| Zbkx | `KLDJ_ZB_GROUP_ZBKX` | `KLDJ_ZB_OP_XPERM4`、`KLDJ_ZB_OP_XPERM8` |

本核是 RV32，因此 Zba 的 `.uw`、`add.uw`、`slli.uw` 等 RV64-only 指令不在实现范围内。

## 三、推荐的现场流程

1. 根据下发的 **32 位指令编码** 确认其归属和助记符，不要只凭名称猜扩展。
2. 只编辑 `zb_cfg.vh` 的三行，确保 `GROUP` 与 `OP` 属于同一行表中的扩展。
3. 在本地验证当前源码配置：

   ```bash
   cd jyd/pipilined5/kldj.srcs2
   bash ./sim.sh rtl-zb 60
   bash ./sim.sh rv32i 60
   ```

   第一个命令不会传入任何 `-D` 参数，只读取刚编辑的 `zb_cfg.vh`；成功时会出现 `ZB_RTL_PASS`。第二个命令确认基础指令没有回归。

4. 正常重新运行综合、实现和生成 bitstream。无需改 Vivado 宏设置。
5. 查看新的 `report_timing_summary` 的 WNS/TNS，再下载。

赛前覆盖六组实现可运行：

```bash
bash ./sim.sh zb-all 60
```

该命令是开发回归，内部会用命令行宏逐组编译，不会修改 `zb_cfg.vh`，也不是现场切换方式。

## 四、Vivado 中唯一的一次性准备

工程必须已经包含以下三个模块源文件；以后切换哪一条指令都不再需要改工程设置：

```text
kldj.srcs2/sources_1/imports/rtl/zb/zb_decode.v
kldj.srcs2/sources_1/imports/rtl/zb/zb_exec.v
kldj.srcs2/sources_1/imports/rtl/zb/zb_clmul_iter.v
```

`zb_cfg.vh` 由 `KLDJ_top.v`、`KLDJ_idu.v`、`KLDJ_exu.v` 和上述模块以 `` `include `` 引入，无需把它设置成顶层模块。若这三份 `.v` 已经在工程 source set 中，现场仅改 RTL 宏、重新综合即可；不要再执行任何 `set_property verilog_define ...` 操作。

## 五、功能和时序边界

- 只有所选编码会进入 Zb 执行器；同组其余编码不会被 Zb 插件开启，仍保留基础译码器对原本“非标准编码”的既有处理方式。
- Zb 微操作使用空闲的 `exu_op[17]` 标记，复用已有寄存器旁路、load-use 冒险处理、EX/MEM/WB 通路；普通指令路径没有功能改变。
- Zbc 的 `clmul`、`clmulh`、`clmulr` 使用 32 次迭代 GF(2) 乘法，并复用现有长操作 stall 协议，避免在普通 EX 组合路径上挂大乘法器。
- 当前保存的 200 MHz 报告本身有负裕量，因此“几乎不影响现有时序”应以基础版先闭合、再比较该单指令构型的 WNS/TNS 为准。

## 六、最终检查清单

1. `KLDJ_RTL_EXT_ENABLE` 已取消注释。
2. `KLDJ_RTL_EXT_GROUP` 与 `KLDJ_RTL_EXT_OP` 匹配，且只选一条。
3. Vivado 的 `verilog_define` 没有遗留 `KLDJ_CFG_*` 宏。
4. `bash ./sim.sh rtl-zb 60` 输出 `ZB_RTL_PASS`。
5. `bash ./sim.sh rv32i 60` 输出 `ALL TESTS PASSED`。
6. 实现后 WNS/TNS 满足目标；若使用 Zbc，仿真中应能看到迭代 stall，但不能死锁。
7. 比赛结束或切换题目时，重新编辑这三行并重新综合；恢复基础核则注释 `KLDJ_RTL_EXT_ENABLE`。



开关分三层，最终可以精确到一条指令：

  // 1. 总开关
  `define KLDJ_RTL_EXT_ENABLE

  // 2. 选“哪一组”
  `define KLDJ_RTL_EXT_GROUP `KLDJ_ZB_GROUP_ZBS

  // 3. 选“该组中的哪一条”
  `define KLDJ_RTL_EXT_OP    `KLDJ_ZB_OP_BEXT

  上例只开启 Zbs.bext，不是整个 Zbs。

  如果题目要求整个 Zbs 组都支持，则第三行改为：

  `define KLDJ_RTL_EXT_OP `KLDJ_ZB_OP_ALL

  例如：

  - clmulh：GROUP_ZBC + OP_CLMULH
  - cpop：GROUP_ZBB + OP_CPOP
  - packh：GROUP_ZBKB + OP_PACKH
  - xperm4：GROUP_ZBKX + OP_XPERM4