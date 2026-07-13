# EX1/EX2 流水线拆分 Skill

## 1. 目标

将当前 5 级流水线 `IF → ID → EX → MEM → WB` 拆分为 6 级：

```
IF → ID → EX1 → EX2 → MEM → WB
```

**核心目的：** 打断从 EX/MEM 寄存器到 IFU PC 寄存器的关键路径，提高主频。

**当前瓶颈路径：**
```
EX/MEM寄存器输出 → 前递mux → ALU → 分支比较 → 跳转目标 → redirect → IFU pc_reg
```
这条路径全部是组合逻辑，一个周期内必须算完，是 setup 时间最难满足的路径。

**拆分后：**
```
EX1：EX/MEM → 前递mux → 写入EX1/EX2寄存器    （~3ns）
EX2：ALU → 分支 → redirect → pc_reg            （~3ns）
```

---

## 2. 拆分边界原则

### EX1 的职责（选数）
- 前递命中判断
- 前递数据选择 mux
- 操作数最终准备
- dependency stall 检测

### EX2 的职责（算数）
- ALU 运算
- 分支判断与目标计算
- 跳转决策
- 访存地址计算
- CSR 读写
- MUL/DIV 多周期运算
- BPU 更新
- redirect 生成

### 核心约束
- **EX1 不产生任何不可撤销副作用**（不写寄存器、不写内存、不改 CSR、不更新 BPU）
- **EX2 内部逻辑零改动**，只改输入端口连线
- **第一版不加 EX2→EX1 组合前递**，避免重新形成长路径

---

## 3. 指令类型覆盖分析（基于 irom-v2.coe）

测试程序共 2218 条指令，覆盖以下类型：

| 类型 | 指令 | 数量 | 涉及的冒险类型 |
|------|------|------|----------------|
| R-type | add, sub, sll, srl, sra, slt, sltu, xor, or, and | 85 | 数据冒险（RAW） |
| **M-extension** | **mul, mulh, mulhsu, mulhu, div, divu, rem, remu** | **39** | **多周期 + 数据冒险** |
| I-type ALU | addi, slli, srli, srai, slti, sltiu, xori, ori, andi | 764 | 数据冒险（RAW） |
| Load | lb, lh, lw, lbu, lhu | 341 | Load-Use 冒险 |
| Store | sb, sh, sw | 301 | Store 数据冒险 |
| Branch | beq, bne, blt, bge, bltu, bgeu | 147 | 控制冒险 |
| JAL | jal | 131 | 控制冒险 |
| JALR | jalr | 118 | 控制冒险 + 数据冒险 |
| LUI | lui | 161 | 无 |
| AUIPC | auipc | 108 | 无 |
| CSR | csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci | 18 | CSR 冒险 |
| System | ecall, mret | 3 | 控制冒险 |
| NOP | nop | 若干 | 无 |

**冒险密度：**
- 控制冒险：17.6%（396/2218 条是分支/跳转）
- Load-Use 冒险：15.4%（341/2218 条是 load）
- 多周期冒险：1.8%（39/2218 条是 M-extension）

---

## 4. 时序场景模型

以下场景基于改造前的 5 级流水线行为建理，改造后的 6 级流水线必须在每个场景下产生**相同的最终寄存器状态和内存状态**。

### 场景 S1：连续 ALU 无依赖

```asm
add  t0, t1, t2    # A
sub  t3, t4, t5    # B（不依赖 A）
and  t6, t7, t8    # C（不依赖 B）
```

**改造前时序：**
```
周期  IF   ID   EX   MEM  WB
 1    C    B    A    -    -
 2    -    C    B    A    -
 3    -    -    C    B    A
 4    -    -    -    C    B
 5    -    -    -    -    C
```
无 stall，每周期推进一条。

**改造后期望：**
```
周期  IF   ID   EX1  EX2  MEM  WB
 1    C    B    A    -    -    -
 2    -    C    B    A    -    -
 3    -    -    C    B    A    -
 4    -    -    -    C    B    A
 5    -    -    -    -    C    B
 6    -    -    -    -    -    C
```
同样无 stall，只是多一拍延迟。最终寄存器状态相同。

---

### 场景 S2：ALU → ALU 数据冒险（RAW）

```asm
add  t0, t1, t2    # A：产生 t0
sub  t3, t0, t4    # B：消费 t0（EX1 依赖 EX2）
```

**改造前时序：**
```
周期  IF   ID   EX        MEM  WB
 1    B    A    A(算t0)    -    -
 2    -    B    B(前递t0)  A    -
 3    -    -    -          B    A
```
B 在 EX 阶段通过前递从 EX/MEM 拿到 A 的结果，无 stall。

**改造后期望：**
```
周期  IF   ID   EX1       EX2       MEM  WB
 1    B    A    A(选数)    -         -    -
 2    -    B    B(依赖!)   A(算t0)   -    -
 3    -    -    B(hold)    bubble    A    -
 4    -    -    B(前递t0)  -         bub  A
 5    -    -    -          B(算t3)   -    -
```
B 在 EX1 检测到依赖 A（A 在 EX2），插入 bubble 到 EX1/EX2，A 继续推进到 EX2/MEM。下一拍 A 离开 EX2/MEM，B 从 EX2/MEM 前递拿到 t0。

**实际行为：** 依赖检测持续到 A 离开 EX2/MEM（周期 3 结束）。周期 4 组合逻辑评估时，A 已不在 EX2/MEM，ex1_dependency_stall=0，B 进入 EX1 并从 EX2/MEM 前递。总 stall 1 拍。

**验证点：** t3 = t1 + t2 - t4，与改造前一致。

---

### 场景 S3：Load-Use 冒险

```asm
lw   t0, 0(t1)     # A：load，结果在 MEM 阶段才回来
add  t2, t0, t3    # B：依赖 A 的 load 结果
```

**改造前时序：**
```
周期  IF   ID   EX        MEM        WB
 1    B    A    A(算地址)  -          -
 2    -    B    B(stall!)  A(读内存)  -
 3    -    -    B(前递t0)  -          A
 4    -    -    -          B          -
```
B 在 EX 阶段 stall 1 拍，等 A 的 load 数据从 MEM 回来。

**改造后期望：**
```
周期  IF   ID   EX1        EX2       MEM        WB
 1    B    A    A(选数)     -         -          -
 2    -    B    B(依赖!)    A(算地址) -          -
 3    -    -    B(hold)     bubble    A(读内存)  -
 4    -    -    B(hold→)    bub       bub        A
 5    -    -    B(前递t0)   -         -          bub
 6    -    -    -           B(算t2)   -          -
```

**依赖检测时序：** A 是 load 指令，数据在 MEM 阶段才可用。
- 周期 2：B 在 ID/EX1，A 在 EX1/EX2 → 检测到依赖，stall
- 周期 3：A 推进到 EX2/MEM（load，开始读内存），B 仍在 ID/EX1 → 依赖持续，stall
- 周期 4：A 推进到 MEM/WB，EX2/MEM 变为 bubble → 依赖清除，B 进入 EX1
- 周期 5：B 从 MEM/WB 前递拿到 load 数据

共 stall 2 拍，与改造前一致。

**验证点：** t2 = mem[0+t1] + t3，与改造前一致。

---

### 场景 S4：Store 数据冒险

```asm
add  t0, t1, t2    # A：产生 t0
sw   t0, 0(t3)     # B：store t0 到内存
```

**改造前时序：**
```
周期  IF   ID   EX        MEM        WB
 1    B    A    A(算t0)    -          -
 2    -    B    B(前递t0,写mem) A    -
 3    -    -    -          B          A
```

**改造后期望：**
```
周期  IF   ID   EX1       EX2       MEM        WB
 1    B    A    A(选数)    -         -          -
 2    -    B    B(依赖!)   A(算t0)   -          -
 3    -    -    B(hold)    bubble    A          -
 4    -    -    B(前递t0)  -         bub        A
 5    -    -    -          B(写mem)  -          -
```

A 是 ALU 指令，结果在 EX2/MEM 即可前递。依赖检测持续到 A 离开 EX2/MEM（周期 3 结束），周期 4 B 进入 EX1 并前递。总 stall 1 拍。

**验证点：** mem[t3+0] = t1 + t2，与改造前一致。注意 store 的 data（rs2）也需要前递。

---

### 场景 S5：分支预测正确

```asm
loop: addi t0, t0, 1     # A
      bne  t0, t1, loop   # B：预测 taken，实际 taken
      nop                  # C（不会执行）
```

**改造前时序：**
```
周期  IF        ID   EX         MEM  WB
 1    B         A    A(算t0)    -    -
 2    loop      B    B(判断:跳) A    -
 3    A'        -    -          B    A
```
BPU 预测正确，无 redirect。

**改造后期望：**
```
周期  IF        ID   EX1       EX2        MEM  WB
 1    B         A    A(选数)    -          -    -
 2    loop      B    B(选数)    A(算t0)    -    -
 3    A'        -    -          B(判断:跳) A    -
 4    -         A'   -          -          B    A
```

**验证点：** t0 最终递增到 t1，与改造前一致。

---

### 场景 S6：分支预测错误（方向错）

```asm
beq  t0, t1, label   # A：预测 not taken，实际 taken
nop                    # B（错误路径，应被冲刷）
nop                    # C（错误路径，应被冲刷）
label:
add  t2, t3, t4       # D（正确路径）
```

**改造前时序：**
```
周期  IF        ID   EX          MEM  WB
 1    B         A    A(判断:跳!) -    -
 2    D(正确)   B(flush) C(flush) A  -
 3    -         D    -           -    A
```
A 在 EX 发现预测错误，flush IF/ID，从正确地址重新取指。冲刷 2 级，浪费 2 拍。

**改造后期望：**
```
周期  IF        ID   EX1       EX2          MEM  WB
 1    B         A    A(选数)    -            -    -
 2    C         B    B(选数)    A(判断:跳!)  -    -
 3    D(正确)   C(flush) B(flush) -          A    -
 4    -         D    -          -            -    A
```
A 在 EX2 发现预测错误，flush IF/ID/EX1，冲刷 3 级，浪费 3 拍。

**验证点：** t2 = t3 + t4，D 的结果正确。错误路径的 B、C 不产生任何副作用。

---

### 场景 S7：分支预测错误（目标错）

```asm
beq  t0, t1, label   # A：预测 taken → 0x100，实际 taken → 0x200
nop
label:                # 0x200
add  t2, t3, t4       # D
```

**改造前时序：**
```
周期  IF        ID   EX             MEM  WB
 1    0x100     A    A(目标=0x200!) -    -
 2    D(0x200)  flush  flush        A    -
```

**改造后期望：**
```
周期  IF        ID   EX1       EX2              MEM  WB
 1    0x100     A    A(选数)    -                -    -
 2    0x100的B  -    B(选数)    A(目标=0x200!)   -    -
 3    D(0x200)  flush flush     -                A    -
```

**验证点：** 从 0x200 正确取指，D 结果正确。

---

### 场景 S8：JAL 跳转

```asm
jal  ra, func       # A：跳转 + 保存返回地址
nop                  # B（延迟槽，被冲刷）
func:
addi sp, sp, -16    # C
```

**改造前时序：**
```
周期  IF        ID   EX         MEM  WB
 1    B         A    A(跳转!)   -    -
 2    C         B(flush) -     A    -
```

**改造后期望：**
```
周期  IF        ID   EX1       EX2        MEM  WB
 1    B         A    A(选数)    -          -    -
 2    C(错误?)  B    -          A(跳转!)   -    -
 3    func      B(flush) -     -          A    -
```

**验证点：** ra = PC+4（返回地址正确），PC 跳到 func。

---

### 场景 S9：JALR 寄存器间接跳转

```asm
lw   t0, 0(t1)      # A：load 目标地址
jalr ra, t0, 0       # B：依赖 A 的 load 结果
nop                   # C（被冲刷）
target:               # 实际跳转目标
add  t2, t3, t4      # D
```

**这是最复杂的场景：Load-Use + 控制冒险叠加。**

**改造前时序：**
```
周期  IF        ID   EX          MEM        WB
 1    B         A    A(算地址)   -          -
 2    C         B    B(stall!)   A(读内存)  -
 3    -         C    B(前递t0,跳!) -        A
 4    D(target) C(flush) -      B          -
```

**改造后期望：**
```
周期  IF        ID   EX1        EX2         MEM        WB
 1    B         A    A(选数)     -           -          -
 2    C         B    B(依赖!)    A(算地址)   -          -
 3    -         C    B(hold)     bubble      A(读内存)  -
 4    -         -    B(hold)     bub         bub        A
 5    D(target) -    B(前递t0)   -           -          bub
 6    -         -    -           B(跳转!)    -          -
 7    -         D    flush       flush       -          B
```

**依赖检测时序：** 与 S3 一致，load 依赖需要 stall 2 拍。
- 周期 2-4：B 在 ID/EX1，等待 A 的 load 数据就绪
- 周期 5：B 进入 EX1，从 MEM/WB 前递拿到 t0
- 周期 6：B 在 EX2 计算跳转目标并执行跳转

**验证点：** ra = B的PC+4，PC = t0（从 load 拿到的地址），D 在正确地址执行。

---

### 场景 S10：CSR 读写

```asm
csrrw t0, mscratch, t1   # A：写 mscratch = t1，读旧值到 t0
csrrs t2, mscratch, t3   # B：读 mscratch（应为 t1），设置位
```

**改造前时序：**
```
周期  IF   ID   EX          MEM  WB
 1    B    A    A(读旧CSR,写CSR)  -
 2    -    B    B(读新CSR)   A    -
```
CSR 读是组合逻辑，写是时序逻辑，同周期读到旧值是正确的。

**改造后期望：**
```
周期  IF   ID   EX1       EX2            MEM  WB
 1    B    A    A(选数)    -              -    -
 2    -    B    B(选数)    A(读旧CSR,写)  -    -
 3    -    -    B          B(读旧CSR)     A    -
```

**CSR 读写语义：** CSR 读是组合逻辑，写是时序逻辑（posedge clk）。B 在 EX2 读 CSR 时，A 的写尚未生效（写在周期末 posedge），所以 B 读到的是**旧值**，不是 A 写入的新值。这与改造前行为一致。

**验证点：** t0 = mscratch旧值，t2 = mscratch旧值 | t3，mscratch = t1（A 的写在周期末生效）。

---

### 场景 S11：ecall 异常

```asm
addi t0, zero, 10    # A
ecall                 # B：触发异常，跳到 mtvec
nop                   # C（被冲刷）
```

**改造前时序：**
```
周期  IF        ID   EX            MEM  WB
 1    B         A    A(算10)       -    -
 2    C         B    B(ecall→mtvec) A  -
 3    mtvec处   C(flush) -        B    A
```

**改造后期望：**
```
周期  IF        ID   EX1       EX2             MEM  WB
 1    B         A    A(选数)    -               -    -
 2    C         B    B(选数)    A(算10)         -    -
 3    mtvec处   C    flush      B(ecall→mtvec)  A    -
 4    -         flush -        -               B    A
```

**验证点：** mepc = B的PC，mcause = 0xB，PC = mtvec，t0 = 10。

---

### 场景 S12：mret 返回

```asm
mret    # A：从异常返回，PC = mepc
nop     # B（被冲刷）
```

**改造前时序：**
```
周期  IF        ID   EX           MEM  WB
 1    B         A    A(mret→mepc) -    -
 2    mepc处    B(flush) -        A    -
```

**改造后期望：**
```
周期  IF        ID   EX1       EX2          MEM  WB
 1    B         A    A(选数)    -            -    -
 2    mepc处    B    flush      A(mret→mepc) -    -
 3    -         flush -        -            A    -
```

**验证点：** PC = mepc（异常前的 PC）。

---

### 场景 S13：MUL/DIV 多周期（测试程序已覆盖 39 条）

```asm
mul  t0, t1, t2    # A：多周期运算
add  t3, t0, t4    # B：依赖 A
```

**改造前时序：**
```
周期  IF   ID   EX          MEM  WB
 1    B    A    A(mul第1拍)  -    -
 2    -    B    A(mul第2拍)  -    -
 3    -    -    A(mul完成)   -    -
 4    -    -    B(前递t0)    A    -
```

**改造后期望：**
```
周期  IF   ID   EX1        EX2           MEM  WB
 1    B    A    A(选数)     -             -    -
 2    -    B    B(依赖!)    A(mul第1拍)   -    -
 3    -    -    B(hold)     A(mul第2拍)   -    -
 4    -    -    B(hold)     A(mul完成)    -    -
 5    -    -    B(前递t0)   -             A    -
 6    -    -    -           B(算t3)       -    A
```

**关键机制：**
- EX2 busy 期间（ex2_stall=1）：PC/IFID hold，ID/EX1 hold，EX1/EX2 hold，EX2/MEM 插 bubble
- A 不能离开 EX2 直到 MUL/DIV 完成
- MUL/DIV 完成后，ex2_stall=0，A 推进到 EX2/MEM
- 下一拍 B 从 EX2/MEM 前递拿到 A 的结果

**注意：** 周期 2 中 B 的"依赖"检测实际上是因为 ex2_stall 导致的 ID/EX1 hold，而不是 ex1_dependency_stall。两者效果相同：B 卡在 ID/EX1 不动。

**验证点：** t0 = t1 * t2（正确乘法结果），t3 = t0 + t4。

---

### 场景 S14：连续分支（BPU 压力测试）

```asm
loop: addi t0, t0, 1       # A
      bne  t0, t1, loop     # B：循环分支
      addi t2, zero, 1      # C：循环结束后
```

**改造前时序（循环体执行 N 次）：**
```
每次循环：A 在 EX，B 在 EX 判断跳转。
预测正确时无 redirect，预测错误时冲刷 2 级。
```

**改造后期望：**
```
每次循环：A 在 EX2，B 在 EX2 判断跳转。
预测正确时无 redirect，预测错误时冲刷 3 级。
```

**验证点：** t0 = t1，t2 = 1（循环结束后执行 C）。

---

### 场景 S15：Store → Load 同地址

```asm
sw   t0, 0(t1)      # A：写内存
lw   t2, 0(t1)      # B：读同地址
```

**改造前时序：**
```
周期  IF   ID   EX        MEM        WB
 1    B    A    A(写mem)   -          -
 2    -    B    B(读mem)   A          -
 3    -    -    -          B          A
```
A 写和 B 读在不同周期访问内存，无冲突。

**改造后期望：**
```
周期  IF   ID   EX1       EX2       MEM        WB
 1    B    A    A(选数)    -         -          -
 2    -    B    B(选数)    A(写mem)  -          -
 3    -    -    B          B         A          -
 4    -    -    -          B(读mem)  -          A
```

**验证点：** t2 = t0（先写后读，值一致）。

---

## 5. 不变量约束

改造后的 CPU 必须满足以下不变量，与改造前行为一致：

### 数据正确性
1. **每条有效指令最多写寄存器一次**
2. **每条有效指令最多写内存一次**
3. **每条有效指令最多更新 BPU 一次**
4. **每条有效指令最多执行一次 CSR 写**
5. **x0 永远为 0**

### 冒险处理
6. **RAW 冒险：** 结果必须在消费者读取前就绪（通过前递或 stall）
7. **Load-Use：** load 结果未就绪时，消费者必须 stall
8. **控制冒险：** 预测错误时，错误路径指令的所有副作用必须被撤销
9. **Store 数据：** store 的 rs2 数据必须正确前递

### 流水线控制
10. **优先级：** reset > redirect/flush > busy_stall > dependency_stall > 正常
11. **flush 优先于 hold：** redirect 到来时，即使 MUL/DIV 在忙，也必须清空年轻指令
12. **dependency stall 时 EX1/EX2 插 bubble（不是 hold）：** 生产者必须继续推进
13. **redirect 时 EX2/MEM 正常推进：** 产生 redirect 的指令不被自己的 flush 杀掉
14. **ecall/mret 的 CSR 副作用与 redirect 对齐：** mepc/mcause/mstatus 更新和 redirect 在同一周期

### 前递正确性
15. **EX2/MEM → EX1 前递：** ALU 结果可在下一拍前递
16. **MEM/WB → EX1 前递：** load 结果可在两拍后前递
17. **不加 EX2 组合结果 → EX1 前递：** 避免重新形成长路径

---

## 6. 改动清单

### 新增文件
| 文件 | 职责 | 行数 |
|------|------|------|
| pipe_ex1_ex2.v | EX1/EX2 流水寄存器 | ~120 |

### 修改文件
| 文件 | 改动 | 行数 |
|------|------|------|
| ex_forward.v | 加 dependency stall 检测 + 输出改名 | ~25 |
| KLDJ_exu.v | 输入端口改接 ex1_ex2_* | ~15 |
| ex_bpu_ctrl.v | 输入端口改接 ex1_ex2_* | ~10 |
| ex_mem_req_ctrl.v | 输入端口改接 ex1_ex2_* | ~5 |
| KLDJ_csr.v | 输入端口改接 ex1_ex2_* | ~5 |
| pipe_ex_mem.v | 输入端口改接 ex1_ex2_* | ~10 |
| pipe_id_ex.v | stall 信号改名 | ~2 |
| KLDJ_top.v | 新增信号 + 重新连线 | ~60 |

### 不改的文件
| 文件 | 原因 |
|------|------|
| KLDJ_alu.v | 在 EX2 内部，逻辑不变 |
| KLDJ_idu.v | ID 阶段不变 |
| KLDJ_ifu.v | IF 阶段不变 |
| KLDJ_lsu.v | MEM 阶段不变 |
| KLDJ_regfile.v | 不变 |
| KLDJ_wbu.v | 不变 |
| pipe_if_id.v | flush/hold 接口不变 |
| pipe_mem_wb.v | 不变 |
| bpu.v | 不变 |
| mem_stage_top.v | 不变 |

---

## 7. 验证策略

### 第一阶段：功能验证
1. 跑 irom-v2.coe 测试程序，对比改造前后的 `wb_commit_pc` 和 `tb_ex_res`
2. 逐条指令对比 commit 记录，确保每条指令的结果一致
3. 检查内存最终状态一致

### 第二阶段：场景覆盖
逐一注入以下场景的测试用例：
- S1-S2：ALU 连续/依赖
- S3：Load-Use
- S4：Store 数据前递
- S5-S7：分支预测正确/方向错/目标错
- S8-S9：JAL/JALR
- S10：CSR 读写
- S11-S12：ecall/mret
- S13：MUL/DIV
- S14：连续分支
- S15：Store-Load 同地址

### 第三阶段：边界测试
- redirect 与 dependency_stall 同周期
- redirect 与 busy_stall 同周期
- 连续 redirect（back-to-back 分支）
- flush 时 EX2/MEM 正常推进
- x0 作为源/目的寄存器

---

## 8. 第一版保守策略

为保证正确性，第一版采用以下保守策略：

1. **不加 EX2→EX1 组合前递：** 连续 ALU 依赖 stall 1 拍
2. **dependency stall 统一处理：** 不区分 ALU/Load/CSR/MUL，统一 stall 1 拍
3. **不改 exu_op 编码：** 沿用现有编码
4. **不改 BPU：** 只改 BPU 更新信号的来源（从 EX2）
5. **不改 DRAM 接口：** 内存时序不变

后续优化方向：
- 加 EX2 简单 ALU 结果 → EX1 前递（减少 stall）
- 加 MEM load 结果 → EX1 前递（减少 load-use penalty）
- 按结果就绪时间分类 stall（只对未就绪的结果 stall）

---

## 9. 代码审阅补充（对照实际 RTL）

以下问题在逐文件审阅 KLDJ_top.v、ex_forward.v、ex_bpu_ctrl.v、pipe_ex_mem.v、pipe_id_ex.v、ex_mem_req_ctrl.v、KLDJ_csr.v 后发现。

### 9.1 【关键】三个模块的 valid 信号必须改接

改造后 EX2 阶段执行的是 EX1/EX2 寄存器中的指令，因此以下三处 valid 门控必须从 `id_ex_valid` 改为 `ex1_ex2_valid`：

**KLDJ_exu（KLDJ_top.v 第 391 行）：**
```verilog
// 改造前：
.valid       (id_ex_valid           )
// 改造后：
.valid       (ex1_ex2_valid         )
```

**KLDJ_csr（KLDJ_top.v 第 467-472 行）：**
```verilog
// 改造前：
.csr_we    (csr_we && id_ex_valid  )
.ecall_en  (is_ecall && id_ex_valid)
.mret_en   (is_mret && id_ex_valid )
// 改造后：
.csr_we    (csr_we && ex1_ex2_valid  )
.ecall_en  (is_ecall && ex1_ex2_valid)
.mret_en   (is_mret && ex1_ex2_valid )
```

**ex_mem_req_ctrl（KLDJ_top.v 第 449 行）：**
```verilog
// 改造前：
.id_ex_valid    (id_ex_valid      )
// 改造后：
.id_ex_valid    (ex1_ex2_valid    )
```

如果漏改，EX1 阶段的年轻指令会错误触发 CSR 副作用、内存写入或执行运算。这是**正确性关键**。

### 9.2 【关键】ex_forward 中旧 load_use_stall 逻辑必须处理

当前 ex_forward.v 第 54-57 行的 load_use_stall 检测的是 **IF/ID 依赖 ID/EX load**：

```verilog
assign load_use_stall = id_ex_valid && id_ex_load_op && (id_ex_rd_addr != 5'd0) &&
                        if_id_valid &&
                        ((id_reg_rs1_ren && (id_reg_rs1_addr == id_ex_rd_addr)) ||
                         (id_reg_rs2_ren && (id_reg_rs2_addr == id_ex_rd_addr)));
```

改造后这个逻辑的含义和位置都变了。新的 dependency stall 由 `ex1_hazard.v` 检测 **ID/EX1 依赖 EX1/EX2** 或 **ID/EX1 依赖 EX2/MEM load**。

**处理方式（二选一）：**
- **方案 A（推荐）：** 删除 ex_forward 中的 load_use_stall 逻辑，将该端口连接到新的 `ex1_dependency_stall`
- **方案 B：** 保留 ex_forward 的逻辑，但将其改为检测新的依赖关系（ID/EX1 依赖 EX1/EX2 load）

无论哪种方案，`pipe_id_ex` 的 `load_use_stall` 输入信号来源都必须从 ex_forward 改为新的 hazard unit。

### 9.3 【中等】pipe_ex_mem 输出信号命名

当前 pipe_ex_mem 输出信号名为 `ex_mem_*`（如 `ex_mem_valid`、`ex_mem_rd_addr`）。改造后这些信号代表的是 EX2/MEM 寄存器的输出。

**建议：** 在改造时将输出信号从 `ex_mem_*` 重命名为 `ex2_mem_*`，使信号名与流水级语义一致。这影响：
- ex_forward 中的前递比较端口
- ex1_hazard 中的依赖检测端口
- KLDJ_top 中的所有连线

如果不想大规模重命名，也可以保留 `ex_mem_*`，但在文档中明确标注其含义变为 EX2/MEM。

### 9.4 【中等】ex_forward 中 store 和 data2 选择的解码

ex_forward.v 第 76-84 行使用 `id_ex_exu_op` 判断指令类型：

```verilog
assign id_ex_rs2_to_data2 = ((id_ex_exu_op >= 18'ha) && (id_ex_exu_op <= 18'h19)) |
                            ((id_ex_exu_op >= 18'h25) && (id_ex_exu_op <= 18'h2c));
assign id_ex_store_op = ((id_ex_exu_op >= 18'h22) && (id_ex_exu_op <= 18'h24));
```

改造后 ex_forward 在 EX1 阶段，`id_ex_exu_op` 仍然来自 ID/EX1 寄存器，**信号本身可用**。但需确认：
- M-extension 编码 0x25-0x2c 与 define.v 一致（已确认一致）
- store 编码 0x22-0x24 与 define.v 一致（已确认一致）

这段逻辑可以保留在 EX1，因为它是组合逻辑且不产生副作用。EX1 输出的 `ex_store_wdata` 通过 pipe_ex1_ex2 传到 EX2。

### 9.5 【低】性能计数器代码被注释

KLDJ_top.v 第 584-618 行的性能计数器代码当前被注释（`/* ... */`）。如果需要在改造后统计新的 stall/redirect 事件，需要取消注释并更新事件信号定义。

### 9.6 【低】S13 场景描述与实际不符

技能文档第 444 行写的是"设计必须覆盖，但测试程序不含"，但实际上 irom-v2.coe 已包含 39 条 M-extension 指令。应改为"测试程序已覆盖"。

### 9.7 更新后的检查清单

在原有检查清单基础上，增加以下条目：

| # | 检查项 | 严重程度 |
|---|--------|---------|
| 1 | KLDJ_exu 的 `.valid` 改为 `ex1_ex2_valid` | **关键** |
| 2 | KLDJ_csr 的 valid 门控改为 `ex1_ex2_valid` | **关键** |
| 3 | ex_mem_req_ctrl 的 `.id_ex_valid` 改为 `ex1_ex2_valid` | **关键** |
| 4 | ex_forward 中旧 load_use_stall 逻辑删除或替换 | **高** |
| 5 | pipe_id_ex 的 `load_use_stall` 输入改接新 hazard unit | **高** |
| 6 | pipe_ex_mem 输出信号是否重命名为 `ex2_mem_*` | 中 |
| 7 | 性能计数器代码是否需要取消注释 | 低 |
| 8 | S13 场景描述更正 | 低 |
