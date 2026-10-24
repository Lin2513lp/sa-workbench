# 保留原接口的最小控制标记修正

以零点前版本为参照，保留两个向量标记的逻辑作用，SA_TOP 对外保持用户原定的 18 个端口。TOP 只连接 CTRL 的数据与控制，不给 SA 旁接 FIFO 读使能或 FIFO 末拍。

## 代码变化

- `tpu_ctrl.sv`：通过已有 `dat_in_vld/dat_in_last` 输出 lane0 向量有效和末向量标记。原物理 Skew 有效和 lane15 尾部保留为内部信号，DONE 等待条件不变。
- `sa_top.sv`：已有 VALID/LAST 在内部连接原收集器；增加 15 位单比特 valid 历史，恢复原 PE 共享有效窗口。没有新增数值缓存或结果延迟。
- PE、SA_CTRL、Skew 数值数据通路及零点前输出收集器逐文件保持原样。

已有 VALID/LAST 的时序含义有明确调整：它们现在标记 lane0 向量，VALID 为 0 时其他 Skew 路仍可能有数据。不是只修改变量名称，也不能把这两根控制波形说成完全不变。数值输出、结果有效/LAST 和任务完成时序经逐拍对照一致。

## 接口约束

26 个编译设计模块的接口声明已核对，见 `module_interface_audit.json`：SA_TOP 与用户八月原定 18 端口一致；其余模块与零点前接口声明一致，无新增或删减。验证用 SVA 检查器也保持原 17 个形式端口和原 5 条性质，仅改变 bind 接线。

## TB 最小变更

| TB | 处理 |
|---|---|
| TOP smoke | 恢复零点前原文件，SHA-256 为 `43f0f372839e8637232918cbbeafd27310c2b07a90e3e5fa7fbc03527c6a380f`。DONE 时 AXI LAST 已接收、发送计数为 7 的原检查均保留 |
| SA_CTRL、PE 阵列、OUTPUT_COLLECTOR 单元 TB | 与零点前文件逐字节一致，重新运行通过 |
| INT4、INT8、FP16、FP32、Multi 包装 TB | 与零点前文件逐字节一致 |
| SA 公共驱动器与 Smoke | 仅调整 DUT 端口接线；原输入刺激、算术期望和输出时刻检查不变。原 empty 检查继续观察同一个 raw-valid 归约表达式 |
| CTRL standalone | 调整新外部标记的检查，保留全部 512-bit Skew 数据检查，并额外保留内部原有效窗口和物理尾部检查；检查数由 2059 增为 2245 |
| DONE clear | 代码内容保持原样，96 项检查通过 |

今天早些时候为适配被撤销的结果缓存方案，TOP TB 的 DONE 检查曾被调整；那个 `8f200…` 版本仅作历史记录。当前已恢复真正零点前的 `43f0…` 原 TB，并重新测试，不沿用先前结果。

## 本次实际验证

- 真正零点前 TOP TB：Questa 与虚拟机 VCS 均 **107 项通过**，4 拍输入、7 拍输出、16 个独立算术结果、唯一 LAST、报告与 W1C。
- 6 组 SA 顶层和 3 个原单元测试：Questa 与 VCS 均通过。四种精度各 9 任务/1008 结果，Multi 为 27 任务/3024 结果，保留原气泡与有效零值检查。
- 双真实 FIFO＋CTRL＋SA 对照：108 任务、332244 项逐拍等价检查及 46755 项独立数学/时序检查通过，5292 个结果含 2094 个合法零值。
- CTRL 与原端口 SVA：2245 项通过；DONE clear 与 SVA：96 项通过。
- 当前 VCS 实测 AXI 首拍 2536.250 ns，末拍 2551.250 ns，CTRL DONE 2566.250 ns。
- 已交付共享源码重新编译通过。Verilator 保留原 50 条 PE/SA/CRG 提示，未作新的全芯片签核结论。

当前 SA 原生 Verdi 波形每组仅展示 18 个外部端口；TOP 原生波形展示 36 个外部端口。截图来自本次 FSDB，通过后台虚拟机 guest 命令取得。

源码/日志哈希见 `final_candidate_manifest.json`、`results.json`、`shared_delivery.json`；接口核对见 `module_interface_audit.json`；原生证据见 `vm_sa/` 和 `vm_top/`。线上发布另以 `publication.json`、`online_verification.json` 的实际生成记录为准。
