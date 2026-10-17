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

TB 使用一个 initial，明确分开写 H=W=1、4、16 三段。三段都送相同的16包512bit数据，LAST都在第16包，不由H/W决定输入长度。mode固定为0。每段直接按第t拍、第r路来自第(t-r)包计算期望值，范围外补0，不读取DUT内部寄存器。

## 模块职责

- CTRL的物理宽度固定16路，第r路固定延迟r拍；H/W和mode不改变数据内容、补0、VALID或输入LAST对齐。
- rpt_dat_in_cnt只统计实际FIFO读取包数，START接受时清0。三段同为16包，因此三段计数均为16；不会用H乘W推算。
- rpt_cpt_done等待CTRL输入尾部送完及SA最终输出LAST到达，先到的条件用内部标志记住。H/W可能通过SA的LAST时刻影响完成；CTRL不直接按H/W计时，也不增加SA流水空闲端口。
- rpt_error为累计错误标志，等于错误次数非0；rpt_error_state[2:0]为错误次数。任务中FIFO输入LAST尚未读入就收到SA完成LAST，判为协议错误；连续同一次LAST只计一次，次数到7饱和。复位或有效新START清零，DONE或关闭EN后保留。正常FIFO等待和气泡不报错，不因错误改变数据/完成逻辑。rpt_cpt_error为寄存器名，通过rpt_error_state接口读回，字索引0x103、CPU字节偏移0x40C，低3位有效，高29位读0。

## 当前TB覆盖

- 三种H/W均读取相同16包，检查31个采样列的全部16路数据及前后补0。
- 检查FIFO读使能、VALID、物理第15路LAST、逐拍输入计数、正常任务零错误上报。
- 检查启动后的同步状态和计数清0；输入尾部送完后，未收到SA LAST时不能报告DONE。
- 检查SA LAST到达后产生单拍DONE，以及START保持高不重复启动。
- 每拍打印十六进制INPUT、EXPECTED和ACTUAL；总线左侧为第15路，右侧为第0路。

当前测试固定mode=0、连续输入；前版四模式、气泡及中止恢复等测试已存档，不属于当前精简TB的覆盖范围。
SA反馈由TB模拟，本单测不验证SA矩阵乘加。真实FIFO_IN+CTRL+SA的历史54个H=W联调用例报告保留在工作台。

## 接入SA

```systemverilog
.data_out_last(dat_out_vld && dat_out_last)
```

顶层接口保持原设计，仅使用data_out_last反馈，不含sa_pipeline_empty输入。尺寸配置需在START前稳定并保持到DONE。
## 错误上报与寄存器源码

rtl/reg_list.sv 与 rtl/ahb_slave_regmap.sv 同步了3bit错误次数接口。tb/tb_reg_list.sv 和 tb/tb_ahb_slave_regmap.sv 覆盖0～7全部计数值、只读保护及高29位补0。AHB封装依赖共享AHB_SLAVE模块（合法字地址上限0x106）；默认Makefile仍只运行CTRL独立TB。reg_list仅实时读回次数，不自行增加计数或清零；状态接入AHB域前需完成CDC。

## 实际错误检测范围

目前只检测提前SA完成LAST协议错误，包括与FIFO最后一包同拍的提前反馈。错误仅上报，不中止任务。尚未定义FIFO缺数、超时或算术数值错误检测；不能把合法FIFO空拍直接计错。错误次数大于7保持7，不回绕。错误次数由CTRL产生，reg_list只读回，不自己计数。

独立错误标志接口：`reg_list`与`ahb_slave_regmap`各增加1bit输入`rpt_error`，封装逐级传入。错误标志独立分配RO字地址0x106、CPU字节偏移0x418，返回{31'b0, rpt_error}，写入忽略；`rpt_cpt_error`仍返回`{29'b0, rpt_error_state}`。错误次数仍由CTRL生成。
