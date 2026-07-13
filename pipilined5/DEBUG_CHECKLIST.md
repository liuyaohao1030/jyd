# 程序跑飞调试检查清单

## 检查项目

### 1. 复位和初始化
- [ ] PC初始值是否为0x80000000
- [ ] 所有流水线寄存器的valid初始值是否为0
- [ ] 指令存储器是否正确加载irom-v2.coe

### 2. 第一条指令的执行路径
第一条指令应该经历：
```
周期0: rst=1, 所有寄存器复位
周期1: IF取0x80000000, ID=NOP, EX1=NOP, EX2=NOP, MEM=NOP, WB=NOP
周期2: IF取0x80000004, ID=第1条指令, EX1=NOP, EX2=NOP, MEM=NOP, WB=NOP
周期3: IF取0x80000008, ID=第2条指令, EX1=第1条指令(前递), EX2=NOP, MEM=NOP, WB=NOP
...
```

### 3. Valid信号传播路径
```
if_id_valid → id_ex_valid → ex1_ex2_valid → ex2_mem_valid → mem_wb_valid
```

### 4. Stall和Flush的优先级
优先级: rst > redirect > dependency_stall > ex2_stall > 正常推进

### 5. 关键信号检查
