# SA_TOP Design Workbench

## 在线使用

[打开 SA_TOP 设计工作台](https://lin2513lp.github.io/sa-workbench/)

这是一个面向 16×16 脉动阵列（Systolic Array）的独立设计工作台，可直接通过 GitHub Pages 在浏览器中使用，无需安装软件。

## 工作台内容

- **设计报告**：SA_TOP 总体架构、外部接口、时钟复位、RegMap CDC、权重加载、PE 阵列互连与输出收集设计。
- **代码设计**：在线浏览当前工程的 `Makefile`、11 个 RTL 文件和 11 个 testbench 文件。
- **仿真波形**：收录 INT4、INT8、FP16、FP32 和 multi 连续任务的顶层回归波形与检查结论。
- **WaveDrom 时序图**：展示 B 权重跨时钟域加载、A 数据流水以及不同计算精度下的输出时序。
- **材料与笔记**：从矩阵乘法、局部 MAC、partial sum 到 16×16 阵列数据流的图示化讲解，并包含可交互流水演示。

## 当前实现

SA_TOP 由以下主要模块组成：

- `sa_top`
- `sa_ctrl`
- `pe_array_16x16`
- `output_collector`
- `pe_mp/PE_MP_v1`

顶层回归覆盖 smoke、INT4、INT8、FP16、FP32 和 multi 六类场景；Questa 与 Icarus 回归均为 6/6 PASS。工作台内同时注明了当前 INT4/INT8 数据路径、浮点特殊值和动态尺寸等尚待扩展的验证边界。

## 目录说明

- `sa_workbench.html`：完整设计工作台入口。
- `sa_code_design.html`：RTL/TB 代码浏览页。
- `sa_sim_waveforms.html`：仿真波形浏览页。
- `sa_wavedrom_int4.html`：多精度 WaveDrom 时序图。
- `code/`：工作台展示的 RTL、TB 和构建文件快照。
- `sim/`：五组顶层仿真波形。

本仓库为纯静态页面，使用 `.nojekyll` 保留原始目录和文件路径。
