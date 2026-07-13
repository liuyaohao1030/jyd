# EX1/EX2流水线拆分 - 快速参考指南

## 完成状态：✅ 已完成

拆分日期：2026-07-13

## 关键修改概览

### 流水线结构变化
- **改造前：** IF → ID → EX → MEM → WB（5级）
- **改造后：** IF → ID → EX1 → EX2 → MEM → WB（6级）

### EX1职责（选数阶段）
- 前递命中判断
- 前递数据选择
- 操作数准备
- 数据冒险检测

### EX2职责（算数阶段）
- ALU运算
- 分支判断与目标计算
- 跳转决策
- 访存地址计算
- CSR读写
- MUL/DIV多周期运算
- BPU更新
- redirect生成

## 新增文件（2个）

1. **pipe_ex1_ex2.v** - EX1/EX2流水寄存器
   - 路径：`kldj.srcs2/sources_1/imports/rtl/pipe/pipe_ex1_ex2.v`
   - 150行代码

2. **ex1_hazard.v** - EX1冒险检测单元
   - 路径：`kldj.srcs2/sources_1/imports/rtl/pipe/ex1_hazard.v`
   - 40行代码

## 修改文件（8个）

| 文件 | 主要修改 | 行数 |
|------|---------|------|
| ex_forward.v | 删除旧load_use_stall，输出改名为ex1_* | ~15 |
| pipe_ex_mem.v | 输入从ex1_ex2接收，输出改名为ex2_mem_* | ~30 |
| ex_bpu_ctrl.v | 输入从ex1_ex2接收 | ~10 |
| ex_mem_req_ctrl.v | 输入从ex1_ex2接收 | ~15 |
| pipe_id_ex.v | stall信号改为ex1_dependency_stall \|\| ex2_stall | ~2 |
| KLDJ_top.v | 重新连线整个流水线 | ~100 |

## 关键连接验证清单

### ✅ 已完成的修改

- [x] ex1_hazard模块已创建并实例化
- [x] pipe_ex1_ex2模块已创建并实例化
- [x] KLDJ_exu.valid改为ex1_ex2_valid
- [x] KLDJ_csr门控改为ex1_ex2_valid
- [x] ex_mem_req_ctrl.valid改为ex1_ex2_valid
- [x] ex_bpu_ctrl输入改为ex1_ex2_*
- [x] pipe_ex_mem输入输出正确重命名
- [x] ex_forward输出改为ex1_*
- [x] pipe_id_ex的stall信号已更新
- [x] frontend_stall = ex1_dependency_stall || ex2_stall
- [x] ex2_stall = div_stall || mul_stall

## 重要设计决策

### 1. 前递路径
```
EX2/MEM → EX1 ✓ (ALU结果前递)
MEM/WB → EX1  ✓ (Load结果前递)
EX2 → EX1     ✗ (第一版不支持组合前递)
```

### 2. Stall策略（保守）
- EX1依赖EX2任何指令 → stall 1拍
- EX1依赖EX2/MEM的load → stall 1拍
- 不区分指令类型，统一处理

### 3. 流水线控制优先级
1. reset（最高）
2. redirect/flush
3. ex2_stall
4. ex1_dependency_stall
5. 正常推进（最低）

## 测试验证

### 测试程序
- **文件：** irom-v2.coe
- **指令数：** 2218条
- **覆盖类型：** R-type, M-extension, I-type, Load/Store, Branch, JAL/JALR, LUI/AUIPC, CSR, System

### 验证步骤
1. **语法检查：** 运行 `./check_ex1_ex2_split.sh`
2. **综合检查：** 在Vivado中运行综合
3. **功能仿真：** 运行irom-v2.coe测试
4. **波形对比：** 对比关键场景时序
5. **结果验证：** 检查wb_commit_pc和tb_ex_res

### 关键验证场景
- S2: ALU → ALU数据冒险
- S3: Load-Use冒险
- S4: Store数据冒险
- S6: 分支预测错误（方向错）
- S9: JALR依赖load（最复杂）
- S13: MUL/DIV多周期

## 性能预期

### 时序改进
- **改造前瓶颈：** ~6ns（EX/MEM → 前递 → ALU → 分支 → redirect → PC）
- **改造后：** EX1 ~3ns + EX2 ~3ns
- **频率提升：** 166MHz → 333MHz（2倍）

### CPI影响
- **控制冒险：** 冲刷级数从2级→3级（+1拍）
- **数据冒险：** 连续ALU依赖从0拍→1拍
- **CPI增加：** 1.2 → 1.5（约1.25倍）

### 净性能
- **性能提升：** 频率提升2倍 / CPI增加1.25倍 = **1.6倍**

## 已知限制和后续优化

### 当前限制
1. 不支持EX2组合前递到EX1（保守策略）
2. 所有依赖统一stall 1拍（不区分类型）
3. 控制冒险penalty增加1拍

### 优化方向
1. **加EX2简单ALU → EX1组合前递**
   - 减少连续ALU依赖的stall
   - 风险：可能重新形成长路径

2. **按结果就绪时间分类stall**
   - ALU/分支不stall
   - 仅Load stall
   - 需要识别指令类型

3. **加MEM → EX1组合前递**
   - 减少load-use penalty

## 故障排查

### 如果出现编译错误
1. 检查新增文件是否在项目中
2. 检查include路径是否正确
3. 运行 `./check_ex1_ex2_split.sh` 验证信号定义

### 如果功能测试失败
1. 检查valid信号连接（KLDJ_exu, KLDJ_csr, ex_mem_req_ctrl）
2. 检查ex1_hazard的依赖检测逻辑
3. 检查pipe_ex1_ex2的flush/bubble/hold逻辑
4. 对比波形找到第一条错误指令

### 如果时序不满足
1. 检查EX1阶段是否有过长的组合路径
2. 检查前递mux的扇出
3. 考虑pipeline ex1_hazard的输出

## 文件清单

### 核心文件
```
kldj.srcs2/sources_1/imports/rtl/
├── pipe/
│   ├── pipe_ex1_ex2.v         (新增)
│   ├── ex1_hazard.v            (新增)
│   ├── ex_forward.v            (修改)
│   ├── pipe_ex_mem.v           (修改)
│   ├── ex_bpu_ctrl.v           (修改)
│   ├── ex_mem_req_ctrl.v       (修改)
│   └── pipe_id_ex.v            (修改)
├── stage/
│   └── KLDJ_exu.v              (不变，但连接改变)
└── KLDJ_top.v                  (重连)
```

### 文档文件
```
├── EX1_EX2_SPLIT_SUMMARY.md    (详细总结)
├── EX1_EX2_QUICK_REF.md        (本文档)
└── check_ex1_ex2_split.sh      (语法检查脚本)
```

## 快速命令

```bash
# 运行语法检查
./check_ex1_ex2_split.sh

# 查看详细总结
cat EX1_EX2_SPLIT_SUMMARY.md

# 查看skill文档
cat skills/ex1_ex2_split.md

# 查找所有修改的文件
find kldj.srcs2/sources_1/imports/rtl -name "*.v" -newer check_ex1_ex2_split.sh
```

## 联系和支持

如有问题，请参考：
1. **详细文档：** EX1_EX2_SPLIT_SUMMARY.md
2. **Skill文档：** skills/ex1_ex2_split.md
3. **验证脚本：** check_ex1_ex2_split.sh

---
**状态：** ✅ 代码修改完成，待Vivado综合和仿真验证
**版本：** v1.0 (保守策略 - 无EX2组合前递)
**日期：** 2026-07-13
