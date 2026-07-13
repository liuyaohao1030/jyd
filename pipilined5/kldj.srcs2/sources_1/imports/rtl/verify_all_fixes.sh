#!/bin/bash
echo "=== 验证所有Bug修复状态 ==="
echo ""

echo "✓ 检查1: pipe_ex1_ex2模块是否存在"
if grep -q "pipe_ex1_ex2" KLDJ_top.v; then
    echo "  ✅ pipe_ex1_ex2模块已实例化"
else
    echo "  ❌ 缺少pipe_ex1_ex2模块"
fi

echo ""
echo "✓ 检查2: ex1_hazard模块是否存在"
if grep -q "ex1_hazard" KLDJ_top.v; then
    echo "  ✅ ex1_hazard模块已实例化"
else
    echo "  ❌ 缺少ex1_hazard模块"
fi

echo ""
echo "✓ 检查3: EXU的valid信号"
if grep -q "\.valid.*ex1_ex2_valid" KLDJ_top.v; then
    echo "  ✅ KLDJ_exu.valid = ex1_ex2_valid"
else
    echo "  ❌ EXU的valid信号错误"
fi

echo ""
echo "✓ 检查4: pipe_ex_mem的输入"
if grep -q "\.ex1_ex2_valid.*ex1_ex2_valid" KLDJ_top.v; then
    echo "  ✅ pipe_ex_mem接收ex1_ex2_*信号"
else
    echo "  ❌ pipe_ex_mem输入信号错误"
fi

echo ""
echo "✓ 检查5: pipe_ex_mem的输出"
if grep -q "\.ex2_mem_valid.*ex2_mem_valid" KLDJ_top.v; then
    echo "  ✅ pipe_ex_mem输出ex2_mem_*信号"
else
    echo "  ❌ pipe_ex_mem输出信号错误"
fi

echo ""
echo "✓ 检查6: 性能计数器Bug 2"
if grep -q "perf_event_load_use_stall = ex1_dependency_stall" KLDJ_top.v; then
    echo "  ✅ Bug 2已修复"
elif grep -q "perf_event_load_use_stall = load_use_stall" KLDJ_top.v; then
    echo "  ❌ Bug 2未修复（使用了不存在的load_use_stall）"
else
    echo "  ⚠️  性能计数器被注释掉了"
fi

echo ""
echo "✓ 检查7: 性能计数器Bug 3"
if grep -q "perf_event_load.*ex1_ex2_valid" KLDJ_top.v; then
    echo "  ✅ Bug 3已修复"
elif grep -q "perf_event_load.*id_ex_valid.*ex_stall" KLDJ_top.v; then
    echo "  ❌ Bug 3未修复（使用了错误的信号）"
else
    echo "  ⚠️  性能计数器被注释掉了"
fi

echo ""
echo "=== 检查完成 ==="
