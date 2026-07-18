# irom-v2 Zb 上板自检映像

`demo/irom-v2.coe` 保持不变。本目录的六个 `irom-v2-<group>.coe` 是单独的
上板测试映像：每个映像只含一个 Zb 扩展组的指令，且必须与同组的 RTL 配置
配对使用。

生成命令：

```bash
python3 demo/zb_irom/gen_irom_zb_variants.py
```

生成器固定校验当前基准映像的 SHA-256；因此不会意外从已改动的上板程序生成
测试映像。清单文件 `irom-v2-zb-manifest.json` 列出每个映像中的指令。

| RTL 组 | IROM 初始化文件 | 覆盖的指令数 | 成功 LED/数码管值 |
| --- | --- | ---: | --- |
| Zba | `irom-v2-zba.coe` | 3 | `0x5A5A0001` |
| Zbb | `irom-v2-zbb.coe` | 18 | `0x5A5A0002` |
| Zbc | `irom-v2-zbc.coe` | 3 | `0x5A5A0003` |
| Zbs | `irom-v2-zbs.coe` | 8 | `0x5A5A0004` |
| Zbkb | `irom-v2-zbkb.coe` | 12 | `0x5A5A0005` |
| Zbkx | `irom-v2-zbkx.coe` | 2 | `0x5A5A0006` |

失败时，LED/数码管保持 `0xE0GG00NN`：`GG` 是扩展组编号（01 至 06），
`NN` 是该组内失败的第一个指令序号。标准映像的成功代码会保持一段时间，随后
原应用从其正常启动路径继续；失败则永久停留，便于观察。

## 上板流程

以 Zba 为例：

1. 在 `sources_1/imports/rtl/zb/zb_cfg.vh` 中只启用 Zba，并保持 OP 为 ALL：

   ```verilog
   `define KLDJ_RTL_EXT_ENABLE
   `define KLDJ_RTL_EXT_GROUP `KLDJ_ZB_GROUP_ZBA
   `define KLDJ_RTL_EXT_OP    `KLDJ_ZB_OP_ALL
   ```

2. 将 IROM IP 的初始化文件改为 `demo/zb_irom/irom-v2-zba.coe`，重新生成 IP
   输出产品，并重新执行综合、实现、生成 bitstream、下载开发板。
3. 观察 LED/数码管中的 `0x5A5A0001`。任何 `0xE...` 值表示失败。
4. 对其余五组重复以上步骤；每次必须只选择一个 RTL 组和对应的一个 COE。
5. 验证结束后，把 IROM 初始化文件恢复为 `demo/irom-v2.coe`，并注释
   `KLDJ_RTL_EXT_ENABLE` 以恢复原始上板配置。

COE 文件本身不能给已生成的 bitstream 增加 Zb 硬件；每个测试映像都必须与
对应 Zb 配置重新综合出的 bitstream 配对。

## 仿真

先按上面的方式选择一个 RTL 组，再运行同名命令：

```bash
bash ./sim_zb_irom_board.sh zba
```

该回归沿用 `student_top` 的 `KLDJ_top -> perip_bridge` 路径，并检查 IROM
自检程序实际写出的 LED 成功码。测试台还会拒绝“未开启、开启多个组、选择了
错误 COE、或 OP 不是 ALL”的组合。

## Zbkx 成功码停住时的快速恢复映像

若板上的标准 `irom-v2-zbkx.coe` 在显示 `5A5A0006` 后没有恢复原程序，请先用
下列命令生成并使用快速映像：

```bash
python3 demo/zb_irom/gen_irom_zb_variants.py \
  --group zbkx --pass-hold-iterations 0 --name-suffix=-quick
```

把 IROM 初始化文件改为 `irom-v2-zbkx-quick.coe`，并保持 RTL 只开启 Zbkx。
该映像仍测试 `xperm4` 和 `xperm8`，但成功后不执行长等待循环，而是立即恢复
原程序。因此它的正常通过现象是原有的“通过指令数/运行时间”继续更新；成功码
可能短到看不见。失败时仍会永久显示 `E0060001` 或 `E0060002`。

若快速映像也无法恢复原程序，则问题不在成功码等待循环，应检查该 Zbkx bitstream
的 IROM 初始化是否已重新生成，以及实现时序是否满足要求（WNS 必须不小于 0）。

若需要肉眼确认成功码，同时又不希望标准映像停留太久，可生成并使用
`irom-v2-zbkx-visible.coe`：

```bash
python3 demo/zb_irom/gen_irom_zb_variants.py \
  --group zbkx --pass-hold-iterations 20000000 --name-suffix=-visible
```

该映像会显示 `5A5A0006` 约数百毫秒，然后通过同一条 Zbkx 专用 JALR trampoline
恢复原来的计数程序。它只影响 Zbkx 映像。

## 保持原应用行为的方式

每个变体只改写它自己的第 0 个 IROM 字为跳转，并把自检代码放在原映像未使用
的 `0x8000_2400` 开始处。自检成功后会清空测试使用的通用寄存器、等价重建
原启动指令设置的 `sp=0x80121000`，然后跳回原映像的 `0x8000_0004`。因此
原始 `demo/irom-v2.coe` 不会被修改，且测试变体在显示成功码后按冷启动语义
继续运行原应用。
