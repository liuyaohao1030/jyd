# CPU跑飞Bug修复 - 快速总结

## 🐛 Bug原因
**GHR（Global History Register）在分支预测错误时没有恢复机制**

gshare分支预测器使用 `PHT_index = PC_index XOR GHR` 来查询PHT表。当分支预测错误时：
- GHR被投机更新污染了（基于错误的预测结果）
- 后续所有分支预测都使用错误的GHR查询PHT
- 导致预测准确率暴跌，CPU不断redirect，完全"跑飞"

## ✅ 修复方案
在分支预测错误时，恢复GHR到正确的值。

### 修改的文件

1. **`pipilined5/kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v`** (+19行)
   - 添加 `redirect` 和 `redirect_pht_idx` 输入端口
   - 在GHR更新逻辑中添加redirect处理：
     ```verilog
     end else if(redirect) begin
         // 恢复GHR到正确状态
         ghr <= redirect_pht_idx ^ update_btb_idx;
     end else if(update_valid) begin
     ```

2. **`pipilined5/kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v`** (+2行)
   - 连接 `ex_redirect` 到 BPU
   - 连接 `ex1_ex2_pred_pht_idx` 到 BPU

## 📋 详细文档
查看完整分析：[GHR_BUG_FIX_REPORT.md](GHR_BUG_FIX_REPORT.md)

## 🚀 下一步

### 1. 重新综合和实现
```bash
在Vivado中：
- Run Synthesis
- Run Implementation  
- Generate Bitstream
```

### 2. 上板测试
下载新的比特流到FPGA，运行之前会跑飞的程序。

### 3. 验证要点
- ✅ 程序能正常执行完成
- ✅ 输出结果正确
- ✅ 不再频繁redirect

### 4. ILA调试（如果还有问题）
观察关键信号：
- `ex_redirect` - 是否还是频繁拉高
- `if_pc` - PC变化是否正常
- `ex1_ex2_pred_pht_idx` - 分支预测索引

## 💡 为什么这个Bug这么致命？

```
错误的GHR → 错误的PHT索引 → 错误的预测 → 更错误的GHR → 恶性循环
```

一次预测错误会导致后续所有预测都错误，CPU陷入"预测-错误-redirect"的死循环。

## ⚠️ 重要提示

这个bug是**gshare分支预测器的经典问题**。任何使用投机更新的预测器（GHR、RAS等）都需要在预测错误时的恢复机制。

---

**修复时间**: 2026-07-14  
**修复人**: Claude (Kiro AI)  
**Bug类型**: 分支预测器GHR恢复缺失  
**影响**: 导致CPU完全"跑飞"，无法正常执行程序
