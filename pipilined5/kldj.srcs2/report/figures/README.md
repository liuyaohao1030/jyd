# 报告图片

把图片放在本目录，保留下面的基本文件名即可。支持 PDF、PNG、JPG、JPEG，正文会自动选择实际存在的格式。

- `cpu_architecture`：CPU 架构图
- `dual_port_bram_sim`：双端口 BRAM 功能仿真图
- `bpu_sim`：BPU 功能仿真图
- `ecall_mret_sim`：ecall/mret 功能仿真图

图片未提供时，`main.tex` 会生成带占位框的可编译版本。图片补齐后，在 `report` 目录执行两遍 `xelatex main.tex`，或直接执行 `make`。
