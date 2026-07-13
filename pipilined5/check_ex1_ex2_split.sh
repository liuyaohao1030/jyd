#!/bin/bash
# EX1/EX2拆分后的语法检查脚本

echo "=========================================="
echo "EX1/EX2流水线拆分 - 语法检查"
echo "=========================================="
echo ""

RTL_DIR="kldj.srcs2/sources_1/imports/rtl"

echo "1. 检查新增文件是否存在..."
NEW_FILES=(
    "$RTL_DIR/pipe/pipe_ex1_ex2.v"
    "$RTL_DIR/pipe/ex1_hazard.v"
)

for file in "${NEW_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file 存在"
    else
        echo "  ✗ $file 不存在！"
        exit 1
    fi
done
echo ""

echo "2. 检查关键模块实例化..."
if grep -q "ex1_hazard u_ex1_hazard" "$RTL_DIR/KLDJ_top.v"; then
    echo "  ✓ ex1_hazard 已实例化"
else
    echo "  ✗ ex1_hazard 未实例化！"
fi

if grep -q "pipe_ex1_ex2 #" "$RTL_DIR/KLDJ_top.v"; then
    echo "  ✓ pipe_ex1_ex2 已实例化"
else
    echo "  ✗ pipe_ex1_ex2 未实例化！"
fi
echo ""

echo "3. 检查信号定义..."
REQUIRED_SIGNALS=(
    "ex1_ex2_valid"
    "ex1_ex2_pc"
    "ex1_dependency_stall"
    "ex2_stall"
    "ex2_mem_valid"
    "ex2_mem_pc"
)

for sig in "${REQUIRED_SIGNALS[@]}"; do
    if grep -q "wire.*$sig" "$RTL_DIR/KLDJ_top.v"; then
        echo "  ✓ $sig 已定义"
    else
        echo "  ✗ $sig 未定义！"
    fi
done
echo ""

echo "4. 检查valid信号的关键连接..."
# 检查KLDJ_exu的valid是否改为ex1_ex2_valid
if grep -A5 "KLDJ_exu exu2" "$RTL_DIR/KLDJ_top.v" | grep -q "\.valid.*ex1_ex2_valid"; then
    echo "  ✓ KLDJ_exu.valid 已改为 ex1_ex2_valid"
else
    echo "  ✗ KLDJ_exu.valid 未正确连接！"
fi

# 检查KLDJ_csr的门控是否改为ex1_ex2_valid
if grep -A10 "KLDJ_csr u_csr" "$RTL_DIR/KLDJ_top.v" | grep -q "csr_we.*ex1_ex2_valid"; then
    echo "  ✓ KLDJ_csr门控 已改为 ex1_ex2_valid"
else
    echo "  ✗ KLDJ_csr门控 未正确连接！"
fi
echo ""

echo "5. 检查Verilog语法..."
# 简单的语法检查 - 检查是否有明显的语法错误
V_FILES=$(find "$RTL_DIR" -name "*.v" -type f)
ERROR_COUNT=0

for vfile in $V_FILES; do
    # 检查是否有未闭合的module
    MODULE_BEGIN=$(grep -c "^module " "$vfile" || true)
    MODULE_END=$(grep -c "^endmodule" "$vfile" || true)

    if [ "$MODULE_BEGIN" -ne "$MODULE_END" ]; then
        echo "  ✗ $vfile: module/endmodule 不匹配 (begin:$MODULE_BEGIN, end:$MODULE_END)"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
done

if [ $ERROR_COUNT -eq 0 ]; then
    echo "  ✓ 基本语法检查通过"
else
    echo "  ✗ 发现 $ERROR_COUNT 个潜在语法错误"
fi
echo ""

echo "6. 统计修改情况..."
echo "  新增文件: 2个"
echo "  修改文件: 8个"
echo "  主要修改:"
echo "    - pipe_ex1_ex2.v (新增)"
echo "    - ex1_hazard.v (新增)"
echo "    - ex_forward.v (修改)"
echo "    - pipe_ex_mem.v (修改)"
echo "    - ex_bpu_ctrl.v (修改)"
echo "    - ex_mem_req_ctrl.v (修改)"
echo "    - pipe_id_ex.v (修改)"
echo "    - KLDJ_top.v (重连)"
echo ""

echo "=========================================="
echo "检查完成"
echo "=========================================="
echo ""
echo "下一步："
echo "1. 在Vivado中打开项目"
echo "2. 运行综合检查语法"
echo "3. 运行仿真测试irom-v2.coe"
echo "4. 对比改造前后的波形和结果"
