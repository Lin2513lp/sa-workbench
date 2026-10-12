# TPU_CTRL 独立测试工程

本目录的 RTL 来自已通过联调的精简版 CTRL。`tb/tb_tpu_ctrl.sv` 是可直接运行的自检 TB，不需要 SA、FIFO RTL 或 Python。

## 在虚拟机中运行

沿用之前 SA 工程的运行方式，在已加载 Synopsys 工具环境的终端执行：

```bash
cd /mnt/hgfs/share/tpu/tpu/TPU_CTRL
make                    # 等同于 make all：编译、运行、自检、生成 FSDB
make verdi              # 等同于 make wave：在虚拟机图形桌面终端打开 Verdi
make summary            # 查看 CTRL_UNIT_PASS 检查统计
```

其他入口：

```bash
make run DUMP=none      # 不导出波形，不需要 Verdi PLI
make run DUMP=vcd       # 标准 VCD 波形
make compile           # 只编译 TB
make rtl               # 只编译 CTRL 的可综合层次
make regress           # 运行本工程的完整单元测试并显示结果
make help
make env
```

默认 `TOP=tb_tpu_ctrl`、`DUMP=fsdb`。默认许可服务器与现有 TPU_CRG 工程一样是 `27000@localhost.localdomain`，可用 `make LICENSE_SERVER=...` 改用自己的服务器。许可检测脚本复用现有工程方式，先查询状态，需要时启动已安装的本地服务；不修改许可文件。

VCS 构建时需要符号链接，VMware hgfs 共享目录不支持，所以构建文件与原始日志、波形生成于：

```text
$HOME/tpu_ctrl_runs/TPU_CTRL/
├── build/vcs/tb_tpu_ctrl/
├── logs/tb_tpu_ctrl_compile.log
├── logs/tb_tpu_ctrl_run.log
└── waves/tb_tpu_ctrl.fsdb
```

编译和运行日志、生成的波形自动复制到共享目录 `results/`。`make clean` / `make clean-all` 只清除虚拟机本地生成物，不删除 RTL/TB，也保留共享 `results/` 以便查阅。

## 文件说明

```text
Makefile
rtl/filelist.f
rtl/tpu_ctrl.sv          # 任务、FIFO 读入计数、LAST 记录与 DONE 判断
rtl/tpu_ctrl_sync.sv     # CPU EN/START 两级同步
rtl/tpu_ctrl_skew.sv     # 第 r 路延迟 r SYS 拍，无效路补零
tb/tb_tpu_ctrl.sv        # 独立逐拍 oracle 和 directed stimulus
scripts/check_license.sh
```

TB 每个时钟从实际 FIFO 读取记录中预测 16 路数据，不使用 DUT 内部移位寄存器来计算期望值。它同时检查输出 valid、物理第15路 LAST、读使能条件、两级同步、输入计数与 DONE 控制。

## 覆盖的场景

- 使能但未 START 的空闲阶段不读 FIFO。
- 四种精度模式分别设置 H=W=1、4、16；CTRL 的物理 skew 不随 H/W/mode 改变。
- 连续输入和输入气泡；气泡时移位链继续推进，空白路为零。
- 最后向量读完后停止取 FIFO，即使下一任务的头部可见也不提前读取。
- START 保持高不重复启动；任务中新的 START 上升沿不重置当前任务。
- 输入未完成时的错误提前 SA LAST 被忽略。
- 输入尾巴已结束、SA LAST 已到但流水未空，DONE 继续等待。
- H=W=4 中 SA LAST/EMPTY 先于物理输入尾巴到达，CTRL 记住 LAST 并等待尾巴。
- 每个正常任务只产生一次 DONE；输入计数正确，错误接口保持保留的零值。
- 关闭 EN 中止在途任务并清空 skew；复位后重新执行任务。

SA 的 `data_out_last` 和 `sa_pipeline_empty` 在此 TB 中由驱动模拟，因此这份单元测试不能验证矩阵数值或 SA 内部流水。真实 FIFO_IN+CTRL+SA 的 54 个 H=W 联调用例由独立的集成 TB 验证。本工程也不宣称 CDC 亚稳态概率、形式证明或综合时序已完成验证。

## 接入 SA 时

CTRL 新输入需要按已更新的集成顶层连接：

```systemverilog
.data_out_last(dat_out_vld && dat_out_last),
.sa_pipeline_empty(sa_pipeline_empty)
```

SA 的 `sa_pipeline_empty` 来自底部原始 PE valid 的归约取反。DONE 还必须同时满足输入尾巴结束和最终输出 LAST，因此启动阶段的空流水不会触发完成。
