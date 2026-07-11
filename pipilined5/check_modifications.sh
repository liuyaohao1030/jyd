#!/bin/bash
echo "=== 分支预测功能实现检查清单 ==="
echo ""

echo "1. 检查新增文件..."
files=(
  "kldj.srcs2/sources_1/imports/rtl/pipe/bpu.v"
  "kldj.srcs2/sources_1/imports/rtl/pipe/ex_bpu_ctrl.v"
  "kldj.srcs2/sources_1/imports/rtl/pipe/ex_mem_req_ctrl.v"
  "kldj.srcs2/sources_1/imports/rtl/pipe/ex_forward.v"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✓ $file exists"
  else
    echo "  ✗ $file missing"
  fi
done

echo ""
echo "2. 检查修改的文件..."
modified_files=(
  "kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_ifu.v"
  "kldj.srcs2/sources_1/imports/rtl/pipe/pipe_if_id.v"
  "kldj.srcs2/sources_1/imports/rtl/pipe/pipe_id_ex.v"
  "kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v"
)

for file in "${modified_files[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✓ $file exists"
  else
    echo "  ✗ $file missing"
  fi
done

echo ""
echo "3. 检查关键信号..."
grep -q "pred_taken" kldj.srcs2/sources_1/imports/rtl/stage/KLDJ_ifu.v && echo "  ✓ IFU has pred_taken" || echo "  ✗ IFU missing pred_taken"
grep -q "BPU_INDEX_WIDTH" kldj.srcs2/sources_1/imports/rtl/pipe/pipe_if_id.v && echo "  ✓ IF/ID has BPU_INDEX_WIDTH" || echo "  ✗ IF/ID missing BPU_INDEX_WIDTH"
grep -q "id_ex_pred_taken" kldj.srcs2/sources_1/imports/rtl/pipe/pipe_id_ex.v && echo "  ✓ ID/EX has pred signals" || echo "  ✗ ID/EX missing pred signals"
grep -q "u_bpu" kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v && echo "  ✓ Top has BPU instance" || echo "  ✗ Top missing BPU instance"
grep -q "u_ex_bpu_ctrl" kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v && echo "  ✓ Top has ex_bpu_ctrl" || echo "  ✗ Top missing ex_bpu_ctrl"
grep -q "if_static_jal" kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v && echo "  ✓ Top has JAL prediction" || echo "  ✗ Top missing JAL prediction"

echo ""
echo "4. 检查模块连接..."
grep -q "ex_mem_req_ctrl" kldj.srcs2/sources_1/imports/rtl/KLDJ_top.v && echo "  ✓ Top has ex_mem_req_ctrl" || echo "  ✗ Top missing ex_mem_req_ctrl"

echo ""
echo "=== 检查完成 ==="
